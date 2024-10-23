{.experimental: "strictFuncs".}
{.experimental: "strictDefs".}
{.experimental: "views".}

import std/tables
import rulecs/[entity]

type
  AbstractComponentStorage* = object of RootObj
    indexTable: Table[Entity, Natural]
    freeIndex: seq[Natural]

  ComponentStorage*[T] = object of AbstractComponentStorage
    storage: seq[T]

func init*[C](T: type ComponentStorage[C]): T =
  return ComponentStorage[C](
    indexTable: initTable[Entity, Natural](), freeIndex: @[], storage: @[]
  )

func contains*(storage: AbstractComponentStorage, entity: Entity): bool =
  return entity in storage.indexTable

func len*(storage: AbstractComponentStorage): Natural =
  return storage.indexTable.len()

func removeEntity*(storage: var AbstractComponentStorage, entity: sink Entity) =
  var index: Natural = 0
  if storage.indexTable.pop(entity, index):
    storage.freeIndex.add index

func `[]`*[T](storage: ComponentStorage[T], entity: sink Entity): lent T =
  return storage.storage[storage.indexTable[entity]]

func `[]`*[T](storage: var ComponentStorage[T], entity: sink Entity): var T =
  return storage.storage[storage.indexTable[entity]]

func `[]=`*[T](storage: var ComponentStorage[T], entity: sink Entity, value: sink T) =
  if entity in storage:
    storage.storage[storage.indexTable[entity]] = value
    return

  if storage.freeIndex.len > 0:
    let index = storage.freeIndex.pop()
    storage.indexTable[entity] = index
    storage.storage[index] = value
    return

  storage.indexTable[entity] = storage.storage.len
  storage.storage.add(value)
