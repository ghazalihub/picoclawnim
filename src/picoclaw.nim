import std/os
import std/strutils
import std/asyncdispatch
import std/parseopt
import std/json
import logger
import config
import bus
import agent/loop
import providers/factory
import tools/base
import tools/filesystem
import tools/shell
import tools/web
import tools/message
import tools/spawn
import skills
import migrate
import auth
import cron
import heartbeat

const version = "0.1.0"
const logo = "🦞"

proc printHelp() =
  echo logo & " picoclaw - Personal AI Assistant v" & version
  echo ""
  echo "Usage: picoclaw <command>"
  echo ""
  echo "Commands:"
  echo "  onboard     Initialize picoclaw configuration and workspace"
  echo "  agent       Interact with the agent directly"
  echo "  auth        Manage authentication (login, logout, status)"
  echo "  gateway     Start picoclaw gateway"
  echo "  status      Show picoclaw status"
  echo "  cron        Manage scheduled tasks"
  echo "  migrate     Migrate from OpenClaw to PicoClaw"
  echo "  skills      Manage skills (install, list, remove)"
  echo "  version     Show version information"

proc onboardCmd() =
  let cfgPath = getHomeDir() / ".picoclaw" / "config.json"
  if fileExists(cfgPath):
    stdout.write("Config already exists. Overwrite? (y/n): ")
    let res = stdin.readLine()
    if res.toLowerAscii != "y":
      echo "Aborted."
      return

  let cfg = defaultConfig()
  if saveConfig(cfgPath, cfg):
    echo logo & " picoclaw is ready!"
    echo "\nNext steps:"
    echo "  1. Add your API key to " & cfgPath
    echo "  2. Chat: picoclaw agent -m \"Hello!\""

proc agentCmd() {.async.} =
  var message = ""
  var sessionKey = "cli:default"
  var debug = false

  var p = initOptParser()
  while true:
    p.next()
    case p.kind:
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key:
      of "m", "message": message = p.val
      of "s", "session": sessionKey = p.val
      of "d", "debug": debug = true
    of cmdArgument: discard

  if debug: logger.setLevel(DEBUG)

  let cfg = loadConfig(getHomeDir() / ".picoclaw" / "config.json")
  let provider = createProvider(cfg)
  let mb = newMessageBus()
  let al = newAgentLoop(cfg, mb, provider)

  # Register standard tools
  al.registerTool(newReadFileTool())
  al.registerTool(newWriteFileTool())
  al.registerTool(newListDirTool())
  al.registerTool(newEditFileTool(cfg.getWorkspacePath()))
  al.registerTool(newExecTool(cfg.getWorkspacePath()))
  al.registerTool(newWebSearchTool(cfg.tools.web.search.api_key, cfg.tools.web.search.max_results))
  al.registerTool(newWebFetchTool())
  al.registerTool(newMessageTool(mb))
  # Subagent manager and tools would go here

  if message != "":
    # Process single message
    echo logo & " Processing..."
    try:
      let resp = await al.processMessage(InboundMessage(
        channel: "cli",
        senderID: "user",
        chatID: "direct",
        content: message,
        sessionKey: sessionKey
      ))
      echo "\n" & logo & " " & resp
    except Exception as e:
      echo "Error: " & e.msg
  else:
    echo logo & " Interactive mode (Ctrl+C to exit)"
    while true:
      stdout.write(logo & " You: ")
      let input = stdin.readLine().strip()
      if input == "exit" or input == "quit": break
      if input == "": continue

      try:
        let resp = await al.processMessage(InboundMessage(
          channel: "cli",
          senderID: "user",
          chatID: "direct",
          content: input,
          sessionKey: sessionKey
        ))
        echo "\n" & logo & " " & resp & "\n"
      except Exception as e:
        echo "Error: " & e.msg

proc statusCmd() =
  let cfgPath = getHomeDir() / ".picoclaw" / "config.json"
  echo logo & " picoclaw Status"
  echo ""
  if fileExists(cfgPath):
    echo "Config: " & cfgPath & " ✓"
  else:
    echo "Config: " & cfgPath & " ✗"

proc main() {.async.} =
  let args = commandLineParams()
  if args.len == 0:
    printHelp()
    return

  case args[0]:
  of "onboard": onboardCmd()
  of "agent": await agentCmd()
  of "status": statusCmd()
  of "migrate":
    let openclaw = getHomeDir() / ".openclaw"
    let picoclaw = getHomeDir() / ".picoclaw"
    runMigration(openclaw, picoclaw)
  of "version", "-v", "--version": echo logo & " picoclaw v" & version
  of "help", "-h", "--help": printHelp()
  else:
    echo "Unknown command: " & args[0]
    printHelp()

waitFor main()
