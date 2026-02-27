import std/asyncdispatch
import std/json
import std/tables
import std/options
import base
import ../cron
import ../bus

type
  CronTool* = ref object of Tool
    service*: CronService
    bus*: MessageBus

proc newCronTool*(service: CronService, bus: MessageBus): CronTool =
  let t = CronTool(
    name: "cron",
    description: "Manage scheduled tasks and reminders.",
    service: service,
    bus: bus
  )
  t.parameters = %*{
    "type": "object",
    "properties": {
      "action": {
        "type": "string",
        "enum": ["add", "list", "remove"]
      },
      "name": {"type": "string"},
      "message": {"type": "string"},
      "every_seconds": {"type": "integer"},
      "cron_expr": {"type": "string"},
      "job_id": {"type": "string"}
    },
    "required": ["action"]
  }
  return t

method execute*(t: CronTool, ctx: JsonNode, args: JsonNode): Future[ToolResult] {.async.} =
  let action = args["action"].getStr()

  case action:
  of "add":
    let name = args.getOrDefault("name").getStr("Unnamed task")
    let message = args.getOrDefault("message").getStr()
    var schedule: CronSchedule
    if args.hasKey("every_seconds"):
      let every = args["every_seconds"].getInt() * 1000
      schedule = CronSchedule(kind: "every", everyMs: some(every.int64))
    elif args.hasKey("cron_expr"):
      schedule = CronSchedule(kind: "cron", expr: args["cron_expr"].getStr())
    else:
      return "Error: either every_seconds or cron_expr is required"

    t.service.addJob(name, schedule, message, false, "", "")
    return "Job added successfully"
  of "list":
    var res = "Scheduled Jobs:\n"
    for j in t.service.store.jobs:
      res &= "- " & j.name & " (" & j.id & ")\n"
    return if t.service.store.jobs.len == 0: "No jobs scheduled" else: res
  of "remove":
    let id = args.getOrDefault("job_id").getStr()
    for i in 0..<t.service.store.jobs.len:
      if t.service.store.jobs[i].id == id:
        t.service.store.jobs.delete(i)
        t.service.saveStore()
        return "Job removed"
    return "Error: Job not found"
  else:
    return "Error: Unknown action"
