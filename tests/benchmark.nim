import std/sets
import std/times
import ../src/rulecs

const dt = 1 / 60

type
  Position = object
    x, y: float

  Velocity = object
    x, y: float

let time = cpuTime()

var world = World.new()

var entitySet = initHashSet[Entity]()

for i in 0 ..< 10000:
  let entity = world.spawnEntity()
  world.attachComponent(entity, Position(x: 0f, y: 0f))
  world.attachComponent(entity, Velocity(x: 5f, y: 5f))
  entitySet.incl entity

let query = Query.init(entities = entitySet, world = addr world)

for i in 0 ..< 10000:
  for e, pos, vel in query of (ptr Position, Velocity):
    pos.x += vel.x * dt
    pos.y += vel.y * dt

echo "Time taken: ", cpuTime() - time
