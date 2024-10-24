import times
import std/packedsets
import ../src/rulecs

type Position = object
  x, y: int

let time = cpuTime()

var world = World.new()

let entity = world.spawnEntity()

world.attachComponent(entity, Position(x: 5, y: 5))

let query = Query.init([entity[].id].toPackedSet(), world = addr world)

for id, pos in query of (ptr Position):
  pos.x = 10

block:
  let storage = world.storageOf(Position)
  echo storage[entity[].id]
