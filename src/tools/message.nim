import std/asyncdispatch
import std/json
import base
import ../bus

type
  MessageTool* = ref object of Tool
    bus*: MessageBus
    channel*: string
    chatID*: string

proc newMessageTool*(bus: MessageBus): MessageTool =
  let t = MessageTool(
    name: "message",
    description: "Send a message to a user or channel.",
    bus: bus
  )
  t.parameters = %*{
    "type": "object",
    "properties": {
      "content": {
        "type": "string",
        "description": "Message content"
      },
      "channel": {
        "type": "string",
        "description": "Optional target channel"
      },
      "chat_id": {
        "type": "string",
        "description": "Optional target chat ID"
      }
    },
    "required": ["content"]
  }
  return t

proc setContext*(t: MessageTool, channel, chatID: string) =
  t.channel = channel
  t.chatID = chatID

method execute*(t: MessageTool, ctx: JsonNode, args: JsonNode): Future[ToolResult] {.async.} =
  let content = args["content"].getStr()
  var channel = t.channel
  var chatID = t.chatID

  if args.hasKey("channel") and args["channel"].getStr() != "":
    channel = args["channel"].getStr()
  if args.hasKey("chat_id") and args["chat_id"].getStr() != "":
    chatID = args["chat_id"].getStr()

  if channel == "" or chatID == "":
    return "Error: Channel and chatID must be provided or set in context"

  await t.bus.publishOutbound(OutboundMessage(
    channel: channel,
    chatID: chatID,
    content: content
  ))

  return "Message sent successfully"
