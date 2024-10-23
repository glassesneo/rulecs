import times
import std/sets
import ../src/rulecs

type Position = object
  x, y: int

let time = cpuTime()

var world = World.new()

let entity = world.spawnEntity()

world.attachComponent(entity, Position(x: 5, y: 5))

let query = Query.new([entity].toHashSet(), world = addr world)

for e, pos in query of (ptr Position):
  pos.x = 10

block:
  let storage = world.storageOf(Position)
  echo storage[entity]
