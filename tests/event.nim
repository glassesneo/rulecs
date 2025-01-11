import ../src/rulecs

type SomeEvent = object
  id: int

var count = 0

proc sendEvent*() {.system.} =
  control.dispatchEvent(SomeEvent(id: count))
  count += 1

proc readEvent*(eventQueue: Event[SomeEvent]) {.system.} =
  echo eventQueue.len()
  for e in eventQueue:
    echo "id: ", $e.id

var world = World.init()

world.registerRuntimeSystems(sendEvent, readEvent)
world.registerEvent(SomeEvent)
world.setupSystems()

for _ in 0 ..< 100:
  world.performRuntimeSystems()
