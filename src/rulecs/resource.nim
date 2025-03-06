{.experimental: "strictFuncs".}
{.experimental: "views".}

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

# For `with` macro from seiryu package
func enter*[T](resource: Resource[T]): T =
  return resource.value

func enter*[T](resource: var Resource[T]): ptr T =
  return addr resource.value

func exit*[T](resource: Resource[T]) =
  discard

func exit*[T](resource: var Resource[T]) =
  discard
