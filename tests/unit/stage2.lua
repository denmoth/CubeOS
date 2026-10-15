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

-- 4. сбой до начала загрузки: отчёт, экран ошибки с кодом, возврат в восстановление (без перезагрузки: считать неудачи нечем)
local function fake_splash(fail_open)
  local sp = { shown = {} }
  function sp:open() if fail_open then error("splash exploded", 0) end end
  function sp:progress() end
  function sp:message() end
  function sp:tick() return false end
  function sp:done() end
  function sp:close() end
  function sp:error(text) self.shown[#self.shown + 1] = text end
  return sp
end

local root2 = ROOT .. "/build/s2root2"
if fs.exists(root2) then fs.delete(root2) end
fs.makeDir(root2)
local sp = fake_splash(true)
local ok4, res4, why4 = pcall(stage2, { boot_dir = ROOT .. "/sys/boot/", root = root2, splash = sp, crash_delay = 0, console = console({}) })
check("a failure before the boot starts goes to recovery", ok4 and res4 == "recovery" and tostring(why4):find("splash exploded", 1, true) ~= nil, tostring(res4) .. " " .. tostring(why4))
check("the error screen shows the reason code", sp.shown[1] and sp.shown[1]:find("Reason code E-", 1, true) ~= nil, sp.shown[1])
check("and offers recovery without a restart countdown", sp.shown[1] and sp.shown[1]:find("Restarting in", 1, true) == nil, sp.shown[1])
local reports = fs.exists(root2 .. "/cubeos/var/crash") and fs.list(root2 .. "/cubeos/var/crash") or {}
check("a crash report was written", #reports == 1 and reports[1]:find("boot", 1, true) ~= nil, #reports)
local body = reports[1] and read(root2 .. "/cubeos/var/crash/" .. reports[1]) or ""
check("the report has the error", body:find("splash exploded", 1, true) ~= nil, body)

-- 5. сбой после начала загрузки: перезагрузка (счётчик неудач в boot.state доведёт до безопасного режима и восстановления)
fs.delete(root2)
fs.makeDir(root2)
local sp2 = fake_splash(false)
local ok5, res5 = pcall(stage2, { boot_dir = ROOT .. "/sys/boot/", root = root2, splash = sp2, crash_delay = 0, console = console({}),
  hooks = { after_start = function() error("boom after start", 0) end } })
check("a failure after the boot starts asks for a restart", ok5 and res5 == "reboot", tostring(res5))
check("with a countdown on screen", sp2.shown[1] and sp2.shown[1]:find("Restarting in 0 s", 1, true) ~= nil, sp2.shown[1])
local st = read(root2 .. "/cubeos/var/boot.state") or ""
check("the unfinished boot stays marked", st:find("pending: true", 1, true) ~= nil or st:find('"pending": true', 1, true) ~= nil, st)
fs.delete(root2)
