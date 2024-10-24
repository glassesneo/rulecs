import ../src/rulecs

type Position = object
  x, y: int

var world = World.new()

let entity = world.spawnEntity()

world.attachComponent(entity, Position(x: 5, y: 5))
echo entity[].archetype

world.detachComponent(entity, Position)
echo entity[].archetype
