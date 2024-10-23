import ../src/rulecs

type Position = object
  x, y: int

var world = World.new()

let entity = world.spawnEntity()

world.attachComponent(entity.id, Position(x: 5, y: 5))
echo world.storageOf(Position).len()

world.detachComponent(entity.id, Position)
echo world.storageOf(Position).len()
