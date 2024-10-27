{.experimental: "strictFuncs".}
{.experimental: "views".}

import
  std/bitops,
  std/sequtils,
  std/sugar,
  std/macros,
  std/packedsets,
  std/sets,
  std/tables,
  std/typetraits
import pkg/seiryu
import rulecs/[component, resource, filter]

{.push experimental: "strictDefs".}
type
  World* = object
    entityManager: EntityManager
    componentRegistry: ComponentRegistry
    componentStorages: Table[string, AbstractComponentStorage]
    resourceTable: Table[string, AbstractResource]
    runtimeSystems, startupSystems, terminateSystems: Table[string, System]
    filterCache: FilterCache

  ComponentQuery* = object
    idSet: PackedSet[EntityId]
    world: ptr World

  QueryTable* = Table[string, ComponentQuery]

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
    T: type System, queryToFilter: Table[string, ArchetypeFilter], action: Action
): T {.construct.} =
  result.queryToFilter = queryToFilter
  result.queryTable = initTable[string, ComponentQuery]()
  result.action = action

func getComponentId(world: var World, typeName: string): ComponentId =
  if typeName notin world.componentRegistry:
    world.componentRegistry.registerComponentType(typeName)

  return world.componentRegistry[typeName]

proc createFilter(world: var World, filter: var ArchetypeFilter) =
  let allIdList = collect(newSeq):
    for typeName in filter.queryAll:
      world.getComponentId(typeName)

  filter.archetypeAll = allIdList.foldl(a.dup(setBit(b)), ComponentId(0))

  let anyIdList = collect(newSeq):
    for typeName in filter.queryAny:
      world.getComponentId(typeName)

  filter.archetypeAny = anyIdList.foldl(a.dup(setBit(b)), ComponentId(0))

  let noneIdList = collect(newSeq):
    for typeName in filter.queryNone:
      world.getComponentId(typeName)

  filter.archetypeNone = noneIdList.foldl(a.dup(setBit(b)), ComponentId(0))

proc registerSystem(world: var World, system: sink System, name: string) =
  for name, filter in system.queryToFilter.mpairs:
    world.createFilter(filter)
    system.queryTable[name] = ComponentQuery.init(world = addr world)

  case system.kind
  of Runtime:
    world.runtimeSystems[name] = system
  of Startup:
    world.startupSystems[name] = system
  of Terminate:
    world.terminateSystems[name] = system

{.pop.}

macro registerRuntimeSystem*(world: World, system: untyped) =
  let systemName = system.strVal.newStrLitNode()
  return quote:
    `system`.kind = Runtime
    `world`.registerSystem(`system`, name = `systemName`)

proc conductRuntimeSystem*(world: var World) =
  for system in world.runtimeSystems.mvalues:
    for queryName, filter in system.queryToFilter:
      let allIdSet = block:
        # Todo: change the condition
        if filter.archetypeAll == 0:
          collect(initPackedSet()):
            for id, entity in world.entityManager.entityTable:
              {id}
        elif filter.archetypeAll in world.filterCache.cacheAll:
          world.filterCache.cacheAll[filter.archetypeAll]
        else:
          echo "All"
          collect(initPackedSet()):
            for id, entity in world.entityManager.entityTable:
              if entity.hasAll(filter.archetypeAll):
                {id}
      let anyIdSet = block:
        if filter.archetypeAny == 0:
          collect(initPackedSet()):
            for id, entity in world.entityManager.entityTable:
              {id}
        elif filter.archetypeAny in world.filterCache.cacheAny:
          world.filterCache.cacheAny[filter.archetypeAny]
        else:
          echo "Any"
          collect(initPackedSet()):
            for id, entity in world.entityManager.entityTable:
              if entity.hasAny(filter.archetypeAny):
                {id}
      let noneIdSet = block:
        if filter.archetypeNone == 0:
          collect(initPackedSet()):
            for id, entity in world.entityManager.entityTable:
              {id}
        elif filter.archetypeNone in world.filterCache.cacheNone:
          world.filterCache.cacheNone[filter.archetypeNone]
        else:
          echo "None"
          collect(initPackedSet()):
            for id, entity in world.entityManager.entityTable:
              if entity.hasNone(filter.archetypeNone):
                {id}

      world.filterCache.cacheAll[filter.archetypeAll] = allIdSet
      world.filterCache.cacheAny[filter.archetypeAny] = anyIdSet
      world.filterCache.cacheNone[filter.archetypeNone] = noneIdSet

      system.queryTable[queryName].idSet = allIdSet * anyIdSet * noneIdSet

    system.action(system.queryTable)

func gatherFilters(
    filterNode: NimNode
): tuple[qAll, qAny, qNone: seq[string]] {.compileTime.} =
  for filter in filterNode:
    case filter[0].strVal
    of "All":
      result.qAll = filter[1 ..^ 1].mapIt(it.strVal)
    of "Any":
      result.qAny = filter[1 ..^ 1].mapIt(it.strVal)
    of "None":
      result.qNone = filter[1 ..^ 1].mapIt(it.strVal)
    else:
      error "Unsupported filter", filter[0]

macro system*(theProc: untyped): untyped =
  let systemName = theProc[0]

  let queryTableNode = ident"queryTable"
  let tableConstr = nnkTableConstr.newTree()
  let actionBody = theProc.body.copyNimTree()

  for argument in theProc.params[1 ..^ 1]:
    let argName = argument[0]
    let argNameStrLit = argName.strVal.newStrLitNode()

    if argument[1].kind == nnkBracket:
      let (qAll, qAny, qNone) = argument[1].gatherFilters()
      let qAllLit = qAll.newLit()
      let qAnyLit = qAny.newLit()
      let qNoneLit = qNone.newLit()
      let filterInitNode = quote:
        ArchetypeFilter.init(`qAllLit`, `qAnyLit`, `qNoneLit`)

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
