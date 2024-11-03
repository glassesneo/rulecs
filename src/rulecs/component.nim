{.experimental: "strictFuncs".}
{.experimental: "strictDefs".}
{.experimental: "views".}

import std/bitops
import std/hashes
import std/packedsets
import std/tables
import std/typetraits
import pkg/seiryu

type EntityId* = distinct uint32

func `==`*(a, b: EntityId): bool {.borrow.}
func `$`*(id: EntityId): string {.borrow.}

const InvalidEntityId* = EntityId(0)

type ComponentId* = uint64

type Entity* = object
  id: EntityId
  archetype: ComponentId

func new(T: type Entity, id: EntityId): T {.construct.} =
  result.id = id
  result.archetype = 0

func `$`*(entity: Entity): string =
  return "Entity(id: " & $entity.id & ")"

func hash*(entity: Entity): Hash =
  return uint32(entity.id).hash()

func id*(entity: Entity): lent EntityId =
  return entity.id

func setArchetype*(entity: var Entity, id: ComponentId) =
  entity.archetype.setBit(id)

func clearArchetype*(entity: var Entity, id: ComponentId) =
  entity.archetype.clearBit(id)

func resetArchetype*(entity: sink Entity) =
  entity.archetype = 0

func hasArchetype*(entity: Entity, id: ComponentId): bool =
  return entity.archetype.testBit(id)

func hasAll*(entity: Entity, subset: ComponentId): bool =
  return bitand(entity.archetype, subset) == subset

func hasNone*(entity: Entity, subset: ComponentId): bool =
  return bitand(entity.archetype, subset) == ComponentId(0)

func hasAny*(entity: Entity, subset: ComponentId): bool =
  return not entity.hasNone(subset)

func archetype*(entity: Entity): lent ComponentId {.getter.}

func isValidEntity*(entity: Entity): bool =
  return entity.id != InvalidEntityId

func destroy*(entity: sink Entity) =
  entity.id = InvalidEntityId

type EntityManager* = object
  idSet: PackedSet[EntityId]
  entityTable: Table[EntityId, Entity]
  reservedEntities: seq[Entity]
  nextId: EntityId
  destroyedIds*: seq[EntityId]
  freeIds: seq[EntityId]

func init*(T: type EntityManager): T {.construct.} =
  result.nextId = EntityId(1)
  result.freeIds = @[]

func isModified*(manager: EntityManager): bool =
  return manager.reservedEntities.len != 0

func idSet*(manager: EntityManager): lent PackedSet[EntityId] {.getter.}

func entityTable*(manager: EntityManager): lent Table[EntityId, Entity] {.getter.}

func reservedEntities*(manager: EntityManager): lent seq[Entity] {.getter.}

func generateEntity(manager: var EntityManager): Entity {.discardable.} =
  return
    if manager.freeIds.len == 0:
      let id = move(manager.nextId)
      manager.nextId = EntityId(id.uint32 + 1)
      Entity.new(id)
    else:
      let id = manager.freeIds.pop()
      Entity.new(id)

proc spawnEntity*(manager: var EntityManager): ptr Entity {.discardable.} =
  let entity = manager.generateEntity()
  manager.entityTable[entity.id] = entity
  manager.idSet.incl entity.id

  return addr manager.entityTable[entity.id]

proc reserveEntity*(manager: var EntityManager): ptr Entity {.discardable.} =
  manager.reservedEntities.add manager.generateEntity()
  return addr manager.reservedEntities[^1]

proc mergeReservedEntities*(manager: var EntityManager) =
  for i in 0 ..< manager.reservedEntities.len:
    var entity = manager.reservedEntities[i]
    manager.idSet.incl entity.id
    manager.entityTable[entity.id] = entity

  manager.reservedEntities.setLen(0)

proc freeEntityId*(manager: var EntityManager, id: sink EntityId) =
  if id in manager.entityTable:
    manager.entityTable.del id
    manager.idSet.excl id
    manager.freeIds.add id

proc freeDestroyedIds*(manager: var EntityManager) =
  while manager.destroyedIds.len() > 0:
    manager.freeEntityId(manager.destroyedIds.pop())

type
  AbstractComponentStorage* = object of RootObj
    id: ComponentId
    indexTable: Table[EntityId, Natural]
    freeIndex: seq[Natural]

  ComponentStorage*[T] = object of AbstractComponentStorage
    storage: seq[T]

func init*(T: type AbstractComponentStorage, id: ComponentId): T {.construct.}

func init*[C](T: type ComponentStorage[C], id: ComponentId): T =
  return ComponentStorage[C](
    id: id, indexTable: initTable[EntityId, Natural](), freeIndex: @[], storage: @[]
  )

func id*(storage: AbstractComponentStorage): lent ComponentId =
  return storage.id

func contains*(storage: AbstractComponentStorage, entityId: EntityId): bool =
  return entityId in storage.indexTable

func len*(storage: AbstractComponentStorage): Natural =
  return storage.indexTable.len()

func putEntity*[T](
    storage: var ComponentStorage[T], entity: ptr Entity, value: sink T
) =
  if entity[].id in storage:
    storage.storage[storage.indexTable[entity[].id]] = value
    return

  if storage.freeIndex.len > 0:
    let index = storage.freeIndex.pop()
    storage.indexTable[entity[].id] = index
    storage.storage[index] = value
    entity[].setArchetype storage.id
    return

  storage.indexTable[entity[].id] = storage.storage.len
  storage.storage.add(value)
  entity[].setArchetype storage.id

proc removeEntity*(storage: var AbstractComponentStorage, entity: ptr Entity) =
  var index: Natural = 0
  if storage.indexTable.pop(entity[].id, index):
    storage.freeIndex.add index
    entity[].clearArchetype(storage.id)

func `[]`*[T](storage: ComponentStorage[T], entityId: sink EntityId): lent T =
  return storage.storage[storage.indexTable[entityId]]

func `[]`*[T](storage: var ComponentStorage[T], entityId: sink EntityId): var T =
  return storage.storage[storage.indexTable[entityId]]

type ComponentRegistry* = object
  nextComponentId: ComponentId
  componentTypes*: Table[string, ComponentId]

func init*(T: type ComponentRegistry): T {.construct.} =
  result.nextComponentId = ComponentId(0)
  result.componentTypes = initTable[string, ComponentId]()

func `[]`*(registry: ComponentRegistry, typeName: string): lent ComponentId =
  return registry.componentTypes[typeName]

func `[]`*(registry: ComponentRegistry, T: typedesc): lent ComponentId =
  return registry[typetraits.name(T)]

func contains*(registry: ComponentRegistry, typeName: string): bool =
  return typeName in registry.componentTypes

func contains*(registry: ComponentRegistry, T: typedesc): bool =
  typetraits.name(T) in registry

func registerComponentType*(registry: var ComponentRegistry, typeName: string) =
  registry.componentTypes[typeName] = 1'u64 shl registry.nextComponentId
  registry.nextComponentId.inc()
