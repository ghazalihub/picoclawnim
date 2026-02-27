import std/asyncdispatch
import std/httpclient
import std/json
import std/strutils
import std/options
import types
import ../logger

type
  CodexProvider* = ref object
    apiKey*: string
    accountID*: string
    apiBase*: string

proc newCodexProvider*(apiKey, accountID, apiBase: string): CodexProvider =
  var base = apiBase
  if base == "": base = "https://chatgpt.com/backend-api/codex"
  CodexProvider(apiKey: apiKey, accountID: accountID, apiBase: base)

proc translateToolsForCodex(tools: seq[ToolDefinition]): JsonNode =
  result = newJArray()
  for t in tools:
    var tool = newJObject()
    tool["type"] = %"function"
    var fn = newJObject()
    fn["name"] = %t.function.name
    fn["description"] = %t.function.description
    fn["parameters"] = t.function.parameters
    tool["function"] = fn
    result.add(tool)

proc buildCodexParams(messages: seq[Message], tools: seq[ToolDefinition], model: string, options: JsonNode): JsonNode =
  result = newJObject()
  result["model"] = %model

  var inputItems = newJArray()
  var instructions = ""

  for msg in messages:
    case msg.role:
    of "system":
      instructions = msg.content
    of "user":
      if msg.tool_call_id != "":
        var item = newJObject()
        item["type"] = %"function_call_output"
        item["call_id"] = %msg.tool_call_id
        item["output"] = %msg.content
        inputItems.add(item)
      else:
        var item = newJObject()
        item["type"] = %"message"
        item["role"] = %"user"
        item["content"] = %msg.content
        inputItems.add(item)
    of "assistant":
      if msg.content != "" or msg.tool_calls.isSome:
        if msg.content != "":
          var item = newJObject()
          item["type"] = %"message"
          item["role"] = %"assistant"
          item["content"] = %msg.content
          inputItems.add(item)

        if msg.tool_calls.isSome:
          for tc in msg.tool_calls.get():
            var item = newJObject()
            item["type"] = %"function_call"
            item["call_id"] = %tc.id
            item["name"] = %tc.function.name
            item["arguments"] = %tc.function.arguments
            inputItems.add(item)
    of "tool":
      var item = newJObject()
      item["type"] = %"function_call_output"
      item["call_id"] = %msg.tool_call_id
      item["output"] = %msg.content
      inputItems.add(item)

  result["input"] = inputItems
  if instructions != "":
    result["instructions"] = %instructions

  if options.hasKey("max_tokens"):
    result["max_output_tokens"] = options["max_tokens"]
  if options.hasKey("temperature"):
    result["temperature"] = options["temperature"]

  if tools.len > 0:
    result["tools"] = translateToolsForCodex(tools)

  result["store"] = %false

proc parseCodexResponse(body: string): LLMResponse =
  let node = parseJson(body)
  var res: LLMResponse

  if node.hasKey("output"):
    for item in node["output"]:
      let iType = item["type"].getStr()
      if iType == "message":
        if item.hasKey("content"):
          for c in item["content"]:
            if c["type"].getStr() == "output_text":
              res.content &= c["text"].getStr()
      elif iType == "function_call":
        var tc: ToolCall
        tc.id = item["call_id"].getStr()
        tc.`type` = "function"
        tc.name = item["name"].getStr()
        let argsStr = item["arguments"].getStr()
        try:
          tc.arguments = parseJson(argsStr)
        except:
          tc.arguments = %*{"raw": argsStr}
        res.tool_calls.add(tc)

  res.finish_reason = "stop"
  if res.tool_calls.len > 0:
    res.finish_reason = "tool_calls"

  if node.hasKey("status") and node["status"].getStr() == "incomplete":
    res.finish_reason = "length"

  if node.hasKey("usage"):
    var usage: UsageInfo
    usage.prompt_tokens = node["usage"]["input_tokens"].getInt()
    usage.completion_tokens = node["usage"]["output_tokens"].getInt()
    usage.total_tokens = node["usage"]["total_tokens"].getInt()
    res.usage = some(usage)

  return res

proc chat*(p: CodexProvider, messages: seq[Message], tools: seq[ToolDefinition], model: string, options: JsonNode): Future[LLMResponse] {.async.} =
  let client = newAsyncHttpClient()
  var headers = newHttpHeaders({
    "Content-Type": "application/json",
    "Authorization": "Bearer " & p.apiKey
  })
  if p.accountID != "":
    headers.add("Chatgpt-Account-Id", p.accountID)
  client.headers = headers

  let requestBody = buildCodexParams(messages, tools, model, options)
  let url = p.apiBase & "/responses"

  logger.debug("codex", "Codex Request", {"url": url, "model": model})

  try:
    let response = await client.post(url, $requestBody)
    let body = await response.body

    if response.code != Http200:
      logger.error("codex", "Codex API Error", {"status": $response.code, "body": body})
      raise newException(IOError, "Codex API Error: " & body)

    return parseCodexResponse(body)
  finally:
    client.close()
