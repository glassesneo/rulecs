import ../src/rulecs

type
  Position = object
    x, y: int

  Velocity = object
    x, y: int

  Player = object

  Enemy = object

var world = World.init()

world.setupSystems()

let player = world.spawnEntity()
world.attachComponent(player, Position(x: 0, y: 0))
world.attachComponent(player, Velocity(x: 0, y: 0))
world.attachComponent(player, Player())

for i in 0 ..< 10:
  let enemy = world.spawnEntity()
  world.attachComponent(enemy, Position(x: 50, y: 0))
  world.attachComponent(enemy, Velocity(x: 0, y: 0))
  world.attachComponent(enemy, Enemy())

for i in 0 ..< 20:
  let e = world.spawnEntity()
  world.attachComponent(e, Position(x: 0, y: 0))
  if i mod 2 == 0:
    world.attachComponent(e, Velocity(x: 5, y: 5))

proc battle(
    playerQuery: [All[Player], None[Enemy]], enemyQuery: [All[Enemy], None[Player]]
) {.system.} =
  echo playerQuery
  echo enemyQuery

proc move(movableQuery: [All[Position, Velocity]]) {.system.} =
  echo movableQuery

world.registerRuntimeSystem(battle)
world.registerRuntimeSystem(move)

for i in 0 ..< 10:
  world.performRuntimeSystems()
