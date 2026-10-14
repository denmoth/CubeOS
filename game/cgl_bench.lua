-- Замеры скорости CGL в настоящем CC. На компьютере: /repo/game/cgl_bench.lua [graphics|teletext]
-- Меряет рисование в память (поверхность) и вывод на экран по отдельности. Итог на экране и в /repo/build/cgl-bench.txt.
local ROOT = "/repo"
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
local loader = cubic.new_loader({ roots = { ROOT .. "/lib" } })
local cgl = loader.import("cgl")
local fx = loader.import("cgl.fx")
local g3d = loader.import("cgl.g3d")
local fontlib = loader.import("font")

-- аргументы те же, что у cgl_demo.lua (см. game/cgl_args.lua)
local opts, target, scale = dofile(ROOT .. "/game/cgl_args.lua")({ ... })
if not opts then
  printError(target)
  return
end
local out = target or term

local screen = cgl.open(opts)
local s = screen.surface
local w, h = screen.w, screen.h
local pal = screen.palette
local fnt = fontlib.default(ROOT .. "/assets")
local results = {}

local function clock() return os.epoch("utc") / 1000 end

-- повторяет fn, пока не пройдёт 2 секунды (с уступкой управления), возвращает вызовов в секунду
local function bench(name, fn)
  local calls, start = 0, clock()
  local last_yield = start
  while clock() - start < 2 do
    fn(calls)
    calls = calls + 1
    if clock() - last_yield > 1 then
      os.queueEvent("cgl_bench"); os.pullEvent("cgl_bench")
      last_yield = clock()
    end
  end
  local rate = calls / (clock() - start)
  results[#results + 1] = string.format("%-34s %8.1f /s  (%.2f ms)", name, rate, 1000 / rate)
end

local ramp = pal:ramp({ { 0, 0, 0 }, { 255, 0, 0 }, { 255, 255, 255 } }, 24)
local small = cgl.surface.new(math.ceil(w / 3), math.ceil(h / 3), 0)
local plasma = fx.Plasma(small.w, small.h, ramp)
local torus = g3d.torus(1, 0.4, 14, 8)

bench("fill_rect весь экран", function(i) s:fill_rect(0, 0, w, h, i % 200) end)
bench("fill_gradient вертикальный", function() s:fill_gradient(0, 0, w, h, ramp, "v") end)
bench("circle залитый r=30", function(i) s:circle(math.floor(w / 2), math.floor(h / 2), 30, i % 200, true) end)
bench("line 100 штук", function(i) for k = 1, 100 do s:line(0, k, w - 1, h - 1 - k, k % 200) end end)
bench("text 40 символов", function() s:text(fnt, 2, 2, "The quick brown fox jumps over the lazy dog", 15) end)
bench("blit малой поверхности x3", function() s:blit(small, 0, 0, { scale = 3 }) end)
bench("plasma (малый размер)", function(i) plasma:draw(small, i * 0.05) end)
bench("3D тор flat", function(i) g3d.render(s, torus, { mode = "flat", ramp = ramp, rx = i * 0.1, z = 3.6, fov = h }) end)

-- вывод на экран
s:clear(0)
bench("present: ничего не менялось", function() screen:present() end)
bench("present: изменилась точка", function(i) s:set(i % w, 3, i % 200); screen:present() end)
bench("present: изменился блок 40x30", function(i) s:fill_rect(10, 10, 40, 30, i % 200); screen:present() end)
bench("present: весь экран (градиент)", function(i)
  s:fill_gradient(0, 0, w, h, ramp, "v"); s:set(0, 0, i % 200); screen:invalidate()
  screen:present()
end)
bench("set_colors 48 цветов", function(i)
  local list = {}
  for k = 1, 48 do list[k] = { 200 + k, i % 255, k * 5, 100 } end
  screen:set_colors(list)
end)

local st = screen.display.stats
results[#results + 1] = string.format("present всего: кадров %d, скан %d мс, отправка %d мс, вызовов %d", st.frames, st.scan_ms, st.send_ms, st.calls)
screen:close()
term.clear(); term.setCursorPos(1, 1)
if target then out.clear() end
print("CGL bench: " .. screen.kind .. " " .. w .. "x" .. h .. (target and (" (monitor, scale " .. tostring(scale) .. ")") or ""))
for _, line in ipairs(results) do print(line) end
local f = fs.open(ROOT .. "/build/cgl-bench-" .. screen.kind .. (target and "-monitor" or "") .. ".txt", "w")
if f then
  f.writeLine("CGL bench: " .. screen.kind .. " " .. w .. "x" .. h .. (target and (" (monitor, scale " .. tostring(scale) .. ")") or ""))
  for _, line in ipairs(results) do f.writeLine(line) end
  f.close()
end
