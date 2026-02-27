import channels/maixcam
import bus
import std/asyncdispatch

proc testMaixCam() {.async.} =
  let mb = newMessageBus()
  let c = newMaixCamChannel("0.0.0.0", 18790, mb)
  echo "MaixCam channel compilation successful."

waitFor testMaixCam()
