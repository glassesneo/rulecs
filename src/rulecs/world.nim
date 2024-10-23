{.experimental: "strictFuncs".}
{.experimental: "strictDefs".}
{.experimental: "views".}

import std/sets
import std/tables
import std/typetraits
import pkg/seiryu
import rulecs/[entity, component, resource]

type World* = object
  entityManager: EntityManager
  storageTable: Table[string, AbstractComponentStorage]
  resourceTable: Table[string, AbstractResource]

func new*(T: type World): T {.construct.} =
  result.entityManager = EntityManager.init()
  result.storageTable = initTable[string, AbstractComponentStorage]()
  result.resourceTable = initTable[string, AbstractResource]()

func spawnEntity*(world: var World): lent Entity {.discardable.} =
  return world.entityManager.spawnEntity()

proc destroyEntity*(world: var World, entity: sink Entity) =
  world.entityManager.freeEntityId(entity.id)
  for storage in world.storageTable.mvalues:
    storage.removeEntity entity

  entity.destroy

proc getEntityById*(world: World, id: sink EntityId): lent Entity =
  return world.entityManager.entityTable[id]

func storageOf*(world: World, T: typedesc): lent ComponentStorage[T] =
  return ComponentStorage[T](world.storageTable[typetraits.name(T)])

func mutableStorageOf*(world: var World, T: typedesc): var ComponentStorage[T] =
  return ComponentStorage[T](world.storageTable[typetraits.name(T)])

func attachComponent*[T](world: var World, entity: sink Entity, data: sink T) =
  if typetraits.name(T) notin world.storageTable:
    world.storageTable[typetraits.name(T)] = ComponentStorage[T].init()

  world.mutableStorageOf(T)[entity] = data

func detachComponent*(world: var World, entity: sink Entity, T: typedesc) =
  world.storageTable[typetraits.name(T)].removeEntity entity

func resourceOf*(world: World, T: typedesc): lent Resource[T] =
  return Resource[T](world.resourceTable[typetraits.name(T)])

func mutableResourceOf*(world: var World, T: typedesc): var Resource[T] =
  return Resource[T](world.resourceTable[typetraits.name(T)])

func addResource*[T](world: var World, data: sink T) =
  world.resourceTable[typetraits.name(T)] = Resource[T].init(data)
