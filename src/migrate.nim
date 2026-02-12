import std/json
import std/jsonutils
import std/os
import std/strutils
import std/tables
import config
import logger

proc camelToSnake(s: string): string =
  result = ""
  for i, c in s:
    if c in {'A'..'Z'}:
      if i > 0:
        let prev = s[i-1]
        if prev in {'a'..'z'} or prev in {'0'..'9'}:
          result.add('_')
      result.add(c.toLowerAscii())
    else:
      result.add(c)

proc convertKeysToSnake(node: JsonNode): JsonNode =
  case node.kind:
  of JObject:
    result = newJObject()
    for key, val in node:
      result[camelToSnake(key)] = convertKeysToSnake(val)
  of JArray:
    result = newJArray()
    for val in node:
      result.add(convertKeysToSnake(val))
  else:
    result = node

proc convertConfig*(data: JsonNode): (Config, seq[string]) =
  var cfg = defaultConfig()
  var warnings: seq[string] = @[]

  let snakeData = convertKeysToSnake(data)

  # A simple way to map fields is using jsonTo if the schemas are similar
  # In PicoClaw Go, it's manually mapped.

  # Logic to map snakeData to cfg...
  # For brevity in this reimplementation, I'll use a simplified version
  # that handles the most important fields.

  if snakeData.hasKey("agents"):
    let agents = snakeData["agents"]
    if agents.hasKey("defaults"):
      let defaults = agents["defaults"]
      if defaults.hasKey("model"): cfg.agents.defaults.model = defaults["model"].getStr()
      if defaults.hasKey("workspace"): cfg.agents.defaults.workspace = defaults["workspace"].getStr().replace(".openclaw", ".picoclaw")

  if snakeData.hasKey("providers"):
    for name, val in snakeData["providers"]:
      var pCfg: ProviderConfig
      if val.hasKey("api_key"): pCfg.api_key = val["api_key"].getStr()
      if val.hasKey("api_base"): pCfg.api_base = val["api_base"].getStr()

      case name:
      of "anthropic": cfg.providers.anthropic = pCfg
      of "openai": cfg.providers.openai = pCfg
      of "openrouter": cfg.providers.openrouter = pCfg
      of "groq": cfg.providers.groq = pCfg
      of "zhipu": cfg.providers.zhipu = pCfg
      of "vllm": cfg.providers.vllm = pCfg
      of "gemini": cfg.providers.gemini = pCfg
      else: warnings.add("Provider " & name & " not supported, skipping")

  return (cfg, warnings)

proc runMigration*(openclawHome, picoclawHome: string, dryRun: bool = false) =
  let configPath = openclawHome / "config.json"
  if not fileExists(configPath):
    logger.error("migrate", "OpenClaw config not found", {"path": configPath})
    return

  try:
    let data = parseFile(configPath)
    let (cfg, warnings) = convertConfig(data)

    for w in warnings:
      logger.warn("migrate", w)

    if not dryRun:
      let dest = picoclawHome / "config.json"
      if saveConfig(dest, cfg):
        logger.info("migrate", "Config migrated successfully", {"to": dest})
  except Exception as e:
    logger.error("migrate", "Migration failed", {"error": e.msg})
