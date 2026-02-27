import std/asyncdispatch
import std/httpclient
import std/json
import std/strutils
import std/tables
import base
import ../bus
import ../logger

type
  DingTalkChannel* = ref object of BaseChannel
    clientID*: string
    clientSecret*: string
    sessionWebhooks*: Table[string, string]

proc newDingTalkChannel*(clientID, clientSecret: string, bus: MessageBus, allowFrom: seq[string] = @[]): DingTalkChannel =
  DingTalkChannel(
    name: "dingtalk",
    bus: bus,
    allowFrom: allowFrom,
    clientID: clientID,
    clientSecret: clientSecret,
    sessionWebhooks: initTable[string, string]()
  )

method send*(c: DingTalkChannel, msg: OutboundMessage) {.async.} =
  if not c.running: return
  if not c.sessionWebhooks.hasKey(msg.chatID):
    logger.error("dingtalk", "No session webhook found for chat", {"chat_id": msg.chatID})
    return

  let webhook = c.sessionWebhooks[msg.chatID]
  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({"Content-Type": "application/json"})

  let body = %*{
    "msgtype": "markdown",
    "markdown": {
      "title": "PicoClaw",
      "text": msg.content
    }
  }

  try:
    let response = await client.post(webhook, $body)
    if response.code != Http200:
      let respBody = await response.body
      logger.error("dingtalk", "Failed to send message", {"status": $response.code, "body": respBody})
  finally:
    client.close()

method start*(c: DingTalkChannel) {.async.} =
  logger.info("dingtalk", "Starting DingTalk channel (Stream Mode)")
  c.running = true

  while c.running:
    await sleepAsync(1000)
