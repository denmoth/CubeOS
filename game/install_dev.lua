-- Ставит цепочку загрузки CubeOS на этот компьютер из /repo/sys (для проверки в игре): /startup.lua, /cubeos/sys/boot/,
-- манифесты служб /cubeos/sys/services/ и настройки по умолчанию /cubeos/sys/cfg/ (существующие не перезаписываются).
--   /repo/game/install_dev.lua           установить (перезагрузка: загрузка CubeOS, F2 при старте: меню, Ctrl: восстановление)
--   /repo/game/install_dev.lua remove    убрать /startup.lua и /cubeos/sys/boot (данные в /cubeos остаются)
-- Если у компьютера уже есть /startup.lua, он сохраняется как /startup.lua.bak (при удалении возвращается).
local ROOT = "/repo"
local mode = ...

local function copy(from, to)
  if fs.exists(to) then fs.delete(to) end
  fs.copy(from, to)
end

if mode == "remove" then
  if fs.exists("/startup.lua") then fs.delete("/startup.lua") end
  if fs.exists("/startup.lua.bak") then fs.move("/startup.lua.bak", "/startup.lua") end
  if fs.exists("/cubeos/sys/boot") then fs.delete("/cubeos/sys/boot") end
  print("CubeOS boot chain removed (data in /cubeos is kept).")
  return
end

if fs.exists("/startup.lua") and not fs.exists("/startup.lua.bak") then fs.move("/startup.lua", "/startup.lua.bak") end
copy(ROOT .. "/sys/startup.lua", "/startup.lua")
fs.makeDir("/cubeos/sys/boot")
fs.makeDir("/cubeos/sys/cfg")
for _, name in ipairs(fs.list(ROOT .. "/sys/boot")) do copy(ROOT .. "/sys/boot/" .. name, "/cubeos/sys/boot/" .. name) end
-- манифесты служб (всегда свежие) и настройки по умолчанию (только если их ещё нет)
fs.makeDir("/cubeos/sys/services")
for _, name in ipairs(fs.list(ROOT .. "/sys/services")) do copy(ROOT .. "/sys/services/" .. name, "/cubeos/sys/services/" .. name) end
for _, name in ipairs(fs.list(ROOT .. "/sys/cfg")) do
  if not fs.exists("/cubeos/sys/cfg/" .. name) then fs.copy(ROOT .. "/sys/cfg/" .. name, "/cubeos/sys/cfg/" .. name) end
end
if not fs.exists("/cubeos/sys/cfg/boot.conf") then
  local f = fs.open("/cubeos/sys/cfg/boot.conf", "w")
  f.write("{\n  source: '/repo',\n  rounds: 1000,\n}\n")
  f.close()
end
print("CubeOS boot chain installed. Restart the computer (Ctrl+R) to boot CubeOS.")
