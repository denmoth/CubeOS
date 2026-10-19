-- CubeOS: «рантайм» для ранних стадий загрузки (проверка пароля восстановления и, позже, загрузчик stage2).
-- Единственное место, которое знает, откуда берётся код системы. Сейчас (разработка): исходники репозитория,
-- каталог из `source` в boot.conf (по умолчанию /repo), модули Cubic компилируются на лету.
-- В установленной системе (есть /cubeos/var/stew/boot.idx) код берётся готовым Lua из пакетов через pkgload.lua; интерфейс тот же.
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

-- Установленная система (docs/packages, шаг 3): stew пишет индекс пакетов, модули берутся готовым Lua из пакетов (сжатых или
-- распакованных), компилятора может не быть. Без индекса (разработка): исходники из `source`, Cubic компилируется на лету.
-- dev: true в boot.conf заставляет грузиться из исходников даже при установленных пакетах.
local IDX = "/cubeos/var/stew/boot.idx"
local rt
if fs.exists(IDX) and not conf:match("[%s{,\"']dev[\"']?%s*:%s*true") then
  local idx = dofile(IDX)
  local loader = dofile("/cubeos/sys/boot/pkgload.lua").new(idx)
  local cubic = idx.cubic and loadfile(idx.cubic .. "/init.lua")(idx.cubic) or nil
  rt = { source = idx.share or "/cubeos/share", cubic = cubic or { rt = loader.rt }, loader = loader, import = loader.import,
    installed = true, map_error = loader.map_error, has_compiler = cubic ~= nil }
else
  local cubic = loadfile(source .. "/src/cubic/init.lua")(source .. "/src/cubic")
  local loader = cubic.new_loader({ roots = { source .. "/lib" } })
  rt = { source = source, cubic = cubic, loader = loader, import = loader.import, has_compiler = true,
    map_error = function(msg) return msg end }
end
local loader = rt.loader

-- порядок модулей: зависимости раньше зависимых. Что не нашлось, пропускается (import сообщит об ошибке сам)
function rt.plan(names)
  local order, seen = {}, {}
  local function visit(name)
    if seen[name] then return end
    seen[name] = true
    if rt.installed then
      if not pcall(loader.resolve, name) then return end
      for _, dep in ipairs(loader.deps(name)) do visit(dep) end
    else
      local ok, path = pcall(loader.resolve, name)
      if not ok then return end
      if path:sub(-4) == ".cub" then
        local src = read(path) or ""
        for dep in ("\n" .. src):gmatch("\n%s*import%s+([%w_%.]+)") do visit(dep) end
      end
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
