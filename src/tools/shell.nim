import std/asyncdispatch
import std/json
import std/os
import std/strutils
import std/times
import std/streams
import std/osproc
import base
import ../logger

type
  ExecTool* = ref object of Tool
    workingDir*: string
    timeout*: int # seconds
    denyPatterns*: seq[string]
    restrictToWorkspace*: bool

proc newExecTool*(workingDir: string): ExecTool =
  let t = ExecTool(
    name: "exec",
    description: "Execute a shell command and return its output. Use with caution.",
    workingDir: workingDir,
    timeout: 60,
    restrictToWorkspace: false
  )

  t.parameters = %*{
    "type": "object",
    "properties": {
      "command": {
        "type": "string",
        "description": "The shell command to execute"
      },
      "working_dir": {
        "type": "string",
        "description": "Optional working directory for the command"
      }
    },
    "required": ["command"]
  }

  t.denyPatterns = @[
    "rm -rf", "rm -f", "rm -r",
    "del /f", "del /q",
    "format ", "mkfs ", "diskpart",
    "dd if=",
    "> /dev/sd",
    "shutdown", "reboot", "poweroff"
  ]

  return t

proc guardCommand(t: ExecTool, command, cwd: string): string =
  let cmd = command.toLowerAscii().strip()

  for pattern in t.denyPatterns:
    if pattern in cmd:
      return "Command blocked by safety guard (dangerous pattern detected)"

  if t.restrictToWorkspace:
    if ".." in cmd:
      return "Command blocked by safety guard (path traversal detected)"
    # More complex path checking could be added here

  return ""

method execute*(t: ExecTool, ctx: JsonNode, args: JsonNode): Future[ToolResult] {.async.} =
  let command = args["command"].getStr()
  var cwd = t.workingDir
  if args.hasKey("working_dir") and args["working_dir"].getStr() != "":
    cwd = args["working_dir"].getStr()

  if cwd == "":
    cwd = getCurrentDir()

  let guardError = t.guardCommand(command, cwd)
  if guardError != "":
    return "Error: " & guardError

  logger.info("shell", "Executing command", {"command": command, "cwd": cwd})

  # Nim's osproc doesn't have an easy async version of execProcess with timeout
  # We'll use a thread or just run it synchronously for now if needed,
  # but asyncdispatch doesn't like blocking.
  # For a "performance-optimized" version, we should use non-blocking I/O.

  try:
    # Use startProcess and check for timeout
    let exe = findExe("sh")
    if exe == "": return "Error: sh not found"
    let p = startProcess(exe, cwd, ["-c", command], options = {poStdErrToStdOut})
    let startTime = epochTime()
    var output = ""

    # This is a simple wait loop with a sleep, not truly async but works in this context
    # Better would be using selectors/asyncdispatch on the output pipes
    while p.running:
      if epochTime() - startTime > t.timeout.float:
        p.terminate()
        return "Error: Command timed out after " & $t.timeout & " seconds"
      await sleepAsync(100)

    let stream = p.outputStream
    output = stream.readAll()
    p.close()

    if output == "": output = "(no output)"
    if output.len > 10000:
      output = output[0..<10000] & "\n... (truncated)"

    return output
  except Exception as e:
    return "Error executing command: " & e.msg
