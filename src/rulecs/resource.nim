{.experimental: "strictFuncs".}
{.experimental: "strictDefs".}
{.experimental: "views".}

type
  AbstractResource* = object of RootObj

  Resource*[T] = object of AbstractResource
    data: T

func init*[C](T: type Resource[C], data: C): T =
  return Resource[C](data: data)

func get*[T](resource: Resource[T]): lent T =
  return resource.data

func get*[T](resource: var Resource[T]): var T =
  return resource.data
