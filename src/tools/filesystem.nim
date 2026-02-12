import std/asyncdispatch
import std/json
import std/os
import std/strutils
import base

type
  ReadFileTool* = ref object of Tool
  WriteFileTool* = ref object of Tool
  ListDirTool* = ref object of Tool
  EditFileTool* = ref object of Tool
    workspace*: string

proc newReadFileTool*(): ReadFileTool =
  let t = ReadFileTool(name: "read_file", description: "Read the contents of a file")
  t.parameters = %*{
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Path to the file to read"
      }
    },
    "required": ["path"]
  }
  return t

method execute*(t: ReadFileTool, ctx: JsonNode, args: JsonNode): Future[ToolResult] {.async.} =
  let path = args["path"].getStr()
  if not fileExists(path):
    return "Error: File not found: " & path
  try:
    return readFile(path)
  except Exception as e:
    return "Error reading file: " & e.msg

proc newWriteFileTool*(): WriteFileTool =
  let t = WriteFileTool(name: "write_file", description: "Write content to a file")
  t.parameters = %*{
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Path to the file to write"
      },
      "content": {
        "type": "string",
        "description": "Content to write to the file"
      }
    },
    "required": ["path", "content"]
  }
  return t

method execute*(t: WriteFileTool, ctx: JsonNode, args: JsonNode): Future[ToolResult] {.async.} =
  let path = args["path"].getStr()
  let content = args["content"].getStr()
  try:
    createDir(parentDir(path))
    writeFile(path, content)
    return "File written successfully to " & path
  except Exception as e:
    return "Error writing file: " & e.msg

proc newListDirTool*(): ListDirTool =
  let t = ListDirTool(name: "list_dir", description: "List files and directories in a path")
  t.parameters = %*{
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Path to list"
      }
    },
    "required": ["path"]
  }
  return t

method execute*(t: ListDirTool, ctx: JsonNode, args: JsonNode): Future[ToolResult] {.async.} =
  var path = args["path"].getStr()
  if path == "": path = "."
  if not dirExists(path):
    return "Error: Directory not found: " & path

  var result = ""
  try:
    for kind, entry in walkDir(path):
      case kind:
      of pcDir, pcLinkToDir:
        result &= "DIR:  " & extractFilename(entry) & "\n"
      of pcFile, pcLinkToFile:
        result &= "FILE: " & extractFilename(entry) & "\n"
    return if result == "": "(empty)" else: result
  except Exception as e:
    return "Error listing directory: " & e.msg

proc newEditFileTool*(workspace: string): EditFileTool =
  let t = EditFileTool(name: "edit_file", description: "Edit a file using search and replace blocks", workspace: workspace)
  t.parameters = %*{
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Path to the file to edit"
      },
      "edits": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "search": {"type": "string"},
            "replace": {"type": "string"}
          },
          "required": ["search", "replace"]
        }
      }
    },
    "required": ["path", "edits"]
  }
  return t

method execute*(t: EditFileTool, ctx: JsonNode, args: JsonNode): Future[ToolResult] {.async.} =
  let path = args["path"].getStr()
  if not fileExists(path):
    return "Error: File not found: " & path

  try:
    var content = readFile(path)
    let edits = args["edits"]
    var appliedCount = 0

    for edit in edits:
      let search = edit["search"].getStr()
      let replace = edit["replace"].getStr()
      if search in content:
        content = content.replace(search, replace)
        appliedCount += 1
      else:
        return "Error: Search block not found: " & search

    writeFile(path, content)
    return "Successfully applied " & $appliedCount & " edits to " & path
  except Exception as e:
    return "Error editing file: " & e.msg
