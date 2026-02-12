import std/json
import std/jsonutils
import std/os
import std/strutils
import logger

type
  AgentDefaults* = object
    workspace*: string
    model*: string
    max_tokens*: int
    temperature*: float64
    max_tool_iterations*: int

  AgentsConfig* = object
    defaults*: AgentDefaults

  WhatsAppConfig* = object
    enabled*: bool
    bridge_url*: string
    allow_from*: seq[string]

  TelegramConfig* = object
    enabled*: bool
    token*: string
    allow_from*: seq[string]

  FeishuConfig* = object
    enabled*: bool
    app_id*: string
    app_secret*: string
    encrypt_key*: string
    verification_token*: string
    allow_from*: seq[string]

  DiscordConfig* = object
    enabled*: bool
    token*: string
    allow_from*: seq[string]

  MaixCamConfig* = object
    enabled*: bool
    host*: string
    port*: int
    allow_from*: seq[string]

  QQConfig* = object
    enabled*: bool
    app_id*: string
    app_secret*: string
    allow_from*: seq[string]

  DingTalkConfig* = object
    enabled*: bool
    client_id*: string
    client_secret*: string
    allow_from*: seq[string]

  SlackConfig* = object
    enabled*: bool
    bot_token*: string
    app_token*: string
    allow_from*: seq[string]

  ChannelsConfig* = object
    whatsapp*: WhatsAppConfig
    telegram*: TelegramConfig
    feishu*: FeishuConfig
    discord*: DiscordConfig
    maixcam*: MaixCamConfig
    qq*: QQConfig
    dingtalk*: DingTalkConfig
    slack*: SlackConfig

  ProviderConfig* = object
    api_key*: string
    api_base*: string
    auth_method*: string

  ProvidersConfig* = object
    anthropic*: ProviderConfig
    openai*: ProviderConfig
    openrouter*: ProviderConfig
    groq*: ProviderConfig
    zhipu*: ProviderConfig
    vllm*: ProviderConfig
    gemini*: ProviderConfig

  GatewayConfig* = object
    host*: string
    port*: int

  WebSearchConfig* = object
    api_key*: string
    max_results*: int

  WebToolsConfig* = object
    search*: WebSearchConfig

  ToolsConfig* = object
    web*: WebToolsConfig

  Config* = object
    agents*: AgentsConfig
    channels*: ChannelsConfig
    providers*: ProvidersConfig
    gateway*: GatewayConfig
    tools*: ToolsConfig

proc defaultConfig*(): Config =
  Config(
    agents: AgentsConfig(
      defaults: AgentDefaults(
        workspace: "~/.picoclaw/workspace",
        model: "glm-4.7",
        max_tokens: 8192,
        temperature: 0.7,
        max_tool_iterations: 20
      )
    ),
    channels: ChannelsConfig(
      whatsapp: WhatsAppConfig(enabled: false, bridge_url: "ws://localhost:3001", allow_from: @[]),
      telegram: TelegramConfig(enabled: false, token: "", allow_from: @[]),
      feishu: FeishuConfig(enabled: false, app_id: "", app_secret: "", encrypt_key: "", verification_token: "", allow_from: @[]),
      discord: DiscordConfig(enabled: false, token: "", allow_from: @[]),
      maixcam: MaixCamConfig(enabled: false, host: "0.0.0.0", port: 18790, allow_from: @[]),
      qq: QQConfig(enabled: false, app_id: "", app_secret: "", allow_from: @[]),
      dingtalk: DingTalkConfig(enabled: false, client_id: "", client_secret: "", allow_from: @[]),
      slack: SlackConfig(enabled: false, bot_token: "", app_token: "", allow_from: @[])
    ),
    providers: ProvidersConfig(
      anthropic: ProviderConfig(),
      openai: ProviderConfig(),
      openrouter: ProviderConfig(),
      groq: ProviderConfig(),
      zhipu: ProviderConfig(),
      vllm: ProviderConfig(),
      gemini: ProviderConfig()
    ),
    gateway: GatewayConfig(host: "0.0.0.0", port: 18790),
    tools: ToolsConfig(
      web: WebToolsConfig(
        search: WebSearchConfig(api_key: "", max_results: 5)
      )
    )
  )

proc expandHome*(path: string): string =
  if path == "": return ""
  if path.startsWith("~"):
    let home = getHomeDir()
    if path.len > 1 and (path[1] == '/' or path[1] == '\\'):
      return home & path[2..^1]
    return home
  return path

proc getWorkspacePath*(c: Config): string =
  expandHome(c.agents.defaults.workspace)

proc applyEnv(c: var Config) =
  # Replicate environmental overrides logic from Go
  template override(field: untyped, envName: string) =
    if existsEnv(envName):
      let val = getEnv(envName)
      when field is string: field = val
      elif field is int: field = parseInt(val)
      elif field is float: field = parseFloat(val)
      elif field is bool: field = val.toLowerAscii == "true"

  override(c.agents.defaults.workspace, "PICOCLAW_AGENTS_DEFAULTS_WORKSPACE")
  override(c.agents.defaults.model, "PICOCLAW_AGENTS_DEFAULTS_MODEL")
  override(c.agents.defaults.max_tokens, "PICOCLAW_AGENTS_DEFAULTS_MAX_TOKENS")
  override(c.agents.defaults.temperature, "PICOCLAW_AGENTS_DEFAULTS_TEMPERATURE")
  override(c.agents.defaults.max_tool_iterations, "PICOCLAW_AGENTS_DEFAULTS_MAX_TOOL_ITERATIONS")

  override(c.channels.telegram.enabled, "PICOCLAW_CHANNELS_TELEGRAM_ENABLED")
  override(c.channels.telegram.token, "PICOCLAW_CHANNELS_TELEGRAM_TOKEN")

  override(c.channels.discord.enabled, "PICOCLAW_CHANNELS_DISCORD_ENABLED")
  override(c.channels.discord.token, "PICOCLAW_CHANNELS_DISCORD_TOKEN")

  override(c.providers.anthropic.api_key, "PICOCLAW_PROVIDERS_ANTHROPIC_API_KEY")
  override(c.providers.openai.api_key, "PICOCLAW_PROVIDERS_OPENAI_API_KEY")
  override(c.providers.openrouter.api_key, "PICOCLAW_PROVIDERS_OPENROUTER_API_KEY")
  override(c.providers.groq.api_key, "PICOCLAW_PROVIDERS_GROQ_API_KEY")
  override(c.providers.zhipu.api_key, "PICOCLAW_PROVIDERS_ZHIPU_API_KEY")
  override(c.providers.gemini.api_key, "PICOCLAW_PROVIDERS_GEMINI_API_KEY")

  override(c.gateway.host, "PICOCLAW_GATEWAY_HOST")
  override(c.gateway.port, "PICOCLAW_GATEWAY_PORT")

proc loadConfig*(path: string): Config =
  var c = defaultConfig()
  if fileExists(path):
    try:
      let jsonNode = parseFile(path)
      c = jsonNode.jsonTo(Config)
    except Exception as e:
      logger.error("config", "Failed to load config", {"path": path, "error": e.msg})

  applyEnv(c)
  return c

proc saveConfig*(path: string, c: Config): bool =
  try:
    let dir = parentDir(path)
    if not dirExists(dir):
      createDir(dir)
    let jsonNode = c.toJson()
    writeFile(path, jsonNode.pretty())
    return true
  except Exception as e:
    logger.error("config", "Failed to save config", {"path": path, "error": e.msg})
    return false
