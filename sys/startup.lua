-- CubeOS: единственная точка входа (D204). Кладётся в корень компьютера как /startup.lua.
-- Только находит и запускает этап 1; если его нет или он упал, открывает восстановление с паролем, а не голый CraftOS.
local pe, S = os.pullEvent, "/cubeos/sys/boot/"
os.pullEvent = os.pullEventRaw   -- Ctrl+T не прерывает загрузку и восстановление
local function run(f, a) f = loadfile(S .. f) if not f then return false end return pcall(f, a) end
local ok, r = run("stage1.lua")
if not ok then ok, r = run("rescue.lua", { reason = tostring(r or "stage1.lua is missing") }) end
os.pullEvent = pe
if not ok and fs.exists("/cubeos/sys/cfg/users.conf") then   -- система есть, но восстановить нечем: заперто
  print("CubeOS: system files are damaged and recovery is unavailable.")
  sleep(5) os.shutdown()
elseif not ok then print("CubeOS is not installed; starting CraftOS.") return
elseif r == "craftos" then return end
if r == "reboot" then os.reboot() end
os.shutdown()
