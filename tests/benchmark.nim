import std/packedsets
import std/times
import pkg/seiryu/aop
import ../src/rulecs

const dt = 1 / 60

type
  Position = object
    x, y: float

  Velocity = object
    x, y: float

var time: float
advice log:
  before:
    time = cpuTime()
  after:
    echo "Time taken: ", cpuTime() - time

proc main() {.log.} =
  var world = World.init()
  var idSet = initPackedSet[EntityId]()

  for i in 0 ..< 10000:
    let entity = world.spawnEntity()
    world.attachComponent(entity, Position(x: 0f, y: 0f))
    world.attachComponent(entity, Velocity(x: 5f, y: 5f))
    idSet.incl entity[].id

  let query = ComponentQuery.init(idSet = idSet, world = addr world)

  for i in 0 ..< 10000:
    for id, pos, vel in query of (ptr Position, Velocity):
      pos.x += vel.x * dt
      pos.y += vel.y * dt

main()
