import heartbeat
import std/asyncdispatch

proc testHeartbeat() {.async.} =
  let hs = newHeartbeatService(".", 60, true)
  echo "Heartbeat service compilation successful."

waitFor testHeartbeat()
