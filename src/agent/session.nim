import std/json
import std/jsonutils
import std/os
import std/times
import std/tables
import std/syncio
import ../providers/types
import ../logger

type
  Session* = ref object
    key*: string
    messages*: seq[Message]
    summary*: string
    created*: float # Unix timestamp
    updated*: float # Unix timestamp

  SessionManager* = ref object
    sessions*: Table[string, Session]
    storage*: string

proc newSessionManager*(storage: string): SessionManager =
  let sm = SessionManager(
    sessions: initTable[string, Session](),
    storage: storage
  )
  if storage != "":
    if not dirExists(storage):
      createDir(storage)
    # Load existing sessions
    for file in walkFiles(storage / "*.json"):
      try:
        let data = readFile(file)
        let session = data.parseJson().jsonTo(Session)
        sm.sessions[session.key] = session
      except Exception as e:
        logger.error("session", "Failed to load session", {"file": file, "error": e.msg})
  return sm

proc getOrCreate*(sm: SessionManager, key: string): Session =
  if sm.sessions.hasKey(key):
    return sm.sessions[key]

  let now = epochTime()
  let session = Session(
    key: key,
    messages: @[],
    summary: "",
    created: now,
    updated: now
  )
  sm.sessions[key] = session
  return session

proc addMessage*(sm: SessionManager, key, role, content: string) =
  let session = sm.getOrCreate(key)
  session.messages.add(Message(role: role, content: content))
  session.updated = epochTime()

proc addFullMessage*(sm: SessionManager, key: string, msg: Message) =
  let session = sm.getOrCreate(key)
  session.messages.add(msg)
  session.updated = epochTime()

proc getHistory*(sm: SessionManager, key: string): seq[Message] =
  if sm.sessions.hasKey(key):
    return sm.sessions[key].messages
  return @[]

proc getSummary*(sm: SessionManager, key: string): string =
  if sm.sessions.hasKey(key):
    return sm.sessions[key].summary
  return ""

proc setSummary*(sm: SessionManager, key, summary: string) =
  let session = sm.getOrCreate(key)
  session.summary = summary
  session.updated = epochTime()

proc truncateHistory*(sm: SessionManager, key: string, keepLast: int) =
  if not sm.sessions.hasKey(key): return
  let session = sm.sessions[key]
  if session.messages.len <= keepLast: return
  session.messages = session.messages[^keepLast..^1]
  session.updated = epochTime()

proc save*(sm: SessionManager, session: Session) =
  if sm.storage == "": return
  try:
    let path = sm.storage / session.key & ".json"
    let data = session.toJson()
    writeFile(path, data.pretty())
  except Exception as e:
    logger.error("session", "Failed to save session", {"key": session.key, "error": e.msg})
