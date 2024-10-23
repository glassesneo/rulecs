import ../src/rulecs

type Option = object
  flag: bool

let world = World.new()

world.addResource(Option(flag: false))

echo world.mutableResourceOf(Option).get()

proc change(option: var Option) =
  option.flag = true

world.mutableResourceOf(Option).get().change()

echo world.mutableResourceOf(Option).get()
