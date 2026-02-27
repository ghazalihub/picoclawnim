import std/asyncdispatch
import std/httpclient
import std/json
import std/strutils
import std/tables
import base
import ../bus
import ../logger

type
  WhatsAppChannel* = ref object of BaseChannel
    bridgeURL*: string

proc newWhatsAppChannel*(bridgeURL: string, bus: MessageBus, allowFrom: seq[string] = @[]): WhatsAppChannel =
  WhatsAppChannel(
    name: "whatsapp",
    bus: bus,
    allowFrom: allowFrom,
    bridgeURL: bridgeURL
  )

method send*(c: WhatsAppChannel, msg: OutboundMessage) {.async.} =
  if not c.running: return

  logger.info("whatsapp", "Sending message via bridge", {"chat_id": msg.chatID})

  # Logic to send via bridge normally goes here
  # The bridge usually uses WebSockets as well in many implementations

method start*(c: WhatsAppChannel) {.async.} =
  logger.info("whatsapp", "Starting WhatsApp channel (via bridge)")
  c.running = true

  while c.running:
    await sleepAsync(1000)
