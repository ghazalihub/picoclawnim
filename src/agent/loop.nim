import std/os
import std/asyncdispatch
import std/json
import std/strutils
import std/times
import std/tables
import std/options
import std/syncio
import ../bus
import ../config
import ../logger
import ../utils
import ../providers/types
import ../providers/factory
import ../tools/base
import session
import memory
import context
import ../skills
import ../tools/message
import ../tools/spawn
import ../tools/base as tools_base

type
  AgentLoop* = ref object
    bus: MessageBus
    provider: Provider
    workspace: string
    model: string
    contextWindow: int
    maxIterations: int
    sessions: SessionManager
    tools: ToolRegistry
    memory: MemoryStore
    contextBuilder: ContextBuilder
    summarizing: Table[string, bool]

proc newAgentLoop*(cfg: Config, msgBus: MessageBus, provider: Provider): AgentLoop =
  let workspace = cfg.getWorkspacePath()
  let sm = newSessionManager(workspace / "sessions")
  let ms = newMemoryStore(workspace)
  let tr = newToolRegistry()
  let cb = newContextBuilder(workspace)
  cb.setToolsRegistry(tr)

  AgentLoop(
    bus: msgBus,
    provider: provider,
    workspace: workspace,
    model: cfg.agents.defaults.model,
    contextWindow: cfg.agents.defaults.max_tokens,
    maxIterations: cfg.agents.defaults.max_tool_iterations,
    sessions: sm,
    tools: tr,
    memory: ms,
    contextBuilder: cb,
    summarizing: initTable[string, bool]()
  )

proc registerTool*(al: AgentLoop, t: Tool) =
  al.tools.register(t)

proc getStartupInfo*(al: AgentLoop): JsonNode =
  let tools = al.tools.tools
  var toolNames = newJArray()
  for name in tools.keys: toolNames.add(%name)

  result = newJObject()
  result["tools"] = %*{"count": tools.len, "names": toolNames}
  result["skills"] = getSkillsInfo(al.contextBuilder.skillsLoader)

proc estimateTokens(messages: seq[Message]): int =
  result = 0
  for m in messages:
    result += m.content.len div 4

proc summarizeBatch(al: AgentLoop, batch: seq[Message], existingSummary: string): Future[string] {.async.} =
  var prompt = "Provide a concise summary of this conversation segment, preserving core context and key points.\n"
  if existingSummary != "":
    prompt &= "Existing context: " & existingSummary & "\n"
  prompt &= "\nCONVERSATION:\n"
  for m in batch:
    prompt &= m.role & ": " & m.content & "\n"

  try:
    let resp = await al.provider.chat(@[Message(role: "user", content: prompt)], @[], al.model, %*{"max_tokens": 1024, "temperature": 0.3})
    return resp.content
  except Exception as e:
    logger.error("agent", "Summarization batch failed", {"error": e.msg})
    return ""

proc summarizeSession(al: AgentLoop, sessionKey: string) {.async.} =
  let history = al.sessions.getHistory(sessionKey)
  let summary = al.sessions.getSummary(sessionKey)

  if history.len <= 4: return

  let toSummarize = history[0..^5]
  var validMessages: seq[Message] = @[]
  for m in toSummarize:
    if m.role == "user" or m.role == "assistant":
      validMessages.add(m)

  if validMessages.len == 0: return

  var finalSummary = ""
  if validMessages.len > 10:
    let mid = validMessages.len div 2
    let s1 = await al.summarizeBatch(validMessages[0..<mid], "")
    let s2 = await al.summarizeBatch(validMessages[mid..^1], "")

    let mergePrompt = "Merge these two conversation summaries into one cohesive summary:\n\n1: " & s1 & "\n\n2: " & s2
    try:
      let resp = await al.provider.chat(@[Message(role: "user", content: mergePrompt)], @[], al.model, %*{"max_tokens": 1024, "temperature": 0.3})
      finalSummary = resp.content
    except:
      finalSummary = s1 & " " & s2
  else:
    finalSummary = await al.summarizeBatch(validMessages, summary)

  if finalSummary != "":
    al.sessions.setSummary(sessionKey, finalSummary)
    al.sessions.truncateHistory(sessionKey, 4)
    let s = al.sessions.getOrCreate(sessionKey)
    al.sessions.save(s)

proc maybeSummarize(al: AgentLoop, sessionKey: string) {.async.} =
  let history = al.sessions.getHistory(sessionKey)
  let tokens = estimateTokens(history)
  let threshold = (al.contextWindow * 75) div 100

  if history.len > 20 or tokens > threshold:
    if not al.summarizing.hasKey(sessionKey):
      al.summarizing[sessionKey] = true
      try:
        await al.summarizeSession(sessionKey)
      finally:
        al.summarizing.del(sessionKey)

proc runLLMIteration(al: AgentLoop, messagesIn: seq[Message], sessionKey: string): Future[string] {.async.} =
  var messages = messagesIn
  var iteration = 0
  var finalContent = ""

  let toolDefs = al.tools.getDefinitions()
  var providerTools: seq[ToolDefinition] = @[]
  for td in toolDefs:
    let fn = td["function"]
    providerTools.add(ToolDefinition(
      `type`: "function",
      function: ToolFunctionDefinition(
        name: fn["name"].getStr(),
        description: fn["description"].getStr(),
        parameters: fn["parameters"]
      )
    ))

  while iteration < al.maxIterations:
    iteration += 1
    logger.debug("agent", "LLM iteration", {"count": $iteration, "max": $al.maxIterations})

    let response = await al.provider.chat(messages, providerTools, al.model, %*{"temperature": 0.7})

    if response.tool_calls.len == 0:
      finalContent = response.content
      break

    # Handle tool calls
    var assistantMsg = Message(role: "assistant", content: response.content)
    var msgToolCalls: seq[MessageToolCall] = @[]
    for tc in response.tool_calls:
      msgToolCalls.add(MessageToolCall(
        id: tc.id,
        `type`: "function",
        function: FunctionCall(name: tc.name, arguments: $tc.arguments)
      ))
    assistantMsg.tool_calls = some(msgToolCalls)
    messages.add(assistantMsg)
    al.sessions.addFullMessage(sessionKey, assistantMsg)

    for tc in response.tool_calls:
      logger.info("agent", "Executing tool", {"name": tc.name})
      let tool = al.tools.get(tc.name)
      var result: string
      if tool == nil:
        result = "Error: Tool not found: " & tc.name
      else:
        try:
          result = await tool.execute(newJObject(), tc.arguments)
        except Exception as e:
          result = "Error executing tool: " & e.msg

      let toolMsg = Message(
        role: "tool",
        content: result,
        tool_call_id: tc.id
      )
      messages.add(toolMsg)
      al.sessions.addFullMessage(sessionKey, toolMsg)

  return finalContent

proc processSystemMessage(al: AgentLoop, msg: InboundMessage): Future[string] {.async.} =
  # Porting processSystemMessage logic
  var originChannel = "cli"
  var originChatID = msg.chatID

  if ":" in msg.chatID:
    let parts = msg.chatID.split(":", 1)
    originChannel = parts[0]
    originChatID = parts[1]

  let sessionKey = originChannel & ":" & originChatID
  let history = al.sessions.getHistory(sessionKey)
  let summary = al.sessions.getSummary(sessionKey)

  let userMsg = "[System: " & msg.senderID & "] " & msg.content
  var messages = al.contextBuilder.buildMessages(history, summary, userMsg, originChannel, originChatID)
  al.sessions.addMessage(sessionKey, "user", userMsg)

  # We use runLLMIteration but send response back to origin
  let response = await al.runLLMIteration(messages, sessionKey)

  if response != "":
    await al.bus.publishOutbound(OutboundMessage(
      channel: originChannel,
      chatID: originChatID,
      content: response
    ))
    al.sessions.addMessage(sessionKey, "assistant", response)
    al.sessions.save(al.sessions.getOrCreate(sessionKey))

  return response


proc updateToolContexts(al: AgentLoop, channel, chatID: string) =
  let msgTool = al.tools.get("message")
  if msgTool != nil and msgTool of MessageTool:
    (MessageTool(msgTool)).setContext(channel, chatID)

  let spawnTool = al.tools.get("spawn")
  if spawnTool != nil and spawnTool of SpawnTool:
    (SpawnTool(spawnTool)).setContext(channel, chatID)

proc processMessage*(al: AgentLoop, msg: InboundMessage): Future[string] {.async.} =
  logger.info("agent", "Processing message", {"channel": msg.channel, "from": msg.senderID, "text": msg.content.truncate(50)})

  if msg.channel == "system":
    return await al.processSystemMessage(msg)

  # Update tool contexts before processing
  al.updateToolContexts(msg.channel, msg.chatID)

  let sessionKey = msg.sessionKey
  let history = al.sessions.getHistory(sessionKey)
  let summary = al.sessions.getSummary(sessionKey)

  var messages = al.contextBuilder.buildMessages(history, summary, msg.content, msg.channel, msg.chatID)
  al.sessions.addMessage(sessionKey, "user", msg.content)

  let response = await al.runLLMIteration(messages, sessionKey)

  let finalResponse = if response == "": "I've completed processing but have no response to give." else: response

  al.sessions.addMessage(sessionKey, "assistant", finalResponse)
  let s = al.sessions.getOrCreate(sessionKey)
  al.sessions.save(s)

  await al.maybeSummarize(sessionKey)

  return finalResponse

proc run*(al: AgentLoop) {.async.} =
  logger.info("agent", "Agent loop started")
  while true:
    let msg = await al.bus.consumeInbound()
    try:
      let response = await al.processMessage(msg)
      if response != "":
        await al.bus.publishOutbound(OutboundMessage(
          channel: msg.channel,
          chatID: msg.chatID,
          content: response
        ))
    except Exception as e:
      logger.error("agent", "Error in agent loop", {"error": e.msg})
      await al.bus.publishOutbound(OutboundMessage(
        channel: msg.channel,
        chatID: msg.chatID,
        content: "Error: " & e.msg
      ))
