import rulecs/[component, resource, world]

func attachComponents*(world: var World, entity: ptr Entity, components: sink tuple) =
  for component in components.fields:
    world.attachComponent(entity, component)

func attachComponents*(
    control: var Control, entity: ptr Entity, components: sink tuple
) =
  for component in components.fields:
    control.attachComponent(entity, component)

export component, resource, world
