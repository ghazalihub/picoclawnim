import std/asyncdispatch
import std/httpclient
import std/json
import std/strutils
import std/options
import types
import ../logger

type
  ClaudeProvider* = ref object
    apiKey*: string
    apiBase*: string

proc newClaudeProvider*(apiKey, apiBase: string): ClaudeProvider =
  var base = apiBase
  if base == "": base = "https://api.anthropic.com"
  ClaudeProvider(apiKey: apiKey, apiBase: base)

proc translateToolsForClaude(tools: seq[ToolDefinition]): JsonNode =
  result = newJArray()
  for t in tools:
    var tool = newJObject()
    tool["name"] = %t.function.name
    tool["description"] = %t.function.description

    var inputSchema = newJObject()
    inputSchema["type"] = %"object"
    if t.function.parameters.hasKey("properties"):
      inputSchema["properties"] = t.function.parameters["properties"]
    if t.function.parameters.hasKey("required"):
      inputSchema["required"] = t.function.parameters["required"]

    tool["input_schema"] = inputSchema
    result.add(tool)

proc buildClaudeParams(messages: seq[Message], tools: seq[ToolDefinition], model: string, options: JsonNode): JsonNode =
  result = newJObject()
  result["model"] = %model

  var systemPrompt = ""
  var claudeMessages = newJArray()

  for msg in messages:
    case msg.role:
    of "system":
      if systemPrompt != "": systemPrompt &= "\n"
      systemPrompt &= msg.content
    of "user":
      var contentBlocks = newJArray()
      if msg.tool_call_id != "":
        # Tool result
        var cBlock = newJObject()
        cBlock["type"] = %"tool_result"
        cBlock["tool_use_id"] = %msg.tool_call_id
        cBlock["content"] = %msg.content
        contentBlocks.add(cBlock)
      else:
        var cBlock = newJObject()
        cBlock["type"] = %"text"
        cBlock["text"] = %msg.content
        contentBlocks.add(cBlock)

      claudeMessages.add(%*{"role": "user", "content": contentBlocks})

    of "assistant":
      var contentBlocks = newJArray()
      if msg.content != "":
        var cBlock = newJObject()
        cBlock["type"] = %"text"
        cBlock["text"] = %msg.content
        contentBlocks.add(cBlock)

      if msg.tool_calls.isSome:
        for tc in msg.tool_calls.get():
          var cBlock = newJObject()
          cBlock["type"] = %"tool_use"
          cBlock["id"] = %tc.id
          cBlock["name"] = %tc.function.name
          try:
            cBlock["input"] = parseJson(tc.function.arguments)
          except:
            cBlock["input"] = %*{"raw": tc.function.arguments}
          contentBlocks.add(cBlock)

      claudeMessages.add(%*{"role": "assistant", "content": contentBlocks})

    of "tool":
      # Tool results are technically 'user' role in Anthropic
      var contentBlocks = newJArray()
      var cBlock = newJObject()
      cBlock["type"] = %"tool_result"
      cBlock["tool_use_id"] = %msg.tool_call_id
      cBlock["content"] = %msg.content
      contentBlocks.add(cBlock)
      claudeMessages.add(%*{"role": "user", "content": contentBlocks})

  if systemPrompt != "":
    result["system"] = %systemPrompt

  result["messages"] = claudeMessages

  var maxTokens = 4096
  if options.hasKey("max_tokens"):
    maxTokens = options["max_tokens"].getInt()
  result["max_tokens"] = %maxTokens

  if options.hasKey("temperature"):
    result["temperature"] = options["temperature"]

  if tools.len > 0:
    result["tools"] = translateToolsForClaude(tools)

proc parseClaudeResponse(body: string): LLMResponse =
  let node = parseJson(body)
  var res: LLMResponse

  if node.hasKey("content"):
    for cBlock in node["content"]:
      let bType = cBlock["type"].getStr()
      if bType == "text":
        res.content &= cBlock["text"].getStr()
      elif bType == "tool_use":
        var tc: ToolCall
        tc.id = cBlock["id"].getStr()
        tc.`type` = "function"
        tc.name = cBlock["name"].getStr()
        tc.arguments = cBlock["input"]
        res.tool_calls.add(tc)

  res.finish_reason = node["stop_reason"].getStr()
  if res.finish_reason == "tool_use":
    res.finish_reason = "tool_calls"
  elif res.finish_reason == "end_turn":
    res.finish_reason = "stop"

  if node.hasKey("usage"):
    var usage: UsageInfo
    usage.prompt_tokens = node["usage"]["input_tokens"].getInt()
    usage.completion_tokens = node["usage"]["output_tokens"].getInt()
    usage.total_tokens = usage.prompt_tokens + usage.completion_tokens
    res.usage = some(usage)

  return res

proc chat*(p: ClaudeProvider, messages: seq[Message], tools: seq[ToolDefinition], model: string, options: JsonNode): Future[LLMResponse] {.async.} =
  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({
    "Content-Type": "application/json",
    "x-api-key": p.apiKey,
    "anthropic-version": "2023-06-01"
  })

  let requestBody = buildClaudeParams(messages, tools, model, options)
  let url = p.apiBase & "/v1/messages"

  logger.debug("claude", "Claude Request", {"url": url, "model": model})

  try:
    let response = await client.post(url, $requestBody)
    let body = await response.body

    if response.code != Http200:
      logger.error("claude", "Claude API Error", {"status": $response.code, "body": body})
      raise newException(IOError, "Claude API Error: " & body)

    return parseClaudeResponse(body)
  finally:
    client.close()
