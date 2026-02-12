import std/json
import std/jsonutils
import std/os
import std/tables
import std/times
import std/options
import logger

type
  AuthCredential* = object
    accessToken*: string
    refreshToken*: string
    expiresAt*: float
    accountID*: string
    authMethod*: string

  AuthStore* = object
    credentials*: Table[string, AuthCredential]

proc loadAuthStore*(): AuthStore =
  let path = getHomeDir() / ".picoclaw" / "auth.json"
  result = AuthStore(credentials: initTable[string, AuthCredential]())
  if fileExists(path):
    try:
      let data = readFile(path)
      result = data.parseJson().jsonTo(AuthStore)
    except: discard

proc saveAuthStore*(store: AuthStore) =
  let path = getHomeDir() / ".picoclaw" / "auth.json"
  try:
    createDir(path.parentDir())
    writeFile(path, store.toJson().pretty())
  except Exception as e:
    logger.error("auth", "Failed to save auth store", {"error": e.msg})

proc setCredential*(provider: string, cred: AuthCredential) =
  var store = loadAuthStore()
  store.credentials[provider] = cred
  saveAuthStore(store)

proc getCredential*(provider: string): Option[AuthCredential] =
  let store = loadAuthStore()
  if store.credentials.hasKey(provider):
    return some(store.credentials[provider])
  return none(AuthCredential)

proc deleteCredential*(provider: string) =
  var store = loadAuthStore()
  if store.credentials.hasKey(provider):
    store.credentials.del(provider)
    saveAuthStore(store)
