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
  Control* = object
    world: ptr World
    reservedEntities: seq[Entity]
    destroyedIds: seq[EntityId]
    isModified: bool

  World* = object
    control: Control
    entityManager: EntityManager
    componentRegistry: ComponentRegistry
    componentStorages: Table[string, AbstractComponentStorage]
    resourceTable: Table[string, AbstractResource]
    runtimeSystems, startupSystems, terminateSystems: OrderedTable[string, System]
    filterCache: FilterCache

  ComponentQuery* = object
    idSet: PackedSet[EntityId]
    world: ptr World

  QueryTable* = Table[string, ComponentQuery]

  SystemKind* = enum
    Startup
    Runtime
    Terminate

  Action* = (var Control, QueryTable) -> void

  System* = object
    queryToCTFilter: Table[string, CompileTimeFilter]
    queryToFilter: Table[string, ArchetypeFilter]
    queryTable: QueryTable
    kind: SystemKind
    action: Action

func init(T: type Control, world: ptr World): T {.construct.}

func init*(T: type World): T {.construct.} =
  result.entityManager = EntityManager.init()
  result.componentRegistry = ComponentRegistry.init()

func init*(
    T: type ComponentQuery, idSet = initPackedSet[EntityId](), world: ptr World
): T =
  return ComponentQuery(idSet: idSet, world: world)

func init(
    T: type System, queryToCTFilter: Table[string, CompileTimeFilter], action: Action
): T {.construct.} =
  result.queryToCTFilter = queryToCTFilter
  result.action = action

# World
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

func setupSystems*(world: var World) =
  world.control = Control.init(addr world)

func getComponentId(world: var World, typeName: string): ComponentId =
  if typeName notin world.componentRegistry:
    world.componentRegistry.registerComponentType(typeName)

  return world.componentRegistry[typeName]

# Control
proc getEntityById*(control: Control, id: sink EntityId): ptr Entity =
  return addr control.world[].entityManager.entityTable[id]

proc registerReservedEntities(control: var Control) =
  while control.reservedEntities.len() > 0:
    control.world[].entityManager.registerEntity(control.reservedEntities.pop())

proc freeDestroyedIds(control: var Control) =
  for id in control.destroyedIds:
    control.world[].destroyEntity(control.getEntityById(id))
  control.destroyedIds.setLen(0)

proc spawnEntity*(control: var Control): ptr Entity {.discardable.} =
  let id = control.world[].entityManager.generateEntityId()
  control.reservedEntities.add Entity.init(id)
  return addr control.reservedEntities[^1]

func attachComponent*[T](control: var Control, entity: ptr Entity, data: sink T) =
  control.world[].attachComponent(entity, data)
  control.isModified = true

proc detachComponent*(control: var Control, entity: ptr Entity, T: typedesc) =
  control.world[].detachComponent(entity, T)
  control.isModified = true

proc destroyEntity*(control: var Control, entity: ptr Entity) =
  control.destroyedIds.add entity[].id

{.pop.}

proc createFilter(world: var World, ctFilter: CompileTimeFilter): ArchetypeFilter =
  for i, filterKind in ctFilter:
    let idList = ctFilter[i].mapIt(world.getComponentId(it))
    result[i] = idList.foldl(a.dup(setBit(b)), ComponentId(0))

proc registerSystem(world: var World, system: sink System, name: string) =
  for name, ctFilter in system.queryToCTFilter.pairs:
    system.queryToFilter[name] = world.createFilter(ctFilter)
    system.queryTable[name] = ComponentQuery.init(world = addr world)

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

proc performRuntimeSystems*(world: var World) =
  defer:
    world.control.isModified = false
    world.control.registerReservedEntities()
    world.control.freeDestroyedIds()

  for system in world.runtimeSystems.mvalues:
    for queryName, filter in system.queryToFilter:
      var targetedIdSet: PackedSet[EntityId] = block:
        if filter[All] == 0:
          world.entityManager.idSet
        elif world.control.isModified or filter[All] notin world.filterCache:
          let res = collect(initPackedSet()):
            for id, entity in world.entityManager.entityTable:
              if entity.hasAll(filter[All]):
                {id}
          world.filterCache[filter[All]] = res
          res
        else:
          world.filterCache[filter[All]]

      if filter[Any] != 0:
        for id in targetedIdSet:
          let entity = world.getEntityById(id)
          if not entity[].hasAny(filter[Any]):
            targetedIdSet.excl id

      if filter[None] != 0:
        for id in targetedIdSet:
          let entity = world.getEntityById(id)
          if not entity[].hasNone(filter[None]):
            targetedIdSet.excl id

      system.queryTable[queryName].idSet = targetedIdSet

    system.action(world.control, system.queryTable)

# ComponentQuery
func `$`*(query: ComponentQuery): string =
  return $query.idSet

iterator items*(query: ComponentQuery): lent EntityId =
  for id in query.idSet:
    yield id

# DSL
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
  let controlNode = ident"control"
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
        CompileTimeFilter.init(`qAllLit`, `qAnyLit`, `qNoneLit`)

      tableConstr.add newColonExpr(argNameStrLit, filterInitNode)

      actionBody.insert 0,
        quote do:
          let `argName` = `queryTableNode`[`argNameStrLit`]
    else:
      error "Unsupported syntax", argument

  let action = quote:
    proc(`controlNode`: var Control, `queryTableNode`: QueryTable) =
      `actionBody`

  let ctFilterTable =
    if tableConstr.len == 0:
      quote:
        initTable[string, CompileTimeFilter]()
    else:
      quote:
        `tableConstr`.toTable()

  return quote:
    var `systemName` = System.init(queryToCTFilter = `ctFilterTable`, `action`)

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
      `query`,
    `loopBody`,
  )

  result = quote:
    block:
      `storageDef`
      `resLoop`
