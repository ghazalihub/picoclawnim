import channels/whatsapp
import bus
import std/asyncdispatch

proc testWhatsApp() {.async.} =
  let mb = newMessageBus()
  let c = newWhatsAppChannel("ws://localhost:3001", mb)
  echo "WhatsApp channel compilation successful."

waitFor testWhatsApp()
