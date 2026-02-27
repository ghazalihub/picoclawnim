import std/asyncdispatch
import std/asyncnet
import std/json
import std/strutils
import std/tables
import base
import ../bus
import ../logger

type
  MaixCamChannel* = ref object of BaseChannel
    host*: string
    port*: int
    clients*: seq[AsyncSocket]

proc newMaixCamChannel*(host: string, port: int, bus: MessageBus, allowFrom: seq[string] = @[]): MaixCamChannel =
  MaixCamChannel(
    name: "maixcam",
    bus: bus,
    allowFrom: allowFrom,
    host: host,
    port: port,
    clients: @[]
  )

proc processMaixMessage(c: MaixCamChannel, msg: JsonNode) {.async.} =
  let mType = msg.getOrDefault("type").getStr()
  case mType:
  of "person_detected":
    let data = msg["data"]
    let content = "📷 Person detected! Score: " & $data["score"].getFloat()
    await c.handleMessage("maixcam", "default", content)
  of "heartbeat":
    discard
  else:
    logger.warn("maixcam", "Unknown message type", {"type": mType})

proc handleClient(c: MaixCamChannel, client: AsyncSocket) {.async.} =
  while c.running:
    let line = await client.recvLine()
    if line == "": break
    try:
      let node = parseJson(line)
      await c.processMaixMessage(node)
    except:
      logger.error("maixcam", "Failed to parse message")
  client.close()

method send*(c: MaixCamChannel, msg: OutboundMessage) {.async.} =
  if not c.running: return
  let body = %*{
    "type": "command",
    "message": msg.content,
    "chat_id": msg.chatID
  }
  let data = $body & "\n"
  for client in c.clients:
    if not client.isClosed:
      await client.send(data)

method start*(c: MaixCamChannel) {.async.} =
  logger.info("maixcam", "Starting MaixCam channel (TCP Server)")
  c.running = true

  let server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(Port(c.port), c.host)
  server.listen()

  while c.running:
    let client = await server.accept()
    c.clients.add(client)
    asyncCheck c.handleClient(client)
