-- CubeOS: «рантайм» для ранних стадий загрузки (проверка пароля восстановления и, позже, загрузчик stage2).
-- Единственное место, которое знает, откуда берётся код системы. Сейчас (разработка): исходники репозитория,
-- каталог из `source` в boot.conf (по умолчанию /repo), модули Cubic компилируются на лету.
-- В установленной системе (шаг 9, D187) этот файл заменяется на вариант с готовым минифицированным Lua; интерфейс тот же.
--
--   rt = dofile("/cubeos/sys/boot/runtime.lua")
--   rt.import("cfs")                  модуль системы
--   rt.recovery_login(console, opts)  true, если пароль администратора верный (opts.root: корень данных, по умолчанию "/")
local function read(path)
  local f = fs.open(path, "r")
  if not f then return nil end
  local s = f.readAll()
  f.close()
  return s
end

local conf = read("/cubeos/sys/cfg/boot.conf") or ""
local source = conf:match("[%s{,\"']source[\"']?%s*:%s*[\"']([^\"']+)[\"']") or "/repo"

local cubic = loadfile(source .. "/src/cubic/init.lua")(source .. "/src/cubic")
local loader = cubic.new_loader({ roots = { source .. "/lib" } })

local rt = { source = source, cubic = cubic, loader = loader, import = loader.import }

function rt.recovery_login(console, opts)
  local cfs, boot = loader.import("cfs"), loader.import("boot")
  local auth_mod = loader.import("boot.auth")
  local fsys = cfs.new({})
  fsys:mount("/", cfs.host((opts and opts.root) or "/"))
  local rounds = tonumber(conf:match("[%s{,\"']rounds[\"']?%s*:%s*(%d+)"))
  local auth = auth_mod.new(fsys, { rounds = rounds })
  auth:load()
  return boot.recovery_login(console, auth) == true
end

return rt
