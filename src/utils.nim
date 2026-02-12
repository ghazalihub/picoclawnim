import std/os
import std/strutils
import std/httpclient
import std/asyncdispatch
import logger

proc truncate*(s: string, maxLen: int): string =
  if s.len <= maxLen:
    return s
  return s[0..<maxLen] & "..."

proc expandHome*(path: string): string =
  if path == "": return ""
  if path.startsWith("~"):
    let home = getHomeDir()
    if path.len > 1 and (path[1] == '/' or path[1] == '\\'):
      return home & path[2..^1]
    return home
  return path

proc isAudioFile*(filename: string, contentType: string = ""): bool =
  let ext = filename.splitFile().ext.toLowerAscii()
  let audioExts = [".mp3", ".wav", ".ogg", ".m4a", ".flac", ".aac"]
  if ext in audioExts:
    return true
  if contentType.startsWith("audio/"):
    return true
  return false

type
  DownloadOptions* = object
    loggerPrefix*: string

proc downloadFile*(url: string, filename: string, options: DownloadOptions = DownloadOptions(loggerPrefix: "utils")): string =
  let tempDir = getTempDir() / "picoclaw"
  if not dirExists(tempDir):
    createDir(tempDir)

  let destPath = tempDir / filename
  let client = newHttpClient()
  defer: client.close()

  try:
    logger.debug(options.loggerPrefix, "Downloading file", {"url": url, "dest": destPath})
    client.downloadFile(url, destPath)
    return destPath
  except Exception as e:
    logger.error(options.loggerPrefix, "Failed to download file", {"url": url, "error": e.msg})
    return ""

proc downloadFileAsync*(url: string, filename: string, options: DownloadOptions = DownloadOptions(loggerPrefix: "utils")): Future[string] {.async.} =
  let tempDir = getTempDir() / "picoclaw"
  if not dirExists(tempDir):
    createDir(tempDir)

  let destPath = tempDir / filename
  let client = newAsyncHttpClient()
  defer: client.close()

  try:
    logger.debug(options.loggerPrefix, "Downloading file (async)", {"url": url, "dest": destPath})
    await client.downloadFile(url, destPath)
    return destPath
  except Exception as e:
    logger.error(options.loggerPrefix, "Failed to download file (async)", {"url": url, "error": e.msg})
    return ""
