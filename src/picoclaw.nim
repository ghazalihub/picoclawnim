import std/os
import std/strutils
import std/asyncdispatch
import std/parseopt
import std/json
import std/times
import std/tables
import logger
import config
import bus
import agent/loop
import agent/subagent
import providers/factory
import tools/base
import tools/filesystem
import tools/shell
import tools/web
import tools/message
import tools/spawn
import tools/cron as cronTool
import skills
import migrate
import auth
import cron
import heartbeat
import channels/base
import channels/telegram
import channels/discord
import channels/qq
import channels/dingtalk
import channels/feishu
import channels/slack
import channels/whatsapp
import channels/maixcam

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

proc skillsCmd() {.async.} =
  let args = commandLineParams()
  if args.len < 2:
    echo "Usage: picoclaw skills <list|install|remove|search>"
    return

  let cfg = loadConfig(getHomeDir() / ".picoclaw" / "config.json")
  let workspace = cfg.getWorkspacePath()
  let loader = newSkillsLoader(workspace, getHomeDir() / ".picoclaw" / "skills", getAppDir() / "skills")
  let installer = newSkillInstaller(workspace)

  case args[1]:
  of "list":
    let skills = loader.listSkills()
    if skills.len == 0: echo "No skills installed."
    else:
      echo "\nInstalled Skills:"
      for s in skills: echo "  ✓ " & s.name & " (" & s.source & ")"
  of "install":
    if args.len < 3: echo "Usage: picoclaw skills install <repo>"; return
    await installer.installFromGitHub(args[2])
  of "search":
    let avail = await installer.listAvailableSkills()
    for s in avail: echo "  📦 " & s.name & ": " & s.description
  of "remove", "uninstall":
    if args.len < 3: echo "Usage: picoclaw skills remove <name>"; return
    let skillDir = workspace / "skills" / args[2]
    if dirExists(skillDir):
      removeDir(skillDir)
      echo "✓ Skill '" & args[2] & "' removed"
    else: echo "✗ Skill '" & args[2] & "' not found"
  of "show":
    if args.len < 3: echo "Usage: picoclaw skills show <name>"; return
    let (content, ok) = loader.loadSkill(args[2])
    if ok:
      echo "\n📦 Skill: " & args[2]
      echo "----------------------"
      echo content
    else: echo "✗ Skill '" & args[2] & "' not found"
  else: echo "Unknown skills command"

proc cronCmd() =
  let args = commandLineParams()
  if args.len < 2:
    echo "Usage: picoclaw cron <list|add|remove|enable|disable>"
    return

  let cfg = loadConfig(getHomeDir() / ".picoclaw" / "config.json")
  let cs = newCronService(cfg.getWorkspacePath() / "cron" / "jobs.json")

  case args[1]:
  of "list":
    if cs.store.jobs.len == 0: echo "No scheduled jobs."
    else:
      echo "\nScheduled Jobs:"
      echo "----------------"
      for j in cs.store.jobs:
        let stat = if j.enabled: "enabled" else: "disabled"
        echo "  " & j.name & " (" & j.id & ")"
        echo "    Status: " & stat
  of "remove":
    if args.len < 3: echo "Usage: picoclaw cron remove <job_id>"; return
    let id = args[2]
    var found = false
    for i in 0..<cs.store.jobs.len:
      if cs.store.jobs[i].id == id:
        cs.store.jobs.delete(i)
        cs.saveStore()
        echo "✓ Removed job " & id
        found = true; break
    if not found: echo "✗ Job " & id & " not found"
  of "enable", "disable":
    if args.len < 3: echo "Usage: picoclaw cron " & args[1] & " <job_id>"; return
    let id = args[2]
    let enabled = args[1] == "enable"
    var found = false
    for i in 0..<cs.store.jobs.len:
      if cs.store.jobs[i].id == id:
        cs.store.jobs[i].enabled = enabled
        cs.saveStore()
        echo "✓ Job '" & cs.store.jobs[i].name & "' " & args[1] & "d"
        found = true; break
    if not found: echo "✗ Job " & id & " not found"
  else: echo "Unknown cron command"

proc authCmd() =
  let args = commandLineParams()
  if args.len < 2:
    echo "\nAuth commands:"
    echo "  login       Login via OAuth or paste token"
    echo "  logout      Remove stored credentials"
    echo "  status      Show current auth status"
    return

  case args[1]:
  of "status":
    let store = loadAuthStore()
    if store.credentials.len == 0:
      echo "No authenticated providers."
      echo "Run: picoclaw auth login --provider <name>"
    else:
      echo "\nAuthenticated Providers:"
      echo "------------------------"
      for prov, cred in store.credentials:
        let stat = if cred.isExpired(): "expired" else: "active"
        echo "  " & prov & ":"
        echo "    Method: " & cred.authMethod
        echo "    Status: " & stat
  of "logout":
    if args.len < 3:
      echo "Logging out from all providers"
      let store = AuthStore(credentials: initTable[string, AuthCredential]())
      saveAuthStore(store)
    else:
      deleteCredential(args[2])
      echo "Logged out from " & args[2]
  else: echo "Unknown auth command"

proc createWorkspaceTemplates(workspace: string) =
  let templates = {
    "AGENTS.md": "# Agent Instructions\n\nYou are a helpful AI assistant. Be concise, accurate, and friendly.\n",
    "SOUL.md": "# Soul\n\nI am picoclaw, a lightweight AI assistant powered by AI.\n",
    "USER.md": "# User\n\nInformation about user goes here.\n",
    "IDENTITY.md": "# Identity\n\n## Name\nPicoClaw 🦞\n"
  }.toTable

  for filename, content in templates:
    let path = workspace / filename
    if not fileExists(path):
      writeFile(path, content)
      echo "  Created " & filename

  let memDir = workspace / "memory"
  createDir(memDir)
  let memFile = memDir / "MEMORY.md"
  if not fileExists(memFile):
    writeFile(memFile, "# Long-term Memory\n\nThis file stores important information.")
    echo "  Created memory/MEMORY.md"

proc onboardCmd() =
  let cfgPath = getHomeDir() / ".picoclaw" / "config.json"
  if fileExists(cfgPath):
    stdout.write("Config already exists. Overwrite? (y/n): ")
    let res = try: stdin.readLine() except: "n"
    if res.toLowerAscii != "y":
      echo "Aborted."
      return

  let cfg = defaultConfig()
  if saveConfig(cfgPath, cfg):
    let workspace = cfg.getWorkspacePath()
    createDir(workspace)
    createDir(workspace / "memory")
    createDir(workspace / "skills")
    createWorkspaceTemplates(workspace)

    echo logo & " picoclaw is ready!"
    echo "\nNext steps:"
    echo "  1. Add your API key to " & cfgPath
    echo "  2. Chat: picoclaw agent -m \"Hello!\""

proc agentCmd() {.async.} =
  var message = ""
  var sessionKey = "cli:default"
  var debug = false

  var optP = initOptParser()
  while true:
    optP.next()
    case optP.kind:
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case optP.key:
      of "m", "message": message = optP.val
      of "s", "session": sessionKey = optP.val
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

  let sm = newSubagentManager(provider, cfg.getWorkspacePath(), mb, cfg.agents.defaults.model)
  al.registerTool(newSpawnTool(sm))

  let cs = newCronService(cfg.getWorkspacePath() / "cron" / "jobs.json")
  al.registerTool(newCronTool(cs, mb))
  cs.onJob = proc(job: CronJob): Future[string] {.async.} =
    return await al.processMessage(InboundMessage(
      channel: "system",
      senderID: "cron",
      chatID: if job.payload.deliver: job.payload.channel & ":" & job.payload.to else: "cli:direct",
      content: job.payload.message,
      sessionKey: "cron:" & job.id
    ))
  asyncCheck cs.start()

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
      let input = try: stdin.readLine().strip() except EOFError: "exit"
      if input == "exit" or input == "quit":
        echo "\nGoodbye!"
        break
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
  let cfg = loadConfig(cfgPath)
  echo logo & " picoclaw Status"
  echo ""
  if fileExists(cfgPath):
    echo "Config: " & cfgPath & " ✓"
    echo "Model:  " & cfg.agents.defaults.model
  else:
    echo "Config: " & cfgPath & " ✗"

  let store = loadAuthStore()
  if store.credentials.len > 0:
    echo "\nAuthenticated Providers:"
    for prov, cred in store.credentials:
      let stat = if cred.isExpired(): "expired" else: "active"
      echo "  " & prov & ": " & stat

proc gatewayCmd() {.async.} =
  let cfg = loadConfig(getHomeDir() / ".picoclaw" / "config.json")
  let mb = newMessageBus()
  let provider = createProvider(cfg)
  let al = newAgentLoop(cfg, mb, provider)

  # Setup all standard tools
  al.registerTool(newReadFileTool())
  al.registerTool(newWriteFileTool())
  al.registerTool(newListDirTool())
  al.registerTool(newEditFileTool(cfg.getWorkspacePath()))
  al.registerTool(newExecTool(cfg.getWorkspacePath()))
  al.registerTool(newWebSearchTool(cfg.tools.web.search.api_key, cfg.tools.web.search.max_results))
  al.registerTool(newWebFetchTool())
  al.registerTool(newMessageTool(mb))

  let sm = newSubagentManager(provider, cfg.getWorkspacePath(), mb, cfg.agents.defaults.model)
  al.registerTool(newSpawnTool(sm))

  let cs = newCronService(cfg.getWorkspacePath() / "cron" / "jobs.json")
  al.registerTool(newCronTool(cs, mb))
  cs.onJob = proc(job: CronJob): Future[string] {.async.} =
    return await al.processMessage(InboundMessage(
      channel: "system",
      senderID: "cron",
      chatID: if job.payload.deliver: job.payload.channel & ":" & job.payload.to else: "cli:direct",
      content: job.payload.message,
      sessionKey: "cron:" & job.id
    ))
  asyncCheck cs.start()

  let hs = newHeartbeatService(cfg.getWorkspacePath(), 1800, true)
  hs.onHeartbeat = proc(prompt: string): Future[string] {.async.} =
    return await al.processMessage(InboundMessage(
      channel: "system",
      senderID: "heartbeat",
      chatID: "cli:direct",
      content: prompt,
      sessionKey: "system:heartbeat"
    ))
  asyncCheck hs.start()

  let info = al.getStartupInfo()
  echo "\n📦 Agent Status:"
  echo "  • Tools: " & $info["tools"]["count"].getInt() & " loaded"
  echo "  • Skills: " & $info["skills"]["available"].getInt() & "/" & $info["skills"]["total"].getInt() & " available"

  var channels: seq[BaseChannel] = @[]

  if cfg.channels.telegram.enabled:
    channels.add(newTelegramChannel(cfg.channels.telegram.token, mb, cfg.channels.telegram.allow_from))
  if cfg.channels.discord.enabled:
    channels.add(newDiscordChannel(cfg.channels.discord.token, mb, cfg.channels.discord.allow_from))
  if cfg.channels.maixcam.enabled:
    channels.add(newMaixCamChannel(cfg.channels.maixcam.host, cfg.channels.maixcam.port, mb, cfg.channels.maixcam.allow_from))
  if cfg.channels.qq.enabled:
    channels.add(newQQChannel(cfg.channels.qq.app_id, cfg.channels.qq.app_secret, mb, cfg.channels.qq.allow_from))
  if cfg.channels.dingtalk.enabled:
    channels.add(newDingTalkChannel(cfg.channels.dingtalk.client_id, cfg.channels.dingtalk.client_secret, mb, cfg.channels.dingtalk.allow_from))
  if cfg.channels.feishu.enabled:
    channels.add(newFeishuChannel(cfg.channels.feishu.app_id, cfg.channels.feishu.app_secret, mb, cfg.channels.feishu.allow_from))
  if cfg.channels.slack.enabled:
    channels.add(newSlackChannel(cfg.channels.slack.bot_token, cfg.channels.slack.app_token, mb, cfg.channels.slack.allow_from))
  if cfg.channels.whatsapp.enabled:
    channels.add(newWhatsAppChannel(cfg.channels.whatsapp.bridge_url, mb, cfg.channels.whatsapp.allow_from))

  if channels.len == 0:
    echo "No channels enabled in config."
    return

  echo logo & " Starting Gateway with " & $channels.len & " channels..."

  for c in channels:
    asyncCheck c.start()

  # Process outbound messages
  asyncCheck (proc() {.async.} =
    while true:
      let outMsg = await mb.subscribeOutbound()
      for c in channels:
        if c.name == outMsg.channel:
          await c.send(outMsg)
  )()

  await al.run()

proc main() {.async.} =
  let args = commandLineParams()
  if args.len == 0:
    printHelp()
    return

  case args[0]:
  of "onboard": onboardCmd()
  of "agent": await agentCmd()
  of "gateway": await gatewayCmd()
  of "skills": await skillsCmd()
  of "cron": cronCmd()
  of "auth": authCmd()
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
