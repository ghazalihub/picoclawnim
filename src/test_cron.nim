import cron
import std/asyncdispatch

proc testCron() {.async.} =
  let cs = newCronService("test_cron.json")
  echo "Cron service compilation successful."

waitFor testCron()
