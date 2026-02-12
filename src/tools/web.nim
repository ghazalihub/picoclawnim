import std/asyncdispatch
import std/httpclient
import std/json
import std/strutils
import std/uri
import base
import ../logger

type
  WebSearchTool* = ref object of Tool
    apiKey*: string
    maxResults*: int

  WebFetchTool* = ref object of Tool
    maxChars*: int

proc newWebSearchTool*(apiKey: string, maxResults: int = 5): WebSearchTool =
  let t = WebSearchTool(
    name: "web_search",
    description: "Search the web for current information. Returns titles, URLs, and snippets from search results.",
    apiKey: apiKey,
    maxResults: if maxResults <= 0 or maxResults > 10: 5 else: maxResults
  )
  t.parameters = %*{
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "Search query"
      },
      "count": {
        "type": "integer",
        "description": "Number of results (1-10)",
        "minimum": 1,
        "maximum": 10
      }
    },
    "required": ["query"]
  }
  return t

method execute*(t: WebSearchTool, ctx: JsonNode, args: JsonNode): Future[ToolResult] {.async.} =
  if t.apiKey == "":
    return "Error: BRAVE_API_KEY not configured"

  let query = args["query"].getStr()
  var count = t.maxResults
  if args.hasKey("count"):
    count = args["count"].getInt()
    if count <= 0 or count > 10: count = t.maxResults

  let url = "https://api.search.brave.com/res/v1/web/search?q=" & encodeUrl(query) & "&count=" & $count

  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({
    "Accept": "application/json",
    "X-Subscription-Token": t.apiKey
  })

  try:
    let response = await client.get(url)
    let body = await response.body

    if response.code != Http200:
      return "Error: Search API returned " & $response.code & ": " & body

    let node = parseJson(body)
    if not node.hasKey("web") or not node["web"].hasKey("results") or node["web"]["results"].len == 0:
      return "No results found for: " & query

    var res = "Results for: " & query & "\n"
    let results = node["web"]["results"]
    for i in 0..<min(results.len, count):
      let item = results[i]
      res &= $ (i + 1) & ". " & item["title"].getStr() & "\n"
      res &= "   " & item["url"].getStr() & "\n"
      if item.hasKey("description"):
        res &= "   " & item["description"].getStr() & "\n"

    return res
  except Exception as e:
    return "Error performing web search: " & e.msg
  finally:
    client.close()

proc newWebFetchTool*(maxChars: int = 50000): WebFetchTool =
  let t = WebFetchTool(
    name: "web_fetch",
    description: "Fetch a URL and extract readable content (HTML to text).",
    maxChars: if maxChars <= 0: 50000 else: maxChars
  )
  t.parameters = %*{
    "type": "object",
    "properties": {
      "url": {
        "type": "string",
        "description": "URL to fetch"
      },
      "maxChars": {
        "type": "integer",
        "description": "Maximum characters to extract"
      }
    },
    "required": ["url"]
  }
  return t

proc extractText(html: string): string =
  # Very simple text extraction without regex to avoid PCRE dependency
  var resText = ""
  var inTag = false
  var inScript = false
  var inStyle = false

  var i = 0
  while i < html.len:
    if not inTag:
      if html[i] == '<':
        inTag = true
        if i + 7 < html.len and html[i+1..i+7].toLowerAscii == "script": inScript = true
        elif i + 6 < html.len and html[i+1..i+6].toLowerAscii == "style": inStyle = true
      else:
        if not inScript and not inStyle:
          resText.add(html[i])
    else:
      if html[i] == '>':
        inTag = false
        if inScript and i > 8 and html[i-8..i].toLowerAscii == "/script>": inScript = false
        if inStyle and i > 7 and html[i-7..i].toLowerAscii == "/style>": inStyle = false
    i += 1

  var lines: seq[string] = @[]
  for line in resText.split('\n'):
    let s = line.strip()
    if s != "": lines.add(s)

  return lines.join("\n")

method execute*(t: WebFetchTool, ctx: JsonNode, args: JsonNode): Future[ToolResult] {.async.} =
  let urlStr = args["url"].getStr()
  var maxChars = t.maxChars
  if args.hasKey("maxChars"):
    maxChars = args["maxChars"].getInt()

  let uri = parseUri(urlStr)
  if uri.scheme != "http" and uri.scheme != "https":
    return "Error: Only http/https URLs are allowed"

  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({"User-Agent": "Mozilla/5.0 (compatible; picoclaw/1.0)"})

  try:
    let response = await client.get(urlStr)
    let body = await response.body

    let contentType = response.headers.getOrDefault("Content-Type").toLowerAscii()
    var text = ""
    var extractor = "raw"

    if "application/json" in contentType:
      try:
        text = parseJson(body).pretty()
        extractor = "json"
      except:
        text = body
    elif "text/html" in contentType or body.toLowerAscii().startsWith("<!doctype") or "<html" in body.toLowerAscii():
      text = extractText(body)
      extractor = "text"
    else:
      text = body

    let truncated = text.len > maxChars
    if truncated:
      text = text[0..<maxChars]

    let res = %*{
      "url": urlStr,
      "status": response.code.int,
      "extractor": extractor,
      "truncated": truncated,
      "length": text.len,
      "text": text
    }
    return res.pretty()
  except Exception as e:
    return "Error fetching URL: " & e.msg
  finally:
    client.close()
