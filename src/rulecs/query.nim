{.experimental: "strictFuncs".}
{.experimental: "strictDefs".}
{.experimental: "views".}

import std/macros
import std/sets
import rulecs/[entity, world]

type Query* = object
  entities: HashSet[Entity]
  world: ptr World

func init*(T: type Query, entities = initHashSet[Entity](), world: ptr World): T =
  return Query(entities: entities, world: world)

macro `of`*(loop: ForLoopStmt): untyped =
  let
    entity = loop[0]
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
          let `variableName` = addr `storageName`[][`entity`]
    else:
      let storageName = ident("storage" & T.strVal)
      storageDef.add quote do:
        let `storageName` = addr `query`.world[].storageOf(`T`)
      loopBody.insert 0,
        quote do:
          let `variableName` = addr `storageName`[][`entity`]

  let resLoop = nnkForStmt.newTree(
    entity,
    quote do:
      `query`.entities,
    `loopBody`,
  )

  result = quote:
    block:
      `storageDef`
      `resLoop`
