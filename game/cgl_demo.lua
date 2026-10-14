-- Демонстрация Cube Graphics Library в настоящем CC. На компьютере: /repo/game/cgl_demo.lua
-- Стрелки или пробел: следующая сцена, D: дизеринг (телетекст), M: сменить вывод пиксели/телетекст, Q или Ctrl+T: выход, мышь: частицы.
-- С CC: Graphics рисует пикселями (306x171 на 51x19 клеток); без него идёт телетекст (102x57).
-- Аргументы: cgl_demo.lua [graphics|teletext]
local ROOT = "/repo"
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
local loader = cubic.new_loader({ roots = { ROOT .. "/lib", ROOT .. "/examples" } })
local demo = loader.import("cgl_demo")
local args = { ... }
local ok, err = pcall(demo.main, { backend = args[1] or "auto" })
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
if term.setGraphicsMode then term.setGraphicsMode(false) end
term.clear()
term.setCursorPos(1, 1)
if not ok then
  printError("cgl demo: " .. tostring(err))
end
