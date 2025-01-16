{.experimental: "strictFuncs".}
{.experimental: "views".}

import
  std/bitops,
  std/lists,
  std/macros,
  std/macrocache,
  std/packedsets,
  std/sequtils,
  std/sets,
  std/sugar,
  std/tables,
  std/typetraits
import pkg/seiryu
import pkg/seiryu/dbc
import rulecs/[component, event, filter, resource]

const QueryToCTFilterTable = CacheTable"QueryToCTFilter"

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
    resources: Table[string, AbstractResource]
    events: Table[string, AbstractEvent]
    startupSystems, terminateSystems: OrderedTable[string, System]
    runtimeSystems: SystemList
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
    id: Natural
    queryToFilter: Table[string, ArchetypeFilter]
    queryTable: QueryTable
    action: Action

  Stage* = enum
    First
    PreUpdate
    Update
    PostUpdate
    PreDraw
    Draw
    PostDraw
    Last
    PostProcess

  SystemList* = object
    orders: array[Stage, DoublyLinkedList[Natural]]
    systems: seq[System]

func init(T: type Control, world: ptr World): T {.construct.}

func init*(T: type World): T {.construct.} =
  result.entityManager = EntityManager.init()
  result.componentRegistry = ComponentRegistry.init()

func init*(
  T: type ComponentQuery, idSet = initPackedSet[EntityId](), world: ptr World
): T {.construct.}

func init(T: type System, id: Natural, action: Action): T {.construct.}

func init(T: type SystemList): T {.construct.} =
  for stage in Stage.low .. Stage.high:
    result.orders[stage] = initDoublyLinkedList[Natural]()
  result.systems = newSeq[System](len = 1000)

# World
proc spawnEntity*(world: var World): ptr Entity {.discardable.} =
  return world.entityManager.spawnEntity()

proc getEntityById*(world: World, id: EntityId): ptr Entity =
  return world.entityManager.getEntityById(id)

func storageOf*(world: World, T: typedesc): lent ComponentStorage[T] =
  precondition:
    output "world does not have component storage of " & typetraits.name(T)
    T in world.componentRegistry

  return ComponentStorage[T](world.componentStorages[typetraits.name(T)])

func mutableStorageOf*(world: var World, T: typedesc): var ComponentStorage[T] =
  precondition:
    output "world does not have component storage of " & typetraits.name(T)
    T in world.componentRegistry

  return ComponentStorage[T](world.componentStorages[typetraits.name(T)])

proc getComponent*[T](world: World, entity: ptr Entity, _: typedesc[T]): lent T =
  return world.storageOf(T)[entity[].id]

proc getMutableComponent*[T](
    world: var World, entity: ptr Entity, _: typedesc[T]
): var T =
  return world.mutableStorageOf(T)[entity[].id]

proc hasComponent*[T](world: World, entity: ptr Entity, _: typedesc[T]): bool =
  return
    T in world.componentRegistry and
    entity.hasAll(world.componentRegistry[typetraits.name(T)])

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

proc destroyEntity*(world: var World, entity: ptr Entity) =
  for storage in world.componentStorages.mvalues:
    storage.removeEntity(entity)
  world.entityManager.freeEntityId(entity[].id)
  entity[].resetArchetype()
  entity[].destroy()

func hasResource*(world: World, T: typedesc): bool =
  return typetraits.name(T) in world.resources

func hasResource*(world: World, typeName: string): bool =
  return typeName in world.resources

func resourceOf*(world: World, T: typedesc): lent Resource[T] =
  precondition:
    output "world does not have resource of " & typetraits.name(T)
    world.hasResource(T)

  return Resource[T](world.resources[typetraits.name(T)])

func mutableResourceOf*(world: var World, T: typedesc): var Resource[T] =
  precondition:
    output "world does not have resource of " & typetraits.name(T)
    world.hasResource(T)

  return Resource[T](world.resources[typetraits.name(T)])

func addResource*[T](world: var World, value: sink T) =
  let typeName = typetraits.name(T)

  if not world.hasResource(typeName):
    world.resources[typeName] = Resource[T]()

  world.mutableResourceOf(T).set(value)

func eventOf*(world: World, T: typedesc): lent Event[T] =
  precondition:
    output "world does not have event of " & typetraits.name(T)
    typetraits.name(T) in world.events

  return Event[T](world.events[typetraits.name(T)])

func mutableEventOf*(world: var World, T: typedesc): var Event[T] =
  precondition:
    output "world does not have event of " & typetraits.name(T)
    typetraits.name(T) in world.events

  return Event[T](world.events[typetraits.name(T)])

func registerEvent*(world: var World, T: typedesc) =
  precondition:
    output typetraits.name(T) & "is already registered"
    typetraits.name(T) notin world.events

  let typeName = typetraits.name(T)

  world.events[typeName] = Event[T].init()

func dispatchEvent*[T](world: var World, data: sink T) =
  world.mutableEventOf(T).add data

macro setupSystems*(world: var World): untyped =
  result = newStmtList(
    quote do:
      `world`.control = Control.init(addr `world`)
  )
  for typeName, T in CTComponentRegistry:
    result.add quote do:
      if `world`.componentRegistry.contains(`typeName`) and
          not `world`.componentStorages.contains(`typeName`):
        `world`.componentStorages[`typeName`] =
          ComponentStorage[`T`].init(id = `world`.componentRegistry[`typeName`])

func getComponentId(world: var World, typeName: string): ComponentId =
  if typeName notin world.componentRegistry:
    world.componentRegistry.registerComponentType(typeName)

  return world.componentRegistry[typeName]

# Control
proc getEntityById*(control: Control, id: EntityId): ptr Entity =
  return control.world[].getEntityById(id)

func getComponentId*(control: Control, T: typedesc): lent ComponentId =
  precondition:
    let typeName = typetraits.name(T)
    output "world does not have component storage of " & typeName
    typeName in control.world[].componentRegistry

  return control.world[].componentRegistry[typetraits.name(T)]

proc getComponent*[T](control: Control, entity: ptr Entity, _: typedesc[T]): lent T =
  return control.world[].storageOf(T)[entity[].id]

proc getMutableComponent*[T](
    control: var Control, entity: ptr Entity, _: typedesc[T]
): var T =
  return control.world[].mutableStorageOf(T)[entity[].id]

proc hasComponent*[T](control: Control, entity: ptr Entity, _: typedesc[T]): bool =
  return control.world[].hasComponent(entity, T)

func hasResource*(control: Control, T: typedesc): bool =
  return control.world[].hasResource(T)

func hasResource*(control: Control, typeName: string): bool =
  return control.world[].hasResource(typeName)

proc registerReservedEntities(control: var Control) =
  if control.reservedEntities.len() == 0:
    return

  control.isModified = true
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

proc dispatchEvent*[T](control: var Control, data: sink T) =
  control.world[].mutableEventOf(T).add data

# SystemList
{.pop.}

proc createFilter(world: var World, ctFilter: CompileTimeFilter): ArchetypeFilter =
  for i, filterKind in ctFilter:
    let idList = ctFilter[i].mapIt(world.getComponentId(it))
    result[i] = idList.foldl(a.dup(setBit(b)), ComponentId(0))

proc convertFilter(
    world: var World,
    system: var System,
    queryToCTFilter: Table[string, CompileTimeFilter],
) =
  for name, ctFilter in queryToCTFilter.pairs:
    system.queryToFilter[name] = world.createFilter(ctFilter)
    system.queryTable[name] = ComponentQuery.init(world = addr world)

macro registerStartupSystems*(world: World, systems: varargs[untyped]) =
  result = newStmtList()
  for system in systems:
    let systemName = system.strVal
    let systemNameLit = systemName.newStrLitNode()
    let queryToCTFilter = QueryToCTFilterTable[systemName]
    result.add quote do:
      `world`.convertFilter(`system`, `queryToCTFilter`)
      `world`.startupSystems[`systemNameLit`] = `system`

macro registerRuntimeSystems*(world: World, systems: varargs[untyped]) =
  result = newStmtList()
  for system in systems:
    let systemName = system.strVal
    let queryToCTFilter = QueryToCTFilterTable[systemName]
    result.add quote do:
      `world`.convertFilter(`system`, `queryToCTFilter`)
      `world`.runtimeSystems.orders[Stage.Update].add `system`.id
      if `system`.id >= `world`.runtimeSystems.systems.len():
        `world`.runtimeSystems.systems.setLen(`system`.id + 1)
      `world`.runtimeSystems.systems[`system`.id] = `system`

macro registerRuntimeSystemsAt*(world: World, stage: Stage, systems: varargs[untyped]) =
  result = newStmtList()
  for system in systems:
    let systemName = system.strVal
    let queryToCTFilter = QueryToCTFilterTable[systemName]
    result.add quote do:
      `world`.convertFilter(`system`, `queryToCTFilter`)
      `world`.runtimeSystems.orders[`stage`].add `system`.id
      if `system`.id >= `world`.runtimeSystems.systems.len():
        `world`.runtimeSystems.systems.setLen(`system`.id + 1)
      `world`.runtimeSystems.systems[`system`.id] = `system`

macro registerTerminateSystems*(world: World, systems: varargs[untyped]) =
  result = newStmtList()
  for system in systems:
    let systemName = system.strVal
    let systemNameLit = systemName.newStrLitNode()
    let queryToCTFilter = QueryToCTFilterTable[systemName]
    result.add quote do:
      `world`.convertFilter(`system`, `queryToCTFilter`)
      `world`.terminateSystems[`systemNameLit`] = `system`

proc performStartupSystems*(world: var World) =
  defer:
    world.control.isModified = false
    world.control.registerReservedEntities()
    world.control.freeDestroyedIds()

  for system in world.startupSystems.mvalues:
    for queryName, filter in system.queryToFilter:
      var targetedIdSet: PackedSet[EntityId] = block:
        let res = collect(initPackedSet()):
          for id, entity in world.entityManager.entityTable:
            if entity.hasAll(filter[All]):
              {id}
        world.filterCache[filter[All]] = res
        res

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

proc run(system: sink System, world: var World) =
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

proc performRuntimeSystems*(world: var World) =
  defer:
    world.control.isModified = false
    world.control.registerReservedEntities()
    world.control.freeDestroyedIds()

  for stage in Stage.low .. Stage.high:
    for id in world.runtimeSystems.orders[stage]:
      world.runtimeSystems.systems[id].run(world)

proc performTerminateSystems*(world: var World) =
  # defer:
  #   world.control.isModified = false
  #   world.control.registerReservedEntities()
  #   world.control.freeDestroyedIds()

  for system in world.terminateSystems.mvalues:
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

iterator items*(query: ComponentQuery): ptr Entity =
  for id in query.idSet:
    yield query.world[].getEntityById(id)

# DSL
func gatherFilters(
    filterNode: NimNode
): tuple[qAll, qAny, qNone: seq[string]] {.compileTime.} =
  for filter in filterNode:
    case filter[0].strVal
    of "All":
      for T in filter[1 ..^ 1]:
        result.qAll.add(T.strVal)
        if T.strval notin CTComponentRegistry:
          CTComponentRegistry[T.strVal] = T
    of "Any":
      for T in filter[1 ..^ 1]:
        result.qAny.add(T.strVal)
        if T.strval notin CTComponentRegistry:
          CTComponentRegistry[T.strVal] = T
    of "None":
      for T in filter[1 ..^ 1]:
        result.qNone.add(T.strVal)
        if T.strval notin CTComponentRegistry:
          CTComponentRegistry[T.strVal] = T
    else:
      error "Unsupported filter", filter[0]

const SystemIdCounter = CacheCounter"SystemIdCounter"

macro system*(theProc: untyped): untyped =
  let systemName = theProc[0].basename
  let systemId = SystemIdCounter.value()
  SystemIdCounter.inc()

  let queryTableNode = ident"queryTable"
  let controlNode = ident"control"
  let tableConstr = nnkTableConstr.newTree()
  let actionBody = theProc.body.copyNimTree()

  for argument in theProc.params[1 ..^ 1]:
    let argName = argument[0]
    let argNameStrLit = argName.strVal.newStrLitNode()

    case argument[1].kind
    of nnkBracket:
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
    of nnkBracketExpr:
      let variableName = argument[0]
      let T = argument[1][1]
      case argument[1][0].strVal
      of "Resource", "Res":
        if T.kind == nnkPtrTy:
          let T2 = T[0]
          let resourceName = ident("resource" & T2.strVal)
          actionBody.insert 0,
            quote do:
              let `variableName` = block:
                let `resourceName` = addr `controlNode`.world[].resourceOf(`T2`)
                addr `resourceName`[].get()
        else:
          let resourceName = ident("resource" & T.strVal)
          actionBody.insert 0,
            quote do:
              let `variableName` = block:
                let `resourceName` = addr `controlNode`.world[].resourceOf(`T`)
                `resourceName`[].get
      of "Event":
        actionBody.insert 0,
          quote do:
            let `variableName` = `controlNode`.world[].eventOf(`T`)
            if `variableName`.hasNextEvent:
              `controlNode`.world[].mutableEventOf(`T`).moveQueue()
      else:
        error "Unsupported syntax", argument[1][0]
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

  QueryToCTFilterTable[systemName.strVal] = ctFilterTable

  return quote:
    var `systemName` = System.init(`systemId`, `action`)

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
          let `variableName` = addr `storageName`[][`entity`[].id]
    else:
      let storageName = ident("storage" & T.strVal)
      storageDef.add quote do:
        let `storageName` = `query`.world[].storageOf(`T`)
      loopBody.insert 0,
        quote do:
          let `variableName` = `storageName`[`entity`[].id]

  let resLoop = nnkForStmt.newTree(
    entity,
    quote do:
      `query`,
    `loopBody`,
  )

  result = quote:
    block:
      `storageDef`
      `resLoop`
