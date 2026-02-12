import channels/telegram
import bus
import std/asyncdispatch

proc testTelegram() {.async.} =
  let mb = newMessageBus()
  let c = newTelegramChannel("fake-token", mb)
  echo "Telegram channel compilation successful."

waitFor testTelegram()
