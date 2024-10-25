{.experimental: "strictFuncs".}
{.experimental: "strictDefs".}
{.experimental: "views".}

import std/bitops
import std/sequtils
import std/sugar
import std/macros
import std/packedsets
import std/sets
import std/tables
import std/typetraits
import pkg/seiryu
import rulecs/[component, resource]

type
  World* = object
    entityManager: EntityManager
    nextComponentId: ComponentId
    storageTable: Table[string, AbstractComponentStorage]
    unusedComponentTypes: HashSet[string]
    resourceTable: Table[string, AbstractResource]
    unusedSystems, runtimeSystems, startupSystems, terminateSystems:
      Table[string, System]

  ComponentQuery* = object
    idSet: PackedSet[EntityId]
    world: ptr World

  QueryTable* = Table[string, ComponentQuery]

  Condition* = (Entity) -> bool
  Action* = (QueryTable) -> void

  SystemKind* = enum
    Startup
    Runtime
    Terminate

  System* = object
    queryAll: HashSet[string]
    kind: SystemKind
    condition: Condition
    action: Action

func init*(T: type World): T {.construct.} =
  result.entityManager = EntityManager.init()
  result.storageTable = initTable[string, AbstractComponentStorage]()
  result.unusedComponentTypes = initHashSet[string]()
  result.unusedSystems = initTable[string, System]()
  result.resourceTable = initTable[string, AbstractResource]()

proc spawnEntity*(world: var World): ptr Entity {.discardable.} =
  return world.entityManager.spawnEntity()

proc resetEntity*(world: var World, entity: ptr Entity) =
  entity[].resetArchetype()
  for storage in world.storageTable.mvalues:
    storage.removeEntity(entity)

proc destroyEntity*(world: var World, entity: ptr Entity) =
  world.entityManager.freeEntityId(entity[].id)
  world.resetEntity(entity)
  entity[].destroy()

proc getEntityById*(world: World, id: sink EntityId): ptr Entity =
  return addr world.entityManager.entityTable[id]

func storageOf*(world: World, T: typedesc): lent ComponentStorage[T] =
  return ComponentStorage[T](world.storageTable[typetraits.name(T)])

func mutableStorageOf*(world: var World, T: typedesc): var ComponentStorage[T] =
  return ComponentStorage[T](world.storageTable[typetraits.name(T)])

func attachComponent*[T](world: var World, entity: ptr Entity, data: sink T) =
  let typeName = typetraits.name(T)
  if typeName notin world.storageTable:
    world.storageTable[typeName] =
      ComponentStorage[T].init(1'u64 shl world.nextComponentId)
    world.nextComponentId.inc()

  world.mutableStorageOf(T).putEntity(entity, data)

proc detachComponent*(world: var World, entity: ptr Entity, T: typedesc) =
  world.storageTable[typetraits.name(T)].removeEntity(entity)

func resourceOf*(world: World, T: typedesc): lent Resource[T] =
  return Resource[T](world.resourceTable[typetraits.name(T)])

func mutableResourceOf*(world: var World, T: typedesc): var Resource[T] =
  return Resource[T](world.resourceTable[typetraits.name(T)])

func addResource*[T](world: var World, data: sink T) =
  world.resourceTable[typetraits.name(T)] = Resource[T].init(data)

func init*(
    T: type ComponentQuery, idSet = initPackedSet[EntityId](), world: ptr World
): T =
  return ComponentQuery(idSet: idSet, world: world)

func init(
    T: type System,
    queryAll = initHashSet[string](),
      # queryAny = initHashSet[string](),
      # queryNone = initHashSet[string](),
    action: Action,
): T {.construct.} =
  result.queryAll = queryAll
  result.action = action

proc registerSystem(world: var World, system: sink System, name: string) =
  if not system.queryAll.allIt(it in world.unusedComponentTypes):
    world.unusedSystems[name] = system
    return

  let idList = collect(newSeq):
    for storage in world.storageTable.values:
      storage.id

  let archetypeAll = idList.foldl(a.dup(setBit(b)), ComponentId(0))

  system.condition = (entity: Entity) => entity.hasAll(archetypeAll)

  case system.kind
  of Runtime:
    world.runtimeSystems[name] = system
  of Startup:
    world.startupSystems[name] = system
  of Terminate:
    world.terminateSystems[name] = system

macro registerRuntimeSystem*(world: World, system: untyped) =
  let systemName = system.strVal.newStrLitNode()
  return quote:
    `system`.kind = Runtime
    `world`.registerSystem(`system`, name = `systemName`)

macro system*(theProc: untyped): untyped =
  let systemName = theProc[0]

  result = quote:
    var `systemName` = System.init()

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
        let `storageName` = `query`.world[].storageOf(`T`)
      loopBody.insert 0,
        quote do:
          let `variableName` = `storageName`[`id`]

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
