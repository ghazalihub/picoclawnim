import std/asyncdispatch
import std/httpclient
import std/json
import std/jsonutils
import std/strutils
import std/tables
import base
import ../bus
import ../logger
import ../utils

type
  TelegramChannel* = ref object of BaseChannel
    token*: string
    lastUpdateID*: int

proc newTelegramChannel*(token: string, bus: MessageBus, allowFrom: seq[string] = @[]): TelegramChannel =
  let c = TelegramChannel(
    name: "telegram",
    bus: bus,
    allowFrom: allowFrom,
    token: token,
    lastUpdateID: 0
  )
  return c

method send*(c: TelegramChannel, msg: OutboundMessage) {.async.} =
  if not c.running: return

  let url = "https://api.telegram.org/bot" & c.token & "/sendMessage"
  let body = %*{
    "chat_id": msg.chatID,
    "text": msg.content,
    "parse_mode": "HTML"
  }

  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({"Content-Type": "application/json"})
  try:
    let response = await client.post(url, $body)
    if response.code != Http200:
      let respBody = await response.body
      logger.error("telegram", "Failed to send message", {"status": $response.code, "body": respBody})
  finally:
    client.close()

proc processUpdate(c: TelegramChannel, update: JsonNode) {.async.} =
  if update.hasKey("message"):
    let message = update["message"]
    if message.hasKey("text") and message.hasKey("from") and message.hasKey("chat"):
      let text = message["text"].getStr()
      let user = message["from"]
      let chat = message["chat"]

      let senderID = $user["id"].getInt()
      let chatID = $chat["id"].getInt()

      logger.info("telegram", "Received message", {"from": senderID, "text": text.truncate(20)})

      await c.handleMessage(senderID, chatID, text)

method start*(c: TelegramChannel) {.async.} =
  logger.info("telegram", "Starting Telegram channel")
  c.running = true

  let client = newAsyncHttpClient()
  client.timeout = 60000 # 60s for long polling

  while c.running:
    let url = "https://api.telegram.org/bot" & c.token & "/getUpdates?timeout=30&offset=" & $(c.lastUpdateID + 1)
    try:
      let response = await client.get(url)
      if response.code == Http200:
        let body = await response.body
        let node = parseJson(body)
        if node.hasKey("result"):
          for update in node["result"]:
            let updateID = update["update_id"].getInt()
            if updateID > c.lastUpdateID:
              c.lastUpdateID = updateID
            await c.processUpdate(update)
      else:
        await sleepAsync(5000)
    except Exception as e:
      logger.error("telegram", "Error in long polling", {"error": e.msg})
      await sleepAsync(5000)

  client.close()
