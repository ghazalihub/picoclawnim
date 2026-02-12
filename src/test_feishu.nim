import channels/feishu
import bus
import std/asyncdispatch

proc testFeishu() {.async.} =
  let mb = newMessageBus()
  let c = newFeishuChannel("fake-id", "fake-secret", mb)
  echo "Feishu channel compilation successful."

waitFor testFeishu()
