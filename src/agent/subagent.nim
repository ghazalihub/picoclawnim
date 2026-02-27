import std/asyncdispatch
import std/json
import std/tables
import std/times
import std/strformat
import ../providers/types
import ../providers/factory
import ../bus

type
  SubagentTask* = ref object
    id*: string
    task*: string
    label*: string
    originChannel*: string
    originChatID*: string
    status*: string
    result*: string
    created*: float

  SubagentManager* = ref object
    tasks*: Table[string, SubagentTask]
    provider*: Provider
    bus*: MessageBus
    workspace*: string
    nextID*: int
    model*: string

proc newSubagentManager*(provider: Provider, workspace: string, bus: MessageBus, model: string = "gpt-4o"): SubagentManager =
  SubagentManager(
    tasks: initTable[string, SubagentTask](),
    provider: provider,
    bus: bus,
    workspace: workspace,
    nextID: 1,
    model: model
  )

proc runTask(sm: SubagentManager, task: SubagentTask) {.async.} =
  task.status = "running"
  task.created = epochTime()

  let messages = @[
    Message(role: "system", content: "You are a subagent. Complete the given task independently and report the result."),
    Message(role: "user", content: task.task)
  ]

  try:
    let response = await sm.provider.chat(messages, @[], sm.model, %*{"max_tokens": 4096})
    task.status = "completed"
    task.result = response.content
  except Exception as e:
    task.status = "failed"
    task.result = "Error: " & e.msg

  if sm.bus != nil:
    let announceContent = fmt"Task '{task.label}' completed. Result: {task.result}"
    await sm.bus.publishInbound(InboundMessage(
      channel: "system",
      senderID: "subagent:" & task.id,
      chatID: task.originChannel & ":" & task.originChatID,
      content: announceContent
    ))

proc spawn*(sm: SubagentManager, task, label, originChannel, originChatID: string): Future[string] {.async.} =
  let taskID = "subagent-" & $sm.nextID
  sm.nextID += 1

  let subagentTask = SubagentTask(
    id: taskID,
    task: task,
    label: label,
    originChannel: originChannel,
    originChatID: originChatID,
    status: "running",
    created: epochTime()
  )
  sm.tasks[taskID] = subagentTask

  # Run in background
  discard runTask(sm, subagentTask)

  if label != "":
    return fmt"Spawned subagent '{label}' for task: {task}"
  return fmt"Spawned subagent for task: {task}"
