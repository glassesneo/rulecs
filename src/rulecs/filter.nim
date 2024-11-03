import std/packedsets
import std/sets
import std/tables
import rulecs/[component]

type
  FilterKind* = enum
    All
    Any
    None

  FilterCache* = Table[ComponentId, PackedSet[EntityId]]

  CompileTimeFilter* = array[FilterKind, HashSet[string]]

  ArchetypeFilter* = array[FilterKind, ComponentId]

func init*(
    T: type CompileTimeFilter, filterAll, filterAny, filterNone: seq[string]
): T =
  result[All] = filterAll.toHashSet()
  result[Any] = filterAny.toHashSet()
  result[None] = filterNone.toHashSet()
