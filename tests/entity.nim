import ../src/rulecs

type Position = object
  x, y: int

var world = World.new()

let entity = world.spawnEntity()

world.attachComponent(entity, Position(x: 5, y: 5))
echo world.storageOf(Position).len()

world.detachComponent(entity, Position)
echo world.storageOf(Position).len()
