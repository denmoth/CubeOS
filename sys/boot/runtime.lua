-- CubeOS: «рантайм» для ранних стадий загрузки (проверка пароля восстановления и, позже, загрузчик stage2).
-- Единственное место, которое знает, откуда берётся код системы. Сейчас (разработка): исходники репозитория,
-- каталог из `source` в boot.conf (по умолчанию /repo), модули Cubic компилируются на лету.
-- В установленной системе (шаг 9, D187) этот файл заменяется на вариант с готовым минифицированным Lua; интерфейс тот же.
--
--   rt = dofile("/cubeos/sys/boot/runtime.lua")
--   rt.import("cfs")                  модуль системы
--   rt.plan(names)                    порядок загрузки модулей: сначала зависимости (по строкам import в исходниках)
--   rt.preload(names, on_step)        подгружает модули по одному, между ними отдаёт управление CC (иначе «Too long without
--                                     yielding»); on_step(имя, i, n) после каждого
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

-- порядок модулей: зависимости раньше зависимых. Что не нашлось, пропускается (import сообщит об ошибке сам)
function rt.plan(names)
  local order, seen = {}, {}
  local function visit(name)
    if seen[name] then return end
    seen[name] = true
    local ok, path = pcall(loader.resolve, name)
    if not ok then return end
    if path:sub(-4) == ".cub" then
      local src = read(path) or ""
      for dep in ("\n" .. src):gmatch("\n%s*import%s+([%w_%.]+)") do visit(dep) end
    end
    order[#order + 1] = name
  end
  for _, name in ipairs(names) do visit(name) end
  return order
end

local function yield()
  os.queueEvent("cubeos_yield")
  repeat local e = os.pullEventRaw() until e == "cubeos_yield"
end
rt.yield = yield

function rt.preload(names, on_step)
  local order = rt.plan(names)
  for i, name in ipairs(order) do
    loader.import(name)
    if on_step then on_step(name, i, #order) end
    yield()
  end
  return order
end

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
