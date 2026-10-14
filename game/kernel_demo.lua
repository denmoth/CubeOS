-- Демонстрация ядра в настоящем CC: несколько процессов, фокус, события, вытеснение, «не отвечает».
-- На компьютере: /repo/game/kernel_demo.lua   (выход: Ctrl+T)
-- Клавиша Tab переключает активную программу, любая другая клавиша идёт активной.
local ROOT = "/repo"
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
local loader = cubic.new_loader({ roots = { ROOT .. "/lib" } })
local kernel = loader.import("kernel")
local cckernel = loader.import("kernel.cc")

term.clear()
term.setCursorPos(1, 1)
print("CubeOS kernel demo (Tab: switch focus, Ctrl+T: quit)")

local function line(y, text)
  local w = term.getSize()
  term.setCursorPos(1, y)
  term.clearLine()
  term.write(text:sub(1, w))
end

local hung_report = nil
local k = kernel.new({
  rt = cubic.rt,
  cubic = cubic,
  pull = cckernel.pull,
  hung_ms = 4000,
  on_hung = function(proc)
    hung_report = proc.name
    line(12, "NOT RESPONDING: " .. proc.name .. "  (press K to close it, W to wait, S to snooze)")
  end,
})

-- 1. часы: обновляются каждую секунду, пока работают другие
k:spawn_source([=[
n = 0
while true:
    n += 1
    sys.out_line(3, "clock process: tick " .. n)
    sys.sleep(1)
]=], "clock", {}, { name = "clock" })

-- 2. вычисление без единого системного вызова: ядро само уступает управление (код с автоотдачей)
k:spawn_source([=[
total = 0
for i in range[1, 100000000]:
    total += i
    if i % 400000 == 0:
        sys.out_line(4, "heavy loop: " .. i // 1000000 .. "M iterations, sum " .. total)
]=], "heavy", {}, { name = "heavy" })

-- 3. две программы с интерфейсом: клавиши получает только активная
for index, label in ipairs({ "editor", "game" }) do
  k:spawn_source([=[
count = 0
while true:
    name, key = sys.wait_event(["key", "char"])
    count += 1
    sys.out_line(args[2], args[1] .. " got " .. name .. " " .. tostring(key) .. " (" .. count .. ")")
]=], label, { label, 5 + index }, { name = label, ui = true })
end

-- 4. «глухая» программа: крутится и не читает ввод. Ядро заметит и спросит
k:spawn_source([=[
x = 0
while true:
    x += 1
]=], "deaf", {}, { name = "deaf", ui = true })

-- sys.out_line(строка_экрана, текст) для демо: рисует на экране. Добавляем в sys на лету, ядро о нём ничего не знает.
local base_out = k.sys
k.sys.out_line = function(y, text) line(y, text) end

local order = { "editor", "game" }
local lines = { editor = 6, game = 7, deaf = 8 }

local function status()
  line(10, "focus: " .. tostring(k.focus_pid and k:proc(k.focus_pid) and k:proc(k.focus_pid).name))
  local names = {}
  for _, p in ipairs(k:ps()) do names[#names + 1] = p.name .. (p.hung and "!" or "") .. ":" .. math.floor(p.cpu_ms) .. "ms" end
  line(11, table.concat(names, " "))
end

-- ядро с обработкой наших клавиш поверх обычной подачи событий
local feed = k.feed
k.feed = function(self, name, ...)
  local args = { ... }
  if name == "key" then
    local code = args[1]
    if code == keys.tab then
      self:focus_next()
      return
    elseif hung_report and (code == keys.k or code == keys.w or code == keys.s) then
      for _, p in ipairs(self:ps()) do
        if p.hung then
          if code == keys.k then self:answer_hung(p.pid, "kill")
          elseif code == keys.w then self:answer_hung(p.pid, "wait")
          else self:answer_hung(p.pid, "snooze", 20000) end
        end
      end
      hung_report = nil
      line(12, "")
      return
    end
  end
  return feed(self, name, ...)
end

local ok, err = pcall(function()
  local last = 0
  k.pull = function(timeout)
    status()
    return cckernel.pull(math.min(timeout, 250))
  end
  k:run()
end)
term.setCursorPos(1, 14)
print(ok and "kernel stopped" or ("kernel error: " .. tostring(err)))
