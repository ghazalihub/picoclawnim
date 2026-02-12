import std/asyncdispatch
import std/httpclient
import std/json
import std/strutils
import std/tables
import std/times
import base
import ../bus
import ../logger

type
  FeishuChannel* = ref object of BaseChannel
    appID*: string
    appSecret*: string

proc newFeishuChannel*(appID, appSecret: string, bus: MessageBus, allowFrom: seq[string] = @[]): FeishuChannel =
  FeishuChannel(
    name: "feishu",
    bus: bus,
    allowFrom: allowFrom,
    appID: appID,
    appSecret: appSecret
  )

method send*(c: FeishuChannel, msg: OutboundMessage) {.async.} =
  if not c.running: return

  # Feishu requires an internal token. Replicating the logic from oapi-sdk-go
  logger.info("feishu", "Sending message to Feishu", {"chat_id": msg.chatID})

  let client = newAsyncHttpClient()
  # In a full implementation, we'd fetch the tenant_access_token first

  let body = %*{
    "receive_id": msg.chatID,
    "msg_type": "text",
    "content": $ (%*{"text": msg.content}),
    "uuid": "picoclaw-" & $ (epochTime().int)
  }

  # POST https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id
  # requires Authorization: Bearer <tenant_access_token>

  client.close()

method start*(c: FeishuChannel) {.async.} =
  logger.info("feishu", "Starting Feishu channel")
  c.running = true

  while c.running:
    await sleepAsync(1000)
