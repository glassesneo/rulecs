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
    componentRegistry: ComponentRegistry
    componentStorages: Table[string, AbstractComponentStorage]
    resourceTable: Table[string, AbstractResource]
    runtimeSystems, startupSystems, terminateSystems: Table[string, System]

  ComponentQuery* = object
    idSet: PackedSet[EntityId]
    world: ptr World

  QueryTable* = Table[string, ComponentQuery]

  Condition* = (Entity) -> bool

  ArchetypeFilter* = object
    queryAll: HashSet[string]
    condition: Condition

  SystemKind* = enum
    Startup
    Runtime
    Terminate

  Action* = (QueryTable) -> void

  System* = object
    queryToFilter: Table[string, ArchetypeFilter]
    queryTable: QueryTable
    kind: SystemKind
    action: Action

func init*(T: type World): T {.construct.} =
  result.entityManager = EntityManager.init()
  result.componentRegistry = ComponentRegistry.init()
  result.componentStorages = initTable[string, AbstractComponentStorage]()
  result.resourceTable = initTable[string, AbstractResource]()

proc spawnEntity*(world: var World): ptr Entity {.discardable.} =
  return world.entityManager.spawnEntity()

proc getEntityById*(world: World, id: sink EntityId): ptr Entity =
  return addr world.entityManager.entityTable[id]

func storageOf*(world: World, T: typedesc): lent ComponentStorage[T] =
  return ComponentStorage[T](world.componentStorages[typetraits.name(T)])

func mutableStorageOf*(world: var World, T: typedesc): var ComponentStorage[T] =
  return ComponentStorage[T](world.componentStorages[typetraits.name(T)])

func attachComponent*[T](world: var World, entity: ptr Entity, data: sink T) =
  let typeName = typetraits.name(T)

  if typeName notin world.componentRegistry:
    world.componentRegistry.registerComponentType(typeName)

  if typeName notin world.componentStorages:
    world.componentStorages[typeName] =
      ComponentStorage[T].init(id = world.componentRegistry[typeName])

  world.mutableStorageOf(T).putEntity(entity, data)

proc detachComponent*(world: var World, entity: ptr Entity, T: typedesc) =
  world.componentStorages[typetraits.name(T)].removeEntity(entity)

proc resetEntity*(world: var World, entity: ptr Entity) =
  entity[].resetArchetype()
  for storage in world.componentStorages.mvalues:
    storage.removeEntity(entity)

proc destroyEntity*(world: var World, entity: ptr Entity) =
  world.entityManager.freeEntityId(entity[].id)
  world.resetEntity(entity)
  entity[].destroy()

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
    T: type ArchetypeFilter,
    queryAll: seq[string],
      # queryAny = initHashSet[string](),
      # queryNone = initHashSet[string](),
): T {.construct.} =
  result.queryAll = queryAll.toHashSet()

func init(
    T: type System, queryToFilter: Table[string, ArchetypeFilter], action: Action
): T {.construct.} =
  result.queryToFilter = queryToFilter
  result.queryTable = initTable[string, ComponentQuery]()
  result.action = action

proc conductRuntimeSystem*(world: var World) =
  for system in world.runtimeSystems.mvalues:
    for queryName, filter in system.queryToFilter:
      let queriedIdSet: PackedSet[EntityId] = collect(initPackedSet()):
        for id, entity in world.entityManager.entityTable:
          if filter.condition(entity):
            {id}

      system.queryTable[queryName] = ComponentQuery.init(queriedIdSet, addr world)

    system.action(system.queryTable)

proc createFilter(world: var World, filter: var ArchetypeFilter) =
  let idList = collect(newSeq):
    for typeName in filter.queryAll:
      if typeName notin world.componentRegistry:
        world.componentRegistry.registerComponentType(typeName)

      world.componentRegistry[typeName]

  let archetypeAll = idList.foldl(a.dup(setBit(b)), ComponentId(0))

  filter.condition = (entity: Entity) => entity.hasAll(archetypeAll)

proc registerSystem(world: var World, system: sink System, name: string) =
  for name, filter in system.queryToFilter.mpairs:
    world.createFilter(filter)

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

func gatherFilters(filterNode: NimNode): tuple[qAll: seq[string]] {.compileTime.} =
  case filterNode[0].strVal
  of "All":
    result.qAll = filterNode[1 ..^ 1].mapIt(it.strVal)
  # of "Any":
  #   discard
  # of "None":
  #   discard
  else:
    error "Unsupported filter", filterNode[0]

macro system*(theProc: untyped): untyped =
  let systemName = theProc[0]

  let queryTableNode = ident"queryTable"
  let tableConstr = nnkTableConstr.newTree()
  let actionBody = theProc.body.copyNimTree()

  for argument in theProc.params[1 ..^ 1]:
    let argName = argument[0]
    let argNameStrLit = argName.strVal.newStrLitNode()

    if argument[1].kind == nnkBracket:
      for filterNode in argument[1]:
        let (qAll) = filterNode.gatherFilters()
        let qAllLit = qAll.newLit()
        let filterInitNode = quote:
          ArchetypeFilter.init(`qAllLit`)

        tableConstr.add newColonExpr(argNameStrLit, filterInitNode)

      actionBody.insert 0,
        quote do:
          let `argName` = `queryTableNode`[`argNameStrLit`]
    else:
      error "Unsupported syntax", argument

  let action = quote:
    proc(`queryTableNode`: QueryTable) =
      `actionBody`

  return quote:
    var `systemName` = System.init(`tableConstr`.toTable(), `action`)

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
