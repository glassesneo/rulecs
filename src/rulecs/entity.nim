{.experimental: "strictFuncs".}
{.experimental: "strictDefs".}
{.experimental: "views".}

import std/hashes
import std/tables
import pkg/seiryu

type EntityId* = distinct uint32

func `==`*(a, b: EntityId): bool {.borrow.}
func `$`*(id: EntityId): string {.borrow.}

const InvalidEntityId* = EntityId(0)

type Entity* = object
  id: EntityId

func new(T: type Entity, id: EntityId): T {.construct.}

func hash*(entity: Entity): Hash =
  return uint32(entity.id).hash()

func id*(entity: Entity): lent EntityId =
  return entity.id

func `$`*(entity: Entity): string =
  return "Entity(id: " & $entity.id & ")"

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

func spawnEntity*(manager: var EntityManager): lent Entity {.discardable.} =
  var id: EntityId
  if manager.freeIds.len == 0:
    id = move(manager.nextId)
    manager.entityTable[id] = Entity.new(id)
    manager.nextId = EntityId(id.uint32 + 1)
  else:
    id = manager.freeIds.pop()
    manager.entityTable[id] = Entity.new(id)

  return manager.entityTable[id]

func freeEntityId*(manager: var EntityManager, id: sink EntityId) =
  manager.entityTable.del id
  manager.freeIds.add id
