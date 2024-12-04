import std/packedsets
import ../src/rulecs

type Position = object
  x, y: int

var world = World.init()

let entity = world.spawnEntity()

world.attachComponent(entity, Position(x: 5, y: 5))

let query = ComponentQuery.init([entity[].id].toPackedSet(), world = addr world)

for entity, pos in query of (ptr Position):
  pos.x = 10

block:
  echo world.getMutableComponent(entity, Position)
