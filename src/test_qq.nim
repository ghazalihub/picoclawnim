import channels/qq
import bus
import std/asyncdispatch

proc testQQ() {.async.} =
  let mb = newMessageBus()
  let c = newQQChannel("fake-id", "fake-secret", mb)
  echo "QQ channel compilation successful."

waitFor testQQ()
