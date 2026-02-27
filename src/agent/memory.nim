import std/os
import std/times
import std/strutils

type
  MemoryStore* = ref object
    workspace: string
    memoryDir: string
    memoryFile: string

proc newMemoryStore*(workspace: string): MemoryStore =
  let memoryDir = workspace / "memory"
  let memoryFile = memoryDir / "MEMORY.md"

  if not dirExists(memoryDir):
    createDir(memoryDir)

  MemoryStore(
    workspace: workspace,
    memoryDir: memoryDir,
    memoryFile: memoryFile
  )

proc getTodayFile(ms: MemoryStore): string =
  let today = now().format("yyyyMMdd")
  let monthDir = today[0..<6]
  return ms.memoryDir / monthDir / (today & ".md")

proc readLongTerm*(ms: MemoryStore): string =
  if fileExists(ms.memoryFile):
    return readFile(ms.memoryFile)
  return ""

proc writeLongTerm*(ms: MemoryStore, content: string) =
  writeFile(ms.memoryFile, content)

proc readToday*(ms: MemoryStore): string =
  let path = ms.getTodayFile()
  if fileExists(path):
    return readFile(path)
  return ""

proc appendToday*(ms: MemoryStore, content: string) =
  let path = ms.getTodayFile()
  let dir = parentDir(path)
  if not dirExists(dir):
    createDir(dir)

  var existing = ""
  if fileExists(path):
    existing = readFile(path)

  var newContent = ""
  if existing == "":
    let header = "# " & now().format("yyyy-MM-dd") & "\n\n"
    newContent = header & content
  else:
    newContent = existing & "\n" & content

  writeFile(path, newContent)

proc getRecentDailyNotes*(ms: MemoryStore, days: int): string =
  var notes: seq[string] = @[]
  for i in 0..<days:
    let date = now() - i.days
    let dateStr = date.format("yyyyMMdd")
    let monthDir = dateStr[0..<6]
    let path = ms.memoryDir / monthDir / (dateStr & ".md")

    if fileExists(path):
      notes.add(readFile(path))

  if notes.len == 0: return ""
  return notes.join("\n\n---\n\n")

proc getMemoryContext*(ms: MemoryStore): string =
  var parts: seq[string] = @[]

  let longTerm = ms.readLongTerm()
  if longTerm != "":
    parts.add("## Long-term Memory\n\n" & longTerm)

  let recent = ms.getRecentDailyNotes(3)
  if recent != "":
    parts.add("## Recent Daily Notes\n\n" & recent)

  if parts.len == 0: return ""
  return "# Memory\n\n" & parts.join("\n\n---\n\n")
