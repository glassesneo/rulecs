import ../src/rulecs

type Option = object
  flag: bool

var world = World.init()
world.setupSystems()

world.addResource(Option(flag: true))

echo world.resourceOf(Option).get().flag

func accessOption(option: Res[Option]) {.system.} =
  echo option.flag

func changeOption(option: Res[ptr Option]) {.system.} =
  option.flag = not option.flag

world.registerRuntimeSystem(accessOption)
world.registerRuntimeSystem(changeOption)
for _ in 0 ..< 3:
  world.performRuntimeSystems()
