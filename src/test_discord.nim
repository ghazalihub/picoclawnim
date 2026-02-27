import channels/discord
import bus
import std/asyncdispatch

proc testDiscord() {.async.} =
  let mb = newMessageBus()
  let c = newDiscordChannel("fake-token", mb)
  echo "Discord channel compilation successful."

waitFor testDiscord()
