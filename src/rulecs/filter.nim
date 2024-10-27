import std/packedsets
import std/sets
import std/tables
import pkg/seiryu
import rulecs/[component]

type FilterCache* =
  tuple[cacheAll, cacheAny, cacheNone: Table[ComponentId, PackedSet[EntityId]]]

type ArchetypeFilter* =
  tuple[
    queryAll, queryAny, queryNone: HashSet[string],
    archetypeAll, archetypeAny, archetypeNone: ComponentId,
  ]

func init*(
    T: type ArchetypeFilter,
    queryAll: seq[string],
    queryAny: seq[string],
    queryNone: seq[string],
): T =
  result.queryAll = queryAll.toHashSet()
  result.queryAny = queryAny.toHashSet()
  result.queryNone = queryNone.toHashSet()
