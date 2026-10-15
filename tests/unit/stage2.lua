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
local quick_shell = function(session) return function(sys, args) sys.out("hi") end end
local con = console({ "root", "", "s" })
-- язык системы с подписями экрана загрузки (пакет zz с одним boot.lang) и экран, который запоминает подписи
local function put(path, text)
  fs.makeDir(fs.getDir(path))
  local f = fs.open(path, "w") f.write(text) f.close()
end
put(root .. "/cubeos/sys/cfg/locale.conf", '{lang: "zz"}')
put(root .. "/cubeos/share/lang/zz/boot.lang", 'msgid "Loading the kernel"\nmsgstr "ZZ kernel"\n')
local labels = {}
local rec = {}
function rec:open() end
function rec:progress(f, text) if text then labels[#labels + 1] = text end end
function rec:message() end
function rec:tick() return false end
function rec:done() end
function rec:close() end
function rec:error() end
local ok, res, why = pcall(stage2, { shell = quick_shell, boot_dir = ROOT .. "/sys/boot/", root = root, console = con, caps = { pixel = false, color = false }, splash = rec,
  power = { shutdown = function() power[#power + 1] = "shutdown" end, reboot = function() power[#power + 1] = "reboot" end } })
check("first boot runs to the shutdown", ok and res == nil, ok and (tostring(res) .. " " .. tostring(why)) or res)
check("the greeter offered the first account", con:text():find("Create the first account", 1, true) ~= nil, con:text())
check("shutdown reached the power hook", power[1] == "shutdown", power[1])
check("boot captions come in the system language from boot.lang", table.concat(labels, "|"):find("ZZ kernel", 1, true) ~= nil, table.concat(labels, "|"))
check("captions without a translation stay English", table.concat(labels, "|"):find("Loading libraries", 1, true) ~= nil, table.concat(labels, "|"))
local state = read(root .. "/cubeos/var/boot.state") or ""
check("boot state is clean after the cycle", state:find("pending: false", 1, true) ~= nil or state:find('"pending": false', 1, true) ~= nil, state)
local timing = read(root .. "/cubeos/var/boot.timing") or ""
check("timing of the stages is recorded", timing:find("libs", 1, true) ~= nil and timing:find("total", 1, true) ~= nil, timing)
check("users file was created", fs.exists(root .. "/cubeos/sys/cfg/users.conf"))
local blog = read(root .. "/cubeos/var/log/boot.log") or ""
check("boot.log is written from the start", blog:find("stage 2 started", 1, true) ~= nil, blog)
check("boot.log has the stages with timings", blog:find("Loading the kernel:", 1, true) ~= nil and blog:find(" modules in ", 1, true) ~= nil, blog)
check("boot.log says how the boot ended", blog:find("boot finished in", 1, true) ~= nil and blog:find("kernel stopped normally", 1, true) ~= nil, blog)
check("boot.log lines have a time, a level and the source", blog:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ info boot ") ~= nil, blog:sub(1, 80))

-- 2. безопасный режим из меню доходит до входа
fresh()
con = console({ "root", "", "s" })
ok, res = pcall(stage2, { shell = quick_shell, boot_dir = ROOT .. "/sys/boot/", root = root, console = con, mode = "safe",
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

-- 6. вся цепочка с настоящими манифестами служб и их настройками (sys/): службы стартуют, журнал пишется, выключение штатное
local root3 = ROOT .. "/build/s2root3"
if fs.exists(root3) then fs.delete(root3) end
fs.makeDir(root3)
for _, dir in ipairs({ "/cubeos", "/cubeos/sys", "/cubeos/sys/services", "/cubeos/sys/cfg" }) do fs.makeDir(root3 .. dir) end
for _, name in ipairs(fs.list(ROOT .. "/sys/services")) do fs.copy(ROOT .. "/sys/services/" .. name, root3 .. "/cubeos/sys/services/" .. name) end
for _, name in ipairs(fs.list(ROOT .. "/sys/cfg")) do fs.copy(ROOT .. "/sys/cfg/" .. name, root3 .. "/cubeos/sys/cfg/" .. name) end
local power3 = {}
local con3 = console({ "root", "", "s" })
local ok6, res6, why6 = pcall(stage2, { shell = quick_shell, boot_dir = ROOT .. "/sys/boot/", root = root3, console = con3,
  power = { shutdown = function() power3[#power3 + 1] = "shutdown" end, reboot = function() end } })
check("the full chain with the real service manifests runs to shutdown", ok6 and res6 == nil and power3[1] == "shutdown", tostring(res6) .. " " .. tostring(why6))
local syslog = read(root3 .. "/cubeos/var/log/system.log") or ""
check("logd wrote the system log", syslog:find("log service started", 1, true) ~= nil, syslog)
check("devd mounted the hardware view and logged nothing bad", syslog:find("message handler failed", 1, true) == nil, syslog)
check("no crash reports after a clean run", not fs.exists(root3 .. "/cubeos/var/crash") or #fs.list(root3 .. "/cubeos/var/crash") == 0)
fs.delete(root3)
