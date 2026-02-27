import std/asyncdispatch
import std/httpclient
import std/json
import std/jsonutils
import std/strutils
import std/options
import types
import ../logger

type
  HTTPProvider* = ref object
    apiKey*: string
    apiBase*: string

proc newHTTPProvider*(apiKey, apiBase: string): HTTPProvider =
  HTTPProvider(apiKey: apiKey, apiBase: apiBase)

proc parseResponse(body: string): LLMResponse =
  let node = parseJson(body)
  var res: LLMResponse

  if node.hasKey("choices") and node["choices"].len > 0:
    let choice = node["choices"][0]
    let msgNode = choice["message"]

    res.content = msgNode["content"].getStr()
    res.finish_reason = choice["finish_reason"].getStr()

    if msgNode.hasKey("tool_calls"):
      for tcNode in msgNode["tool_calls"]:
        var tc: ToolCall
        tc.id = tcNode["id"].getStr()
        tc.`type` = tcNode["type"].getStr()
        if tcNode.hasKey("function"):
          let fn = tcNode["function"]
          tc.name = fn["name"].getStr()
          let argsStr = fn["arguments"].getStr()
          try:
            tc.arguments = parseJson(argsStr)
          except:
            tc.arguments = %*{"raw": argsStr}
        res.tool_calls.add(tc)

    if node.hasKey("usage"):
      res.usage = some(node["usage"].jsonTo(UsageInfo))

  return res

proc chat*(p: HTTPProvider, messages: seq[Message], tools: seq[ToolDefinition], model: string, options: JsonNode): Future[LLMResponse] {.async.} =
  if p.apiBase == "":
    raise newException(ValueError, "API base not configured")

  var requestBody = newJObject()
  requestBody["model"] = %model
  requestBody["messages"] = messages.toJson()

  if tools.len > 0:
    requestBody["tools"] = tools.toJson()
    requestBody["tool_choice"] = %"auto"

  if options.hasKey("max_tokens"):
    let lowerModel = model.toLowerAscii()
    if "glm" in lowerModel or "o1" in lowerModel:
      requestBody["max_completion_tokens"] = options["max_tokens"]
    else:
      requestBody["max_tokens"] = options["max_tokens"]

  if options.hasKey("temperature"):
    requestBody["temperature"] = options["temperature"]

  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({
    "Content-Type": "application/json",
    "Authorization": "Bearer " & p.apiKey
  })

  let url = p.apiBase & "/chat/completions"
  logger.debug("provider", "LLM Request", {"url": url, "model": model})

  try:
    let response = await client.post(url, $requestBody)
    let body = await response.body

    if response.code != Http200:
      logger.error("provider", "LLM API Error", {"status": $response.code, "body": body})
      raise newException(IOError, "LLM API Error: " & body)

    return parseResponse(body)
  finally:
    client.close()
