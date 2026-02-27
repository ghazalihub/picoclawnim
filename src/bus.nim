import std/asyncdispatch
import std/tables
import std/deques

type
  InboundMessage* = object
    channel*: string
    senderID*: string
    chatID*: string
    content*: string
    sessionKey*: string
    mediaPaths*: seq[string]
    metadata*: Table[string, string]

  OutboundMessage* = object
    channel*: string
    chatID*: string
    content*: string
    metadata*: Table[string, string]

  AsyncQueue*[T] = ref object
    queue: Deque[T]
    waiters: Deque[Future[T]]

proc newAsyncQueue*[T](size: int = 100): AsyncQueue[T] =
  AsyncQueue[T](
    queue: initDeque[T](),
    waiters: initDeque[Future[T]]()
  )

proc put*[T](q: AsyncQueue[T], item: T) =
  if q.waiters.len > 0:
    let waiter = q.waiters.popFirst()
    waiter.complete(item)
  else:
    q.queue.addLast(item)

proc get*[T](q: AsyncQueue[T]): Future[T] =
  let fut = newFuture[T]("AsyncQueue.get")
  if q.queue.len > 0:
    fut.complete(q.queue.popFirst())
  else:
    q.waiters.addLast(fut)
  return fut

type
  MessageBus* = ref object
    inbound*: AsyncQueue[InboundMessage]
    outbound*: AsyncQueue[OutboundMessage]

proc newMessageBus*(queueSize: int = 100): MessageBus =
  MessageBus(
    inbound: newAsyncQueue[InboundMessage](queueSize),
    outbound: newAsyncQueue[OutboundMessage](queueSize)
  )

proc publishInbound*(mb: MessageBus, msg: InboundMessage) {.async.} =
  mb.inbound.put(msg)

proc consumeInbound*(mb: MessageBus): Future[InboundMessage] {.async.} =
  return await mb.inbound.get()

proc publishOutbound*(mb: MessageBus, msg: OutboundMessage) {.async.} =
  mb.outbound.put(msg)

proc subscribeOutbound*(mb: MessageBus): Future[OutboundMessage] {.async.} =
  return await mb.outbound.get()
