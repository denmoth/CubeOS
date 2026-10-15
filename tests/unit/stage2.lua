-- Загрузчик stage2 целиком: настоящие runtime, CFS, ядро, загрузка, вход (скриптовая консоль) и выключение
-- Called by tests/run.lua as: chunk(cubic, ROOT, record)
local cubic, ROOT, record = ...

local function check(name, cond, detail)
  record("stage2: " .. name, cond and true or false, tostring(detail or ""))
end

local root = ROOT .. "/build/s2root"
local function fresh()
  if fs.exists(root) then fs.delete(root) end
  fs.makeDir(root)
end

local function console(inputs)
  local c = { out = {}, inputs = inputs }
  function c:write(t) self.out[#self.out + 1] = t end
  function c:write_line(t) self.out[#self.out + 1] = t .. "\n" end
  function c:clear() self.out[#self.out + 1] = "<clear>" end
  function c:read_line(prompt) return table.remove(self.inputs, 1) end
  function c:text() return table.concat(self.out) end
  return c
end

local function read(path)
  local f = fs.open(path, "r")
  if not f then return nil end
  local s = f.readAll()
  f.close()
  return s
end

local stage2 = loadfile(ROOT .. "/sys/boot/stage2.lua")

-- 1. первая загрузка: создаём администратора, выходим, выключаем
fresh()
local power = {}
local con = console({ "root", "", "s" })
local ok, res, why = pcall(stage2, { boot_dir = ROOT .. "/sys/boot/", root = root, console = con, caps = { pixel = false, color = false },
  power = { shutdown = function() power[#power + 1] = "shutdown" end, reboot = function() power[#power + 1] = "reboot" end } })
check("first boot runs to the shutdown", ok and res == nil, ok and (tostring(res) .. " " .. tostring(why)) or res)
check("the greeter offered the first account", con:text():find("Create the first account", 1, true) ~= nil, con:text())
check("shutdown reached the power hook", power[1] == "shutdown", power[1])
local state = read(root .. "/cubeos/var/boot.state") or ""
check("boot state is clean after the cycle", state:find("pending: false", 1, true) ~= nil or state:find('"pending": false', 1, true) ~= nil, state)
local timing = read(root .. "/cubeos/var/boot.timing") or ""
check("timing of the stages is recorded", timing:find("libs", 1, true) ~= nil and timing:find("total", 1, true) ~= nil, timing)
check("users file was created", fs.exists(root .. "/cubeos/sys/cfg/users.conf"))

-- 2. безопасный режим из меню доходит до входа
fresh()
con = console({ "root", "", "s" })
ok, res = pcall(stage2, { boot_dir = ROOT .. "/sys/boot/", root = root, console = con, mode = "safe",
  power = { shutdown = function() end, reboot = function() end } })
check("safe mode boots", ok and res == nil, res)

-- 3. две незавершённые загрузки подряд: loader просит восстановление
fresh()
fs.makeDir(root .. "/cubeos")
fs.makeDir(root .. "/cubeos/var")
local f = fs.open(root .. "/cubeos/var/boot.state", "w")
f.write("{boots: 5, failures: 1, pending: true, clean: false}\n")
f.close()
con = console({})
local ok3, res3, why3 = pcall(stage2, { boot_dir = ROOT .. "/sys/boot/", root = root, console = con, power = {} })
check("two failed boots request recovery", ok3 and res3 == "recovery" and tostring(why3):find("did not finish", 1, true) ~= nil, tostring(res3) .. " " .. tostring(why3))
fs.delete(root)
