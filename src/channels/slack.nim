import std/asyncdispatch
import std/httpclient
import std/json
import std/strutils
import std/tables
import base
import ../bus
import ../logger

type
  SlackChannel* = ref object of BaseChannel
    botToken*: string
    appToken*: string

proc newSlackChannel*(botToken, appToken: string, bus: MessageBus, allowFrom: seq[string] = @[]): SlackChannel =
  SlackChannel(
    name: "slack",
    bus: bus,
    allowFrom: allowFrom,
    botToken: botToken,
    appToken: appToken
  )

method send*(c: SlackChannel, msg: OutboundMessage) {.async.} =
  if not c.running: return

  let url = "https://slack.com/api/chat.postMessage"
  let body = %*{
    "channel": msg.chatID,
    "text": msg.content
  }

  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({
    "Content-Type": "application/json",
    "Authorization": "Bearer " & c.botToken
  })

  try:
    let response = await client.post(url, $body)
    if response.code != Http200:
      let respBody = await response.body
      logger.error("slack", "Failed to send message", {"status": $response.code, "body": respBody})
  finally:
    client.close()

method start*(c: SlackChannel) {.async.} =
  logger.info("slack", "Starting Slack channel")
  c.running = true

  while c.running:
    await sleepAsync(1000)
