{.experimental: "strictFuncs".}
{.experimental: "strictDefs".}
{.experimental: "views".}

import std/packedsets
import std/tables
import std/typetraits
import pkg/seiryu
import rulecs/[entity, component]

type World* = ref object
  storageTable: Table[string, AbstractComponentStorage]
  entityManager: EntityManager

func new*(T: type World): T {.construct.} =
  result.storageTable = initTable[string, AbstractComponentStorage]()
  result.entityManager = EntityManager.init()

proc spawnEntity*(world: World): lent Entity {.discardable.} =
  return world.entityManager.spawnEntity()

proc destroyEntity*(world: World, entity: sink Entity) =
  world.entityManager.freeEntityId(entity.id)
  for storage in world.storageTable.mvalues:
    storage.removeEntity entity

  entity.destroy

proc getEntityById*(world: World, id: sink EntityId): lent Entity =
  return world.entityManager.entityTable[id]

func storageOf*(world: World, T: typedesc): lent ComponentStorage[T] =
  return ComponentStorage[T](world.storageTable[typetraits.name(T)])

func mutableStorageOf*(world: World, T: typedesc): var ComponentStorage[T] =
  return ComponentStorage[T](world.storageTable[typetraits.name(T)])

func attachComponent*[T](world: World, entity: sink Entity, data: sink T) =
  if typetraits.name(T) notin world.storageTable:
    world.storageTable[typetraits.name(T)] = ComponentStorage[T].init()

  world.mutableStorageOf(T)[entity] = data

func detachComponent*(world: World, entity: sink Entity, T: typedesc) =
  world.storageTable[typetraits.name(T)].removeEntity entity

type Query* = object
  entityIdSet*: PackedSet[EntityId]
  world: World

func init*(
  T: type Query, entityIdSet = initPackedSet[EntityId](), world: World
): T {.construct.}

iterator `[]`*[T](query: Query, _: typedesc[T]): (lent Entity, var T) =
  for id in query.entityIdSet:
    let entity = query.world.getEntityById(id)
    yield (query.world.getEntityById(id), query.world.mutableStorageOf(T)[entity])

iterator `[]`*[T, U](
    query: Query, _: typedesc[T], _: typedesc[U]
): (lent Entity, var T, var U) =
  for id in query.entityIdSet:
    let entity = query.world.entityManager.entityTable[id]
    yield (
      query.world.entityManager.entityTable[id],
      query.world.mutableStorageOf(T)[entity],
      query.world.mutableStorageOf(U)[entity],
    )

iterator `[]`*[T, U, V](
    query: Query, _: typedesc[T], _: typedesc[U], _: typedesc[V]
): (lent Entity, var T, var U, var V) =
  for id in query.entityIdSet:
    let entity = query.world.entityManager.entityTable[id]
    yield (
      query.world.entityManager.entityTable[id],
      query.world.mutableStorageOf(T)[entity],
      query.world.mutableStorageOf(U)[entity],
      query.world.mutableStorageOf(V)[entity],
    )

iterator `[]`*[T, U, V, W](
    query: Query, _: typedesc[T], _: typedesc[U], _: typedesc[V], _: typedesc[W]
): (lent Entity, var T, var U, var V, var W) =
  for id in query.entityIdSet:
    let entity = query.world.entityManager.entityTable[id]
    yield (
      query.world.entityManager.entityTable[id],
      query.world.mutableStorageOf(T)[entity],
      query.world.mutableStorageOf(U)[entity],
      query.world.mutableStorageOf(V)[entity],
      query.world.mutableStorageOf(W)[entity],
    )
