-- Демонстрация Cube Graphics Library в настоящем CC. На компьютере: /repo/game/cgl_demo.lua [graphics|teletext] [monitor[=имя]] [scale=число]
-- Стрелки или пробел: следующая сцена, D: дизеринг (телетекст), M: сменить вывод пиксели/телетекст, Q или Ctrl+T: выход, мышь или касание: частицы.
-- С CC: Graphics рисует пикселями (306x171 на 51x19 клеток); без него идёт телетекст (102x57).
-- Монитор: monitor берёт первый найденный монитор (в том числе по проводному модему), monitor=monitor_0 конкретный.
-- scale это масштаб текста монитора; по умолчанию подбирается сам (51 клетка в ширину, как у терминала компьютера).
-- Средние кадры в секунду по сценам записываются в /repo/build/cgl-demo-term.txt или cgl-demo-monitor.txt.
local ROOT = "/repo"
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
local loader = cubic.new_loader({ roots = { ROOT .. "/lib", ROOT .. "/examples" } })
local demo = loader.import("cgl_demo")

local opts, target, scale = dofile(ROOT .. "/game/cgl_args.lua")({ ... })
if not opts then
  printError(target)
  return
end
opts.log_path = ROOT .. "/build/cgl-demo-" .. (target and "monitor" or "term") .. ".txt"

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
