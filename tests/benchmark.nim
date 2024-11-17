import std/times
import ../src/rulecs

const dt = 1 / 60

type
  Position = object
    x, y: float

  Velocity = object
    x, y: float

func generateSystem() {.system.} =
  let entity = control.spawnEntity()
  control.attachComponents(entity, (Position(x: 0f, y: 0f), Velocity(x: 5f, y: 5f)))

func moveSystem(movables: [All[Position, Velocity]]) {.system.} =
  for id, pos, vel in movables of (ptr Position, Velocity):
    pos.x += vel.x * dt
    pos.y += vel.y * dt

var world = World.init()
world.registerRuntimeSystems(generateSystem)
world.registerRuntimeSystems(moveSystem)
world.setupSystems()

let time = cpuTime()
for _ in 0 ..< 10000:
  world.performRuntimeSystems
echo "Time taken: ", cpuTime() - time
