{.experimental: "strictFuncs".}
{.experimental: "strictDefs".}
{.experimental: "views".}

import std/sets
import std/tables
import std/typetraits
import pkg/seiryu
import rulecs/[component, resource]

type World* = object
  entityManager: EntityManager
  nextComponentId: ComponentId
  storageTable: Table[string, AbstractComponentStorage]
  resourceTable: Table[string, AbstractResource]

func new*(T: type World): T {.construct.} =
  result.entityManager = EntityManager.init()
  result.storageTable = initTable[string, AbstractComponentStorage]()
  result.resourceTable = initTable[string, AbstractResource]()

func spawnEntity*(world: var World): ptr Entity {.discardable.} =
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
