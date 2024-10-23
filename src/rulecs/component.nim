{.experimental: "strictFuncs".}
{.experimental: "strictDefs".}
{.experimental: "views".}

import std/tables
import rulecs/[entity]

type
  AbstractComponentStorage* = object of RootObj
    indexTable: Table[EntityId, Natural]
    freeIndex: seq[Natural]

  ComponentStorage*[T] = object of AbstractComponentStorage
    storage: seq[T]

func init*[C](T: type ComponentStorage[C]): T =
  return ComponentStorage[C](
    indexTable: initTable[EntityId, Natural](), freeIndex: @[], storage: @[]
  )

func contains*(storage: AbstractComponentStorage, entityId: EntityId): bool =
  return entityId in storage.indexTable

func len*(storage: AbstractComponentStorage): Natural =
  return storage.indexTable.len()

func removeEntity*(storage: var AbstractComponentStorage, entityId: sink EntityId) =
  var index: Natural = 0
  if storage.indexTable.pop(entityId, index):
    storage.freeIndex.add index

func `[]`*[T](storage: ComponentStorage[T], entityId: sink EntityId): lent T =
  return storage.storage[storage.indexTable[entityId]]

func `[]`*[T](storage: var ComponentStorage[T], entityId: sink EntityId): var T =
  return storage.storage[storage.indexTable[entityId]]

func `[]=`*[T](
    storage: var ComponentStorage[T], entityId: sink EntityId, value: sink T
) =
  if entityId in storage:
    storage.storage[storage.indexTable[entityId]] = value
    return

  if storage.freeIndex.len > 0:
    let index = storage.freeIndex.pop()
    storage.indexTable[entityId] = index
    storage.storage[index] = value
    return

  storage.indexTable[entityId] = storage.storage.len
  storage.storage.add(value)
