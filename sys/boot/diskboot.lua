-- CubeOS: загрузка с дискет (D224). Чистый Lua, вызывается из stage1 как chunk(arg).
-- arg: conf (текст boot.conf), opt(conf, key, default), gate(info) -> true, если пароль администратора верный, notes (список строк
-- для журнала загрузки), hash(text) -> sha256 hex (для тестов; по умолчанию из runtime.lua).
-- Результат: путь к startup дискеты, которую надо запустить вместо системы, или nil (обычная загрузка).
--
-- 1. Загрузка с дискет самого ROM CC (настройка shell.allow_disk_startup) подменяет наш /startup.lua и обходит пароль, поэтому она
--    выключается при каждой загрузке (boot.conf: rom_disk_startup: true оставляет её как есть).
-- 2. Своя загрузка (boot.conf: disk_boot): "off" (по умолчанию) ничего не запускает; "trusted" только доверенные дискеты;
--    "password" доверенные сразу, остальные после пароля администратора; "all" любая дискета со startup.
--    Доверенные дискеты: /cubeos/sys/cfg/trusted_disks.conf, строки "<номер дискеты> <sha256 файла startup> [метка]"
--    (команда disk trust). Изменённый startup на доверенной дискете уже не доверенный: хэш не сойдётся.
local arg = ... or {}
local conf, opt, notes = arg.conf, arg.opt, arg.notes or {}
local TRUSTED = "/cubeos/sys/cfg/trusted_disks.conf"

if opt(conf, "rom_disk_startup", false) ~= true and settings and settings.get("shell.allow_disk_startup") ~= false then
  settings.set("shell.allow_disk_startup", false)
  pcall(settings.save)
  notes[#notes + 1] = "CraftOS disk startup was enabled; turned it off (rom_disk_startup in boot.conf)"
end

local mode = tostring(opt(conf, "disk_boot", "off"))
if mode == "off" or not peripheral or not disk then return nil end

local function read(path)
  local f = fs.open(path, "r")
  if not f then return nil end
  local s = f.readAll()
  f.close()
  return s
end

-- первая дискета со startup.lua или startup
local found
for _, side in ipairs(peripheral.getNames()) do
  if disk.isPresent(side) and disk.hasData(side) then
    local root = disk.getMountPath(side)
    for _, n in ipairs({ "startup.lua", "startup" }) do
      local p = "/" .. fs.combine(root, n)
      if fs.exists(p) and not fs.isDir(p) then
        found = { side = side, path = p, id = disk.getID(side), label = disk.getLabel(side) or root }
        break
      end
    end
  end
  if found then break end
end
if not found then return nil end
local name = "disk " .. tostring(found.id) .. " (" .. tostring(found.label) .. ")"

if mode == "all" then
  notes[#notes + 1] = "booting from " .. name .. " (disk_boot: all)"
  return found.path
end

local function hash(text)
  if arg.hash then return arg.hash(text) end
  local f = loadfile("/cubeos/sys/boot/runtime.lua")
  if not f then return nil end
  local ok, rt = pcall(f)
  if not ok or type(rt) ~= "table" then return nil end
  local sha = rt.import("sha256")
  return sha.to_hex(sha.digest(text))
end

local trusted = false
local list = read(TRUSTED)
if list and found.id then
  local want
  for line in list:gmatch("[^\n]+") do
    local id, h = line:match("^%s*(%d+)%s+(%x+)")
    if id and tonumber(id) == found.id then want = h:lower() end
  end
  if want then
    local got = hash(read(found.path) or "")
    trusted = got ~= nil and got:lower() == want
    if not trusted then notes[#notes + 1] = name .. " is trusted, but its startup file changed; not trusted any more" end
  end
end

if trusted then
  notes[#notes + 1] = "booting from trusted " .. name
  return found.path
end
if mode == "password" and arg.gate then
  if arg.gate({ disk = name }) then
    notes[#notes + 1] = "booting from " .. name .. " after the administrator password"
    return found.path
  end
  notes[#notes + 1] = "boot from " .. name .. " refused (no administrator password)"
  return nil
end
notes[#notes + 1] = "ignored " .. name .. ": not trusted (disk_boot: " .. mode .. ")"
return nil
