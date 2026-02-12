import std/os
import std/asyncdispatch
import std/json
import std/strutils
import std/times
import std/tables
import std/options
import ../bus
import ../config
import ../logger
import ../providers/types
import ../providers/factory
import ../tools/base
import session
import memory
import context

type
  AgentLoop* = ref object
    bus: MessageBus
    provider: Provider
    workspace: string
    model: string
    maxIterations: int
    sessions: SessionManager
    tools: ToolRegistry
    memory: MemoryStore
    contextBuilder: ContextBuilder

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
    maxIterations: cfg.agents.defaults.max_tool_iterations,
    sessions: sm,
    tools: tr,
    memory: ms,
    contextBuilder: cb
  )

proc registerTool*(al: AgentLoop, t: Tool) =
  al.tools.register(t)

proc runLLMIteration(al: AgentLoop, messages: var seq[Message], sessionKey: string): Future[string] {.async.} =
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

proc processMessage*(al: AgentLoop, msg: InboundMessage): Future[string] {.async.} =
  let sessionKey = msg.sessionKey
  let history = al.sessions.getHistory(sessionKey)
  let summary = al.sessions.getSummary(sessionKey)

  var messages = al.contextBuilder.buildMessages(history, summary, msg.content, msg.channel, msg.chatID)
  al.sessions.addMessage(sessionKey, "user", msg.content)

  let response = await al.runLLMIteration(messages, sessionKey)

  al.sessions.addMessage(sessionKey, "assistant", response)
  let s = al.sessions.getOrCreate(sessionKey)
  al.sessions.save(s)

  return response

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
