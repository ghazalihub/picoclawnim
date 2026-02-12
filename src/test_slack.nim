import channels/slack
import bus
import std/asyncdispatch

proc testSlack() {.async.} =
  let mb = newMessageBus()
  let c = newSlackChannel("fake-bot-token", "fake-app-token", mb)
  echo "Slack channel compilation successful."

waitFor testSlack()
