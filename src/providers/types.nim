import std/json
import std/options

type
  ToolCall* = object
    id*: string
    `type`*: string
    name*: string
    arguments*: JsonNode

  FunctionCall* = object
    name*: string
    arguments*: string

  MessageToolCall* = object
    id*: string
    `type`*: string
    function*: FunctionCall

  Message* = object
    role*: string
    content*: string
    tool_calls*: Option[seq[MessageToolCall]]
    tool_call_id*: string

  UsageInfo* = object
    prompt_tokens*: int
    completion_tokens*: int
    total_tokens*: int

  LLMResponse* = object
    content*: string
    tool_calls*: seq[ToolCall]
    finish_reason*: string
    usage*: Option[UsageInfo]

  ToolFunctionDefinition* = object
    name*: string
    description*: string
    parameters*: JsonNode

  ToolDefinition* = object
    `type`*: string
    function*: ToolFunctionDefinition
