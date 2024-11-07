{.experimental: "strictFuncs".}
{.experimental: "views".}

import std/tables
import pkg/seiryu

type
  AbstractResource* = object of RootObj

  Resource*[T] = object of AbstractResource
    value: T

func get*[T](resource: Resource[T]): lent T =
  return resource.value

func get*[T](resource: var Resource[T]): var T =
  return resource.value

func set*[T](resource: var Resource[T], value: T) =
  resource.value = value
