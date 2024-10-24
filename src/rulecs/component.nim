{.experimental: "strictFuncs".}
{.experimental: "strictDefs".}
{.experimental: "views".}

import std/bitops
import std/hashes
import std/tables
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
  entity.archetype.testBit(id)

func archetype*(entity: Entity): lent ComponentId =
  return entity.archetype

func isValidEntity*(entity: Entity): bool =
  return entity.id != InvalidEntityId

func destroy*(entity: sink Entity) =
  entity.id = InvalidEntityId

type EntityManager* = object
  entityTable: Table[EntityId, Entity]
  nextId: EntityId
  freeIds: seq[EntityId]

func init*(T: type EntityManager): T {.construct.} =
  result.entityTable = initTable[EntityId, Entity]()
  result.nextId = EntityId(1)
  result.freeIds = @[]

func entityTable*(manager: EntityManager): lent Table[EntityId, Entity] =
  return manager.entityTable

func spawnEntity*(manager: var EntityManager): ptr Entity {.discardable.} =
  var id: EntityId
  if manager.freeIds.len == 0:
    id = move(manager.nextId)
    manager.entityTable[id] = Entity.new(id)
    manager.nextId = EntityId(id.uint32 + 1)
  else:
    id = manager.freeIds.pop()
    manager.entityTable[id] = Entity.new(id)

  return addr manager.entityTable[id]

func freeEntityId*(manager: var EntityManager, id: sink EntityId) =
  manager.entityTable.del id
  manager.freeIds.add id

type
  AbstractComponentStorage* = object of RootObj
    id: ComponentId
    indexTable: Table[EntityId, Natural]
    freeIndex: seq[Natural]

  ComponentStorage*[T] = object of AbstractComponentStorage
    storage: seq[T]

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
