import std/packedsets
import ../src/rulecs

type Position = object
  x, y: int

var world = World.init()

for i in 0 ..< 100:
  let e = world.spawnEntity()
  if i mod 2 == 0:
    world.attachComponent(e, Position(x: 5, y: 5))

proc system(query1: [All[Position]], query2: [All[Position]]) {.system.} =
  echo query1
  echo query2

world.registerRuntimeSystem(system)

world.conductRuntimeSystem()
