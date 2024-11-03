import std/times
import ../src/rulecs

const dt = 1 / 60

type
  Position = object
    x, y: float

  Velocity = object
    x, y: float

var world = World.init()
world.setupSystems()

func generateSystem() {.system.} =
  let entity = control.spawnEntity()
  control.attachComponent(entity, Position(x: 0f, y: 0f))
  control.attachComponent(entity, Velocity(x: 5f, y: 5f))

func moveSystem(movables: [All[Position, Velocity]]) {.system.} =
  for id, pos, vel in movables of (ptr Position, Velocity):
    pos.x += vel.x * dt
    pos.y += vel.y * dt

world.registerRuntimeSystem(generateSystem)
world.registerRuntimeSystem(moveSystem)

let time = cpuTime()
for _ in 0 ..< 1000:
  world.performRuntimeSystems
echo "Time taken: ", cpuTime() - time
