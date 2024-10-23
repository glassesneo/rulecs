{.experimental: "strictFuncs".}
{.experimental: "strictDefs".}
{.experimental: "views".}

import std/macros
import std/packedsets
import rulecs/[entity, world]

type Query* = object
  idSet: PackedSet[EntityId]
  world: ptr World

func init*(T: type Query, idSet = initPackedSet[EntityId](), world: ptr World): T =
  return Query(idSet: idSet, world: world)

macro `of`*(loop: ForLoopStmt): untyped =
  let
    id = loop[0]
    query = loop[^2][1]
    typeTuple = loop[^2][2]
    loopBody = loop[^1]

  let storageDef = newStmtList()
  for i, T in typeTuple:
    let variableName = loop[i + 1]
    if T.kind == nnkPtrTy:
      let T2 = T[0]
      let storageName = ident("storage" & T2.strVal)
      storageDef.add quote do:
        let `storageName` = addr `query`.world[].storageOf(`T2`)
      loopBody.insert 0,
        quote do:
          let `variableName` = addr `storageName`[][`id`]
    else:
      let storageName = ident("storage" & T.strVal)
      storageDef.add quote do:
        let `storageName` = addr `query`.world[].storageOf(`T`)
      loopBody.insert 0,
        quote do:
          let `variableName` = addr `storageName`[][`id`]

  let resLoop = nnkForStmt.newTree(
    id,
    quote do:
      `query`.idSet,
    `loopBody`,
  )

  result = quote:
    block:
      `storageDef`
      `resLoop`
