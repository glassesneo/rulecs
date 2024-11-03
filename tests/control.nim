import ../src/rulecs

type
  Position = object
    x, y: int

  Velocity = object
    x, y: int

var world = World.init()

world.setupSystems()

for i in 0 ..< 20:
  let e = world.spawnEntity()
  world.attachComponent(e, Position(x: 0, y: 0))
  if i mod 2 == 0:
    world.attachComponent(e, Velocity(x: 5, y: 5))

func generate() {.system.} =
  for i in 0 ..< 10:
    let e = control.spawnEntity()
    control.attachComponent(e, Position(x: 0, y: 0))
    if i mod 2 == 0:
      control.attachComponent(e, Velocity(x: 5, y: 5))
    debugEcho "generate: ", e[].id
  debugEcho "===========finish generating============="

func destroyMovable(movables: [All[Position, Velocity]]) {.system.} =
  for id in movables:
    control.destroyEntity(control.getEntityById(id))
    debugEcho "destroy: ", id

world.registerRuntimeSystem(generate)
world.registerRuntimeSystem(destroyMovable)

for _ in 0 ..< 3:
  world.performRuntimeSystems()
