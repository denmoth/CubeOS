-- Демонстрация Cube Graphics Library в настоящем CC. На компьютере: /repo/game/cgl_demo.lua [graphics|teletext] [monitor[=имя]] [scale=число]
-- Стрелки или пробел: следующая сцена, D: дизеринг (телетекст), M: сменить вывод пиксели/телетекст, Q или Ctrl+T: выход, мышь или касание: частицы.
-- С CC: Graphics рисует пикселями (306x171 на 51x19 клеток); без него идёт телетекст (102x57).
-- Монитор: monitor берёт первый найденный монитор (в том числе по проводному модему), monitor=monitor_0 конкретный.
-- scale это масштаб текста монитора (0.5 по умолчанию: больше клеток, чётче картинка).
local ROOT = "/repo"
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
local loader = cubic.new_loader({ roots = { ROOT .. "/lib", ROOT .. "/examples" } })
local demo = loader.import("cgl_demo")

local opts = { backend = "auto" }
local scale = 0.5
local target = nil
for _, a in ipairs({ ... }) do
  if a == "graphics" or a == "teletext" then
    opts.backend = a
  elseif a == "monitor" then
    target = peripheral.find("monitor")
    opts.monitor = target and peripheral.getName(target)
  elseif a:sub(1, 8) == "monitor=" then
    opts.monitor = a:sub(9)
    target = peripheral.wrap(opts.monitor)
  elseif a:sub(1, 6) == "scale=" then
    scale = tonumber(a:sub(7)) or scale
  end
end
if opts.monitor and not target then
  printError("monitor not found: " .. tostring(opts.monitor))
  return
end
if target then
  if target.setTextScale then target.setTextScale(scale) end
  opts.term = target
end

local ok, err = pcall(demo.main, opts)
local out = target or term
out.setBackgroundColor(colors.black)
out.setTextColor(colors.white)
if out.setGraphicsMode then out.setGraphicsMode(false) end
out.clear()
out.setCursorPos(1, 1)
if not ok then
  printError("cgl demo: " .. tostring(err))
end
