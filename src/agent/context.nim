import std/os
import std/strutils
import std/strformat
import std/times
import std/json
import ../providers/types
import ../skills
import ../tools/base
import memory

type
  ContextBuilder* = ref object
    workspace: string
    skillsLoader: SkillsLoader
    memory: MemoryStore
    tools: ToolRegistry

proc newContextBuilder*(workspace: string): ContextBuilder =
  let builtinSkillsDir = getAppDir() / "skills"
  let globalSkillsDir = getHomeDir() / ".picoclaw" / "skills"

  ContextBuilder(
    workspace: workspace,
    skillsLoader: newSkillsLoader(workspace, globalSkillsDir, builtinSkillsDir),
    memory: newMemoryStore(workspace)
  )

proc setToolsRegistry*(cb: ContextBuilder, registry: ToolRegistry) =
  cb.tools = registry

proc getIdentity(cb: ContextBuilder): string =
  let nowStr = now().format("yyyy-MM-dd HH:mm (dddd)")
  let workspacePath = expandFilename(cb.workspace)
  let runtime = hostOS & " " & hostCPU

  var toolsSection = ""
  if cb.tools != nil:
    let defs = cb.tools.getDefinitions()
    if defs.len > 0:
      toolsSection = "## Available Tools\n\n**CRITICAL**: You MUST use tools to perform actions. Do NOT pretend to execute commands or schedule tasks.\n\nYou have access to the following tools:\n\n"
      for d in defs:
        let fn = d["function"]
        toolsSection &= "- " & fn["name"].getStr() & ": " & fn["description"].getStr() & "\n"

  result = fmt"""# picoclaw 🦞

You are picoclaw, a helpful AI assistant.

## Current Time
{nowStr}

## Runtime
{runtime}

## Workspace
Your workspace is at: {workspacePath}
- Memory: {workspacePath}/memory/MEMORY.md
- Daily Notes: {workspacePath}/memory/YYYYMM/YYYYMMDD.md
- Skills: {workspacePath}/skills/{{skill-name}}/SKILL.md

{toolsSection}

## Important Rules

1. **ALWAYS use tools** - When you need to perform an action (schedule reminders, send messages, execute commands, etc.), you MUST call the appropriate tool. Do NOT just say you'll do it or pretend to do it.

2. **Be helpful and accurate** - When using tools, briefly explain what you're doing.

3. **Memory** - When remembering something, write to {workspacePath}/memory/MEMORY.md"""

proc loadBootstrapFiles(cb: ContextBuilder): string =
  let files = ["AGENTS.md", "SOUL.md", "USER.md", "IDENTITY.md"]
  result = ""
  for f in files:
    let path = cb.workspace / f
    if fileExists(path):
      result &= "## " & f & "\n\n" & readFile(path) & "\n\n"

proc buildSystemPrompt*(cb: ContextBuilder): string =
  var parts: seq[string] = @[]
  parts.add(cb.getIdentity())

  let bootstrap = cb.loadBootstrapFiles()
  if bootstrap != "":
    parts.add(bootstrap)

  let skillsSummary = cb.skillsLoader.buildSkillsSummary()
  if skillsSummary != "":
    parts.add("# Skills\n\nThe following skills extend your capabilities. To use a skill, read its SKILL.md file using the read_file tool.\n\n" & skillsSummary)

  let memoryCtx = cb.memory.getMemoryContext()
  if memoryCtx != "":
    parts.add(memoryCtx)

  return parts.join("\n\n---\n\n")

proc buildMessages*(cb: ContextBuilder, history: seq[Message], summary: string, currentMessage: string, channel, chatID: string): seq[Message] =
  var messages: seq[Message] = @[]
  var systemPrompt = cb.buildSystemPrompt()

  if channel != "" and chatID != "":
    systemPrompt &= "\n\n## Current Session\nChannel: " & channel & "\nChat ID: " & chatID

  if summary != "":
    systemPrompt &= "\n\n## Summary of Previous Conversation\n\n" & summary

  messages.add(Message(role: "system", content: systemPrompt))
  for h in history:
    messages.add(h)

  messages.add(Message(role: "user", content: currentMessage))
  return messages
