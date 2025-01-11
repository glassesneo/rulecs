import ../src/rulecs
import pkg/seiryu/sugar

type Option = object
  flag: bool

var world = World.init()

world.addResource(Option(flag: true))

echo world.resourceOf(Option).get().flag

# handle resources via `with` macro from seiryu package
with world.mutableResourceOf(Option) as opt:
  # opt is of type `ptr Option`
  opt.flag = false

func accessOption(option: Res[Option]) {.system.} =
  echo option.flag

func changeOption(option: Res[ptr Option]) {.system.} =
  option.flag = not option.flag

world.registerRuntimeSystems(accessOption)
world.registerRuntimeSystems(changeOption)
world.setupSystems()

for _ in 0 ..< 3:
  world.performRuntimeSystems()
