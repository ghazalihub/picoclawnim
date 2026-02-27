import std/asyncdispatch
import std/tables
import std/strutils
import ../bus
import ../logger

type
  BaseChannel* = ref object of RootObj
    name*: string
    bus*: MessageBus
    allowFrom*: seq[string]
    running*: bool

method start*(c: BaseChannel) {.async, base.} =
  raise newException(CatchableError, "start method not implemented")

method stop*(c: BaseChannel) {.async, base.} =
  c.running = false

method send*(c: BaseChannel, msg: OutboundMessage) {.async, base.} =
  raise newException(CatchableError, "send method not implemented")

proc isAllowed*(c: BaseChannel, senderID: string): bool =
  if c.allowFrom.len == 0: return true
  for allowed in c.allowFrom:
    if allowed == senderID or senderID.contains(allowed):
      return true
  return false

proc handleMessage*(c: BaseChannel, senderID, chatID, content: string, mediaPaths: seq[string] = @[], metadata: Table[string, string] = initTable[string, string]()) {.async.} =
  if not c.isAllowed(senderID):
    logger.warn(c.name, "Message rejected by allowlist", {"sender": senderID})
    return

  let msg = InboundMessage(
    channel: c.name,
    senderID: senderID,
    chatID: chatID,
    content: content,
    sessionKey: c.name & ":" & chatID,
    mediaPaths: mediaPaths,
    metadata: metadata
  )
  await c.bus.publishInbound(msg)
