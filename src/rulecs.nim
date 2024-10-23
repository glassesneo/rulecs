import rulecs/[entity, component, world]

# template attachBundle*(world: World, entity: Entity, bundle: tuple) =
#   for component in bundle:
#     world.attachComponent(entity, component)
#
# func `[]`*[T](world: World, entity: Entity, data: T) =
#   world.attachComponent
#
# func `[]`*(world: World, T: typedesc, entity: Entity): T =
#   return world.getMutableComponent(T, entity)

export entity, component, world
