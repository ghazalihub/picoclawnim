import channels/dingtalk
import bus
import std/asyncdispatch

proc testDingTalk() {.async.} =
  let mb = newMessageBus()
  let c = newDingTalkChannel("fake-id", "fake-secret", mb)
  echo "DingTalk channel compilation successful."

waitFor testDingTalk()
