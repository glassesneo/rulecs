{.experimental: "strictFuncs".}
{.push experimental: "strictDefs".}
{.experimental: "views".}

type
  AbstractEvent* = object of RootObj
    hasNextEvent*: bool

  Event*[T] = object of AbstractEvent
    currentQueue, nextQueue: seq[T]

func init*[T](E: type Event[T]): E =
  result = Event[T]()
  result.hasNextEvent = false

func len*[T](event: Event[T]): Natural =
  return event.currentQueue.len()

func nextLen*[T](event: Event[T]): Natural =
  return event.nextQueue.len()

func getSingleton*[T](event: Event[T]): lent T =
  return event.currentQueue[0]

func add*[T](event: var Event[T], value: sink T) =
  event.nextQueue.add value
  event.hasNextEvent = true

func moveQueue*[T](event: var Event[T]) =
  event.currentQueue = move event.nextQueue
  event.hasNextEvent = false

iterator items*[T](event: Event[T]): lent T =
  for v in event.currentQueue:
    yield v
