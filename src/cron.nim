import std/asyncdispatch
import std/json
import std/jsonutils
import std/os
import std/times
import std/options
import std/strutils
import std/tables
import logger

type
  CronSchedule* = object
    kind*: string
    atMs*: Option[int64]
    everyMs*: Option[int64]
    expr*: string
    tz*: string

  CronPayload* = object
    kind*: string
    message*: string
    deliver*: bool
    channel*: string
    to*: string

  CronJobState* = object
    nextRunAtMs*: Option[int64]
    lastRunAtMs*: Option[int64]
    lastStatus*: string
    lastError*: string

  CronJob* = object
    id*: string
    name*: string
    enabled*: bool
    schedule*: CronSchedule
    payload*: CronPayload
    state*: CronJobState
    createdAtMs*: int64
    updatedAtMs*: int64
    deleteAfterRun*: bool

  CronStore* = object
    version*: int
    jobs*: seq[CronJob]

  CronService* = ref object
    storePath*: string
    store*: CronStore
    running*: bool
    onJob*: proc(job: CronJob): Future[string] {.async.}

proc newCronService*(storePath: string): CronService =
  let cs = CronService(
    storePath: storePath,
    store: CronStore(version: 1, jobs: @[]),
    running: false
  )
  if fileExists(storePath):
    try:
      let data = readFile(storePath)
      cs.store = data.parseJson().jsonTo(CronStore)
    except:
      logger.error("cron", "Failed to load cron store")
  return cs

proc saveStore*(cs: CronService) =
  try:
    createDir(cs.storePath.parentDir())
    writeFile(cs.storePath, cs.store.toJson().pretty())
  except Exception as e:
    logger.error("cron", "Failed to save cron store", {"error": e.msg})

proc computeNextRun(cs: CronService, job: CronJob): Option[int64] =
  let nowMs = epochTime() * 1000
  case job.schedule.kind:
  of "at":
    if job.schedule.atMs.isSome and job.schedule.atMs.get() > nowMs.int64:
      return job.schedule.atMs
  of "every":
    if job.schedule.everyMs.isSome:
      return some(nowMs.int64 + job.schedule.everyMs.get())
  of "cron":
    # Simplistic cron implementation: run every minute if expr matches
    # In a full implementation, we'd use a cron parser.
    discard
  return none(int64)

proc checkJobs(cs: CronService) {.async.} =
  let nowMs = (epochTime() * 1000).int64
  var jobsToRun: seq[string] = @[]

  for i in 0..<cs.store.jobs.len:
    let job = cs.store.jobs[i]
    if job.enabled and job.state.nextRunAtMs.isSome and job.state.nextRunAtMs.get() <= nowMs:
      jobsToRun.add(job.id)

  for id in jobsToRun:
    # Find and execute
    for i in 0..<cs.store.jobs.len:
      if cs.store.jobs[i].id == id:
        var job = cs.store.jobs[i]
        logger.info("cron", "Executing job", {"name": job.name})

        if cs.onJob != nil:
          try:
            discard await cs.onJob(job)
            cs.store.jobs[i].state.lastStatus = "ok"
          except Exception as e:
            cs.store.jobs[i].state.lastStatus = "error"
            cs.store.jobs[i].state.lastError = e.msg

        cs.store.jobs[i].state.lastRunAtMs = some(nowMs)
        cs.store.jobs[i].updatedAtMs = nowMs

        if job.schedule.kind == "at":
          if job.deleteAfterRun:
            cs.store.jobs.delete(i)
            break
          else:
            cs.store.jobs[i].enabled = false
            cs.store.jobs[i].state.nextRunAtMs = none(int64)
        else:
          cs.store.jobs[i].state.nextRunAtMs = cs.computeNextRun(cs.store.jobs[i])

        cs.saveStore()
        break

proc start*(cs: CronService) {.async.} =
  logger.info("cron", "Starting Cron service")
  cs.running = true

  # Initial next run computation
  for i in 0..<cs.store.jobs.len:
    if cs.store.jobs[i].enabled and cs.store.jobs[i].state.nextRunAtMs.isNone:
      cs.store.jobs[i].state.nextRunAtMs = cs.computeNextRun(cs.store.jobs[i])
  cs.saveStore()

  while cs.running:
    await cs.checkJobs()
    await sleepAsync(1000)

proc addJob*(cs: CronService, name: string, schedule: CronSchedule, message: string, deliver: bool, channel, to: string) =
  let nowMs = (epochTime() * 1000).int64
  let id = $nowMs # Simple ID
  let job = CronJob(
    id: id,
    name: name,
    enabled: true,
    schedule: schedule,
    payload: CronPayload(kind: "agent_turn", message: message, deliver: deliver, channel: channel, to: to),
    createdAtMs: nowMs,
    updatedAtMs: nowMs,
    deleteAfterRun: schedule.kind == "at"
  )
  cs.store.jobs.add(job)
  cs.store.jobs[^1].state.nextRunAtMs = cs.computeNextRun(cs.store.jobs[^1])
  cs.saveStore()
