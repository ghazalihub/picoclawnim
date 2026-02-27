import std/asyncdispatch
import std/json
import std/tables

type
  Tool* = ref object of RootObj
    name*: string
    description*: string
    parameters*: JsonNode

  ToolResult* = string

method execute*(t: Tool, ctx: JsonNode, args: JsonNode): Future[ToolResult] {.async, base.} =
  raise newException(CatchableError, "execute method not implemented")

type
  ToolRegistry* = ref object
    tools*: Table[string, Tool]

proc newToolRegistry*(): ToolRegistry =
  ToolRegistry(tools: initTable[string, Tool]())

proc register*(tr: ToolRegistry, t: Tool) =
  tr.tools[t.name] = t

proc get*(tr: ToolRegistry, name: string): Tool =
  return tr.tools.getOrDefault(name)

proc getDefinitions*(tr: ToolRegistry): seq[JsonNode] =
  result = @[]
  for t in tr.tools.values:
    var def = newJObject()
    def["type"] = %"function"
    var fn = newJObject()
    fn["name"] = %t.name
    fn["description"] = %t.description
    fn["parameters"] = t.parameters
    def["function"] = fn
    result.add(def)
