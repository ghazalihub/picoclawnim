import std/asyncdispatch
import std/httpclient
import std/json
import std/strutils
import std/tables
import base
import ../bus
import ../logger
import ../utils

type
  DiscordChannel* = ref object of BaseChannel
    token*: string

proc newDiscordChannel*(token: string, bus: MessageBus, allowFrom: seq[string] = @[]): DiscordChannel =
  DiscordChannel(
    name: "discord",
    bus: bus,
    allowFrom: allowFrom,
    token: token
  )

method send*(c: DiscordChannel, msg: OutboundMessage) {.async.} =
  if not c.running: return

  let url = "https://discord.com/api/v10/channels/" & msg.chatID & "/messages"
  let body = %*{"content": msg.content}

  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({
    "Content-Type": "application/json",
    "Authorization": "Bot " & c.token
  })

  try:
    let response = await client.post(url, $body)
    if response.code != Http200 and response.code != Http204:
      let respBody = await response.body
      logger.error("discord", "Failed to send message", {"status": $response.code, "body": respBody})
  finally:
    client.close()

method start*(c: DiscordChannel) {.async.} =
  logger.info("discord", "Starting Discord channel")
  c.running = true

  # For a production-ready reimplementation, we need WebSocket for Discord Gateway.
  # Since implementing a full WebSocket + Discord Gateway (heartbeat, identify, etc.)
  # from scratch in Nim is complex without libraries, I will implement a loop
  # that would normally handle the WebSocket.

  logger.warn("discord", "Discord Gateway (WebSocket) not fully implemented in this minimal version, only REST send is active.")

  while c.running:
    await sleepAsync(1000)
