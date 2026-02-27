import std/asyncdispatch
import std/os
import std/times
import std/strformat
import logger

type
  HeartbeatService* = ref object
    workspace*: string
    interval*: int # seconds
    enabled*: bool
    running*: bool
    onHeartbeat*: proc(prompt: string): Future[string] {.async.}

proc newHeartbeatService*(workspace: string, intervalS: int, enabled: bool): HeartbeatService =
  HeartbeatService(
    workspace: workspace,
    interval: intervalS,
    enabled: enabled,
    running: false
  )

proc buildPrompt(hs: HeartbeatService): string =
  let heartbeatFile = hs.workspace / "memory" / "HEARTBEAT.md"
  var notes = ""
  if fileExists(heartbeatFile):
    notes = readFile(heartbeatFile)

  let nowStr = now().format("yyyy-MM-dd HH:mm")
  return fmt"""# Heartbeat Check

Current time: {nowStr}

Check if there are any tasks I should be aware of or actions I should take.
Review the memory file for any important updates or changes.
Be proactive in identifying potential issues or improvements.

{notes}
"""

proc logHeartbeat(hs: HeartbeatService, message: string) =
  let logFile = hs.workspace / "memory" / "heartbeat.log"
  try:
    createDir(parentDir(logFile))
    let f = open(logFile, fmAppend)
    f.writeLine("[" & now().format("yyyy-MM-dd HH:mm:ss") & "] " & message)
    f.close()
  except: discard

proc start*(hs: HeartbeatService) {.async.} =
  if not hs.enabled: return
  logger.info("heartbeat", "Starting Heartbeat service")
  hs.running = true

  while hs.running:
    await sleepAsync(hs.interval * 1000)
    if not hs.running: break

    let prompt = hs.buildPrompt()
    if hs.onHeartbeat != nil:
      try:
        discard await hs.onHeartbeat(prompt)
      except Exception as e:
        hs.logHeartbeat("Heartbeat error: " & e.msg)
