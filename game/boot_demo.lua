-- Демонстрация загрузки CubeOS в настоящем CC: журнал загрузки, службы, вход, сессия, выключение.
-- На компьютере: /repo/game/boot_demo.lua   (Ctrl при старте: режим восстановления; Ctrl+T: выход)
-- Данные демо лежат в /cubeos-demo (удалить папку = начать заново). Файлы самого репозитория не меняются.
local ROOT = "/repo"
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
local loader = cubic.new_loader({ roots = { ROOT .. "/lib" } })
local cfs = loader.import("cfs")
local boot = loader.import("boot")
local console_mod = loader.import("boot.console")
local cckernel = loader.import("kernel.cc")

local scripted = rawget(_G, "CUBEOS_DEMO_INPUTS")      -- для автоматической проверки: готовые ответы вместо клавиатуры
local console = scripted and console_mod.ScriptedConsole(scripted) or console_mod.TermConsole()

-- Ctrl при старте: ждём секунду клавишу Ctrl
local ctrl = false
if not scripted then
  term.clear()
  term.setCursorPos(1, 1)
  print("CubeOS demo boot. Hold Ctrl now for recovery...")
  local timer = os.startTimer(1)
  while true do
    local ev, a = os.pullEventRaw()
    if ev == "timer" and a == timer then break end
    if ev == "key" and (a == keys.leftCtrl or a == keys.rightCtrl) then ctrl = true; break end
  end
end

-- файловая система: настоящий диск в /cubeos-demo под корнем CFS, tmp в памяти, стандартные права
if not fs.exists("/cubeos-demo") then fs.makeDir("/cubeos-demo") end
local fsys = cfs.new({})
fsys:mount("/", cfs.host("/cubeos-demo"))
fsys:mount("/cubeos/tmp", cfs.tmp(65536))
cfs.install_defaults(fsys)
for _, dir in ipairs({ "/cubeos/sys/services", "/cubeos/sys/cfg", "/cubeos/sys/sec", "/cubeos/var", "/cubeos/shared", "/cubeos/users" }) do
  fsys:mkdir(nil, dir, { parents = true })
end
if not fsys:exists(nil, "/cubeos/sys/services/clockd.conf") then
  fsys:write_file(nil, "/cubeos/sys/services/clockd.conf", "{name: 'clockd', module: 'demo.clockd'}\n")
  fsys:write_file(nil, "/cubeos/sys/services/pingd.conf", "{name: 'pingd', module: 'demo.pingd', requires: ['clockd']}\n")
  fsys:write_file(nil, "/cubeos/sys/services/slowd.conf", "{name: 'slowd', module: 'demo.slowd', safe: false}\n")
  fsys:write_file(nil, "/cubeos/sys/cfg/boot.conf", "{rounds: 200, title: 'CubeOS demo'}\n")
end

-- службы демо: готовые программы вместо файлов
local function service(name, delay)
  return { main = function(sys, args)
    sys.sleep(delay)
    sys.register(name)
    while true do sys.sleep(5) end
  end }
end
local modules = { ["demo.clockd"] = service("clockd", 0.5), ["demo.pingd"] = service("pingd", 0.5), ["demo.slowd"] = service("slowd", 1) }

local function shell_for(session)
  return function(sys, args)
    sys.out("Signed in as " .. session.display .. " (" .. session.profile .. ")\n")
    local view = sys.view()
    view:write("$docs/hello.txt", "created by the demo shell at " .. sys.now())
    sys.out("Wrote $docs/hello.txt; files in $docs: " .. #view:list("$docs") .. "\n")
    sys.out("Press any key to sign out.\n")
    sys.wait_event({ "key" })
  end
end

local b = boot.new({
  fsys = fsys,
  console = console,
  ctrl = ctrl,
  import = function(path) return modules[path] end,
  kernel = { rt = cubic.rt, cubic = cubic, pull = cckernel.pull },
  shell = shell_for,
  power = { shutdown = function() print("(power off)") end, reboot = function() print("(restart)") end },
})

local system = b:start()
if system.mode == "recovery" then
  console:write_line("Recovery: " .. tostring(system.reason))
  if boot.recovery_login(console, system.auth) then
    console:write_line("Recovery shell (type exit to return).")
    if shell and shell.run then shell.run("shell") end
  end
  return
end

local ok, err = pcall(function() system.kernel:run() end)
console:write_line(ok and "kernel stopped" or ("kernel error: " .. tostring(err)))
if scripted then
  local f = fs.open("/cubeos-demo/console.txt", "w")
  f.write(console:text())
  f.close()
end
