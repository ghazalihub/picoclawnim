import std/times
import std/terminal

type
  LogLevel* = enum
    DEBUG, INFO, WARN, ERROR

var currentLogLevel* = INFO

proc setLevel*(level: LogLevel) =
  currentLogLevel = level

proc log(level: LogLevel, component: string, message: string, data: openArray[(string, string)] = []) =
  if level < currentLogLevel:
    return

  let now = now().format("HH:mm:ss")
  let levelStr = case level:
    of DEBUG: "DEBUG"
    of INFO:  " INFO"
    of WARN:  " WARN"
    of ERROR: "ERROR"

  let color = case level:
    of DEBUG: fgBlue
    of INFO:  fgGreen
    of WARN:  fgYellow
    of ERROR: fgRed

  stdout.styledWrite(fgWhite, now, " ")
  stdout.styledWrite(color, levelStr, " ")
  stdout.styledWrite(fgCyan, "[", component, "] ", fgWhite, message)

  if data.len > 0:
    stdout.write(" {")
    for i, pair in data:
      if i > 0: stdout.write(", ")
      stdout.write(pair[0], ": ", pair[1])
    stdout.write("}")

  stdout.writeLine("")

proc debug*(component, message: string, data: openArray[(string, string)] = []) =
  log(DEBUG, component, message, data)

proc info*(component, message: string, data: openArray[(string, string)] = []) =
  log(INFO, component, message, data)

proc warn*(component, message: string, data: openArray[(string, string)] = []) =
  log(WARN, component, message, data)

proc error*(component, message: string, data: openArray[(string, string)] = []) =
  log(ERROR, component, message, data)

when isMainModule:
  setLevel(DEBUG)
  debug("test", "Debug message", {"key": "val"})
  info("test", "Info message")
  warn("test", "Warn message")
  error("test", "Error message")
  echo "Logger tests passed"
