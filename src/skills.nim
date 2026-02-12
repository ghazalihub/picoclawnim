import std/json
import std/strutils
import std/os
import std/httpclient
import std/asyncdispatch
import logger

type
  SkillInfo* = object
    name*: string
    path*: string
    source*: string
    description*: string

  SkillsLoader* = ref object
    workspace: string
    workspaceSkills: string
    globalSkills: string
    builtinSkills: string

  AvailableSkill* = object
    name*: string
    repository*: string
    description*: string
    author*: string
    tags*: seq[string]

proc newSkillsLoader*(workspace, globalSkills, builtinSkills: string): SkillsLoader =
  SkillsLoader(
    workspace: workspace,
    workspaceSkills: workspace / "skills",
    globalSkills: globalSkills,
    builtinSkills: builtinSkills
  )

proc extractFrontmatter(content: string): string =
  let lines = content.splitLines()
  if lines.len < 2 or lines[0] != "---": return ""
  var fmLines: seq[string] = @[]
  for i in 1..<lines.len:
    if lines[i] == "---": return fmLines.join("\n")
    fmLines.add(lines[i])
  return ""

proc stripFrontmatter(content: string): string =
  let lines = content.splitLines()
  if lines.len < 2 or lines[0] != "---": return content
  for i in 1..<lines.len:
    if lines[i] == "---":
      if i + 1 < lines.len:
        return lines[i+1..^1].join("\n")
      else:
        return ""
  return content

proc parseSimpleYAML(content: string): JsonNode =
  result = newJObject()
  for line in content.splitLines():
    let s = line.strip()
    if s == "" or s.startsWith("#"): continue
    let parts = s.split(":", 1)
    if parts.len == 2:
      let key = parts[0].strip()
      let val = parts[1].strip().strip(chars = {'"', '\''})
      result[key] = %val

proc getSkillMetadata(path: string): JsonNode =
  try:
    let content = readFile(path)
    let fm = extractFrontmatter(content)
    if fm == "": return %*{"name": path.parentDir().extractFilename()}
    return parseSimpleYAML(fm)
  except:
    return %*{"name": path.parentDir().extractFilename()}

proc listSkillsInDir(dir: string, source: string): seq[SkillInfo] =
  result = @[]
  if dir == "" or not dirExists(dir): return
  for kind, path in walkDir(dir):
    if kind == pcDir:
      let skillFile = path / "SKILL.md"
      if fileExists(skillFile):
        var info = SkillInfo(
          name: path.extractFilename(),
          path: skillFile,
          source: source
        )
        let meta = getSkillMetadata(skillFile)
        if meta.hasKey("description"):
          info.description = meta["description"].getStr()
        result.add(info)

proc loadSkill*(sl: SkillsLoader, name: string): (string, bool) =
  # Try all sources in priority order
  for dir in [sl.workspaceSkills, sl.globalSkills, sl.builtinSkills]:
    let path = dir / name / "SKILL.md"
    if fileExists(path):
      try:
        return (stripFrontmatter(readFile(path)), true)
      except: discard
  return ("", false)

proc loadSkillsForContext*(sl: SkillsLoader, skillNames: seq[string]): string =
  if skillNames.len == 0: return ""
  var parts: seq[string] = @[]
  for name in skillNames:
    let (content, ok) = sl.loadSkill(name)
    if ok:
      parts.add("### Skill: " & name & "\n\n" & content)
  return parts.join("\n\n---\n\n")

proc listSkills*(sl: SkillsLoader): seq[SkillInfo] =
  var skills: seq[SkillInfo] = @[]

  # Workspace
  let wsSkills = listSkillsInDir(sl.workspaceSkills, "workspace")
  skills.add(wsSkills)

  # Global
  let glSkills = listSkillsInDir(sl.globalSkills, "global")
  for gs in glSkills:
    var exists = false
    for s in skills:
      if s.name == gs.name:
        exists = true
        break
    if not exists: skills.add(gs)

  # Builtin
  let biSkills = listSkillsInDir(sl.builtinSkills, "builtin")
  for bs in biSkills:
    var exists = false
    for s in skills:
      if s.name == bs.name:
        exists = true
        break
    if not exists: skills.add(bs)

  return skills

proc getSkillsInfo*(sl: SkillsLoader): JsonNode =
  let skills = sl.listSkills()
  var names = newJArray()
  for s in skills: names.add(%s.name)
  return %*{"total": skills.len, "available": skills.len, "names": names}

proc escapeXml(s: string): string =
  s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

proc buildSkillsSummary*(sl: SkillsLoader): string =
  let skills = sl.listSkills()
  if skills.len == 0: return ""

  var lines = @["<skills>"]
  for s in skills:
    lines.add("  <skill>")
    lines.add("    <name>" & escapeXml(s.name) & "</name>")
    lines.add("    <description>" & escapeXml(s.description) & "</description>")
    lines.add("    <location>" & escapeXml(s.path) & "</location>")
    lines.add("    <source>" & escapeXml(s.source) & "</source>")
    lines.add("  </skill>")
  lines.add("</skills>")
  return lines.join("\n")


type
  SkillInstaller* = ref object
    workspace: string

proc newSkillInstaller*(workspace: string): SkillInstaller =
  SkillInstaller(workspace: workspace)

proc installFromGitHub*(si: SkillInstaller, repo: string) {.async.} =
  let skillName = repo.extractFilename()
  let skillDir = si.workspace / "skills" / skillName

  if dirExists(skillDir):
    raise newException(ValueError, "Skill already exists: " & skillName)

  let url = "https://raw.githubusercontent.com/" & repo & "/main/SKILL.md"
  let client = newAsyncHttpClient()
  try:
    let response = await client.get(url)
    if response.code != Http200:
      raise newException(IOError, "Failed to fetch skill: " & $response.code)

    let body = await response.body
    createDir(skillDir)
    writeFile(skillDir / "SKILL.md", body)
    logger.info("skills", "Skill installed successfully", {"name": skillName})
  finally:
    client.close()

proc listAvailableSkills*(si: SkillInstaller): Future[seq[AvailableSkill]] {.async.} =
  let url = "https://raw.githubusercontent.com/sipeed/picoclaw-skills/main/skills.json"
  let client = newAsyncHttpClient()
  try:
    let response = await client.get(url)
    if response.code == Http200:
      let body = await response.body
      return parseJson(body).to(seq[AvailableSkill])
  finally:
    client.close()
  return @[]
