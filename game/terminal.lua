-- Терминал CubeOS: оболочка CraftOS на весь экран (классические программы CC работают как есть). На компьютере: /repo/game/terminal.lua [программа] [аргументы]
-- Запускает rom/programs/shell.lua (или указанную программу) в окружении совместимости; os.version() возвращает "CubeOS 0.3.0". Выход: команда exit.
local ROOT = "/repo"
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
local loader = cubic.new_loader({ roots = { ROOT .. "/lib" } })

-- компиляция модулей Cubic в CC идёт долго; между модулями отдаём управление
for _, name in ipairs({ "version", "compat.vararg", "compat.bios", "compat.env", "compat.proc" }) do
  loader.import(name)
  os.queueEvent("preload")
  os.pullEvent("preload")
end
local env_mod = loader.import("compat.env")
local proc_mod = loader.import("compat.proc")

local args = { ... }
local program = table.remove(args, 1) or "rom/programs/shell.lua"
local env = env_mod.new({ term = term.current() })
local proc = proc_mod.new(env, program, args, { name = "terminal" })
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
proc:start()
while proc:alive() do
  proc:feed(os.pullEventRaw())
end
