import std/asyncdispatch
import std/json
import base
import ../agent/subagent

type
  SpawnTool* = ref object of Tool
    manager*: SubagentManager
    originChannel*: string
    originChatID*: string

proc newSpawnTool*(manager: SubagentManager): SpawnTool =
  let t = SpawnTool(
    name: "spawn",
    description: "Spawn a subagent to handle a task in the background. Use this for complex or time-consuming tasks.",
    manager: manager,
    originChannel: "cli",
    originChatID:  "direct"
  )
  t.parameters = %*{
    "type": "object",
    "properties": {
      "task": {
        "type": "string",
        "description": "The task for subagent to complete"
      },
      "label": {
        "type": "string",
        "description": "Optional short label for the task"
      }
    },
    "required": ["task"]
  }
  return t

proc setContext*(t: SpawnTool, channel, chatID: string) =
  t.originChannel = channel
  t.originChatID = chatID

method execute*(t: SpawnTool, ctx: JsonNode, args: JsonNode): Future[ToolResult] {.async.} =
  let task = args["task"].getStr()
  var label = ""
  if args.hasKey("label"): label = args["label"].getStr()

  if t.manager == nil:
    return "Error: Subagent manager not configured"

  return await t.manager.spawn(task, label, t.originChannel, t.originChatID)
