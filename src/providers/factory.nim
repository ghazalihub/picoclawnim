import std/asyncdispatch
import std/json
import std/strutils
import types
import http_provider
import claude
import codex
import ../config

type
  Provider* = ref object
    kind*: string
    httpProvider*: HTTPProvider
    claudeProvider*: ClaudeProvider
    codexProvider*: CodexProvider

proc chat*(p: Provider, messages: seq[Message], tools: seq[ToolDefinition], model: string, options: JsonNode): Future[LLMResponse] {.async.} =
  case p.kind:
  of "http": return await p.httpProvider.chat(messages, tools, model, options)
  of "claude": return await p.claudeProvider.chat(messages, tools, model, options)
  of "codex": return await p.codexProvider.chat(messages, tools, model, options)
  else: raise newException(ValueError, "Unknown provider kind")

proc createProvider*(cfg: Config): Provider =
  let model = cfg.agents.defaults.model
  let lowerModel = model.toLowerAscii()

  # Logic matching Go's CreateProvider
  if (lowerModel.contains("claude") or model.startsWith("anthropic/")) and
     (cfg.providers.anthropic.api_key != "" or cfg.providers.anthropic.auth_method != ""):
    if cfg.providers.anthropic.auth_method == "oauth" or cfg.providers.anthropic.auth_method == "token":
      # OAuth/Token logic would go here, for now use standard
      return Provider(kind: "claude", claudeProvider: newClaudeProvider(cfg.providers.anthropic.api_key, cfg.providers.anthropic.api_base))
    return Provider(kind: "claude", claudeProvider: newClaudeProvider(cfg.providers.anthropic.api_key, cfg.providers.anthropic.api_base))

  if (lowerModel.contains("gpt") or model.startsWith("openai/")) and
     (cfg.providers.openai.api_key != "" or cfg.providers.openai.auth_method != ""):
    if cfg.providers.openai.auth_method == "oauth" or cfg.providers.openai.auth_method == "token":
      return Provider(kind: "codex", codexProvider: newCodexProvider(cfg.providers.openai.api_key, "", "")) # accountID from auth store needed
    return Provider(kind: "http", httpProvider: newHTTPProvider(cfg.providers.openai.api_key, if cfg.providers.openai.api_base != "": cfg.providers.openai.api_base else: "https://api.openai.com/v1"))

  # Fallback to standard OpenAI-compatible HTTP provider
  var apiKey = cfg.providers.openrouter.api_key
  var apiBase = cfg.providers.openrouter.api_base
  if apiBase == "": apiBase = "https://openrouter.ai/api/v1"

  if apiKey == "" and cfg.providers.zhipu.api_key != "":
    apiKey = cfg.providers.zhipu.api_key
    apiBase = if cfg.providers.zhipu.api_base != "": cfg.providers.zhipu.api_base else: "https://open.bigmodel.cn/api/paas/v4"

  if apiKey == "" and cfg.providers.groq.api_key != "":
    apiKey = cfg.providers.groq.api_key
    apiBase = if cfg.providers.groq.api_base != "": cfg.providers.groq.api_base else: "https://api.groq.com/openai/v1"

  if apiKey == "":
    # Try any available key
    if cfg.providers.openai.api_key != "":
      apiKey = cfg.providers.openai.api_key
      apiBase = "https://api.openai.com/v1"
    elif cfg.providers.vllm.api_base != "":
      apiKey = cfg.providers.vllm.api_key
      apiBase = cfg.providers.vllm.api_base

  if apiKey == "" and apiBase == "":
    raise newException(ValueError, "No API key configured for model: " & model)

  return Provider(kind: "http", httpProvider: newHTTPProvider(apiKey, apiBase))
