import std/packedsets
import ../src/rulecs
import ../src/rulecs/world {.all.}

type Position = object
  x, y: int

var w = World.init()

let entity = w.spawnEntity()

w.attachComponent(entity, Position(x: 5, y: 5))

var system = System.init(
  action = proc(t: QueryTable) =
    discard
)

w.registerRuntimeSystem(system)
