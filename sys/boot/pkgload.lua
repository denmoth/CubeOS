-- CubeOS: загрузчик модулей установленной системы (docs/packages, шаг 3). Компилятора нет: в пакетах готовый Lua.
-- Индекс пишет stew при каждой установке (/cubeos/var/stew/boot.idx, обычная таблица Lua, читается без json5):
--   { rt = "<путь к rt.lua>", share = "/cubeos/share", cubic = "<папка компилятора или nil>", maps = "<папка карт строк>",
--     packages = { [id] = { dir = "/cubeos/pkg/<id>" } или { packed = "/cubeos/pkg/<id>.cpk" } },
--     modules = { ["cfs.core"] = { "cubeos.cfs", "lib/cfs/core.lua" }, ... } }
-- Модуль Cubic вызывается как chunk(rt, import); модуль на Lua получает import в своём окружении поверх _G.
-- Сжатые пакеты читает модуль cpk (пакет cubeos.cpk и всё, что ему нужно, всегда распакованы).
--
--   L = dofile("/cubeos/sys/boot/pkgload.lua").new(idx)
--   L.import("cfs")   L.import_for(pkg, dir)   L.resolve(name)   L.deps(name)   L.map_error(msg)   L.read(pkg, path)
local P = {}

local function read_plain(path)
  local f = fs.open(path, "rb")
  if not f then return nil end
  local s = f.readAll()
  f.close()
  return s
end

local function dirname(p) return p:match("^(.*)/[^/]*$") or "" end

local function normalize(p)
  local parts = {}
  for seg in p:gmatch("[^/]+") do
    if seg == ".." then
      if #parts > 0 then parts[#parts] = nil end
    elseif seg ~= "." then
      parts[#parts + 1] = seg
    end
  end
  return table.concat(parts, "/")
end

-- карта строк "cubic-map 1 файл\n1:1 5:3 ..." -> таблица строк и имя исходника
local function parse_map(text)
  local file, body = text:match("^cubic%-map 1 ([^\n]*)\n(.*)$")
  if not file then return nil end
  local starts = {}
  for a, b in body:gmatch("(%d+):(%d+)") do starts[#starts + 1] = { tonumber(a), tonumber(b) } end
  return starts, file
end

local function map_line(starts, n)
  local found
  for _, st in ipairs(starts) do
    if st[1] <= n then found = st[2] else break end
  end
  return found
end

function P.new(idx)
  local rtlib = dofile(idx.rt)
  local cache, loading, chunks, maps, archives = {}, {}, {}, {}, {}
  local L = { rt = rtlib, idx = idx, cache = cache }
  local cpk

  function L.read(pkgid, path)
    local p = idx.packages[pkgid]
    if not p then return nil end
    if p.packed then
      if not cpk then cpk = L.import("cpk") end
      local a = archives[pkgid]
      if not a then
        a = cpk.open_file(p.packed)
        archives[pkgid] = a
      end
      return a:read(path)
    end
    return read_plain(p.dir .. "/" .. path)
  end

  -- после переустановки пакета старый архив больше не читается
  function L.forget(pkgid) archives[pkgid] = nil end

  local function find_in(pkgid, base)
    for _, cand in ipairs({ base .. ".lua", base .. "/init.lua", base }) do
      local p = idx.packages[pkgid]
      if p and p.packed then
        if not cpk then cpk = L.import("cpk") end
        local a = archives[pkgid] or cpk.open_file(p.packed)
        archives[pkgid] = a
        if a:exists(cand) then return cand end
      elseif p and fs.exists(p.dir .. "/" .. cand) and not fs.isDir(p.dir .. "/" .. cand) then
        return cand
      end
    end
    return nil
  end

  function L.resolve(spec, pkgid, base)
    if spec:sub(1, 2) == "./" or spec:sub(1, 3) == "../" then
      if not pkgid then error("relative import '" .. spec .. "' outside a package", 0) end
      local path = find_in(pkgid, normalize((base ~= "" and (base .. "/") or "") .. spec))
      if not path then error("module '" .. spec .. "' not found in " .. pkgid, 0) end
      return pkgid, path
    end
    local m = idx.modules[spec]
    if not m then error("module '" .. spec .. "' is not installed (no package provides it)", 0) end
    return m[1], m[2]
  end

  function L.map_error(msg)
    if type(msg) ~= "string" then return msg end
    return (msg:gsub("([%w_%-%./]+%.lua):(%d+):", function(chunk, n)
      local e = chunks[chunk]
      if not e then return nil end
      local m = maps[chunk]
      if m == nil then
        local text = L.read(e[1], e[2] .. ".map")
        -- system packages keep their maps apart (stew maps downloads them): /cubeos/var/stew/maps/<id>.cpk
        if not text and idx.maps then
          local mp = idx.maps .. "/" .. e[1] .. ".cpk"
          if fs.exists(mp) then
            if not cpk then cpk = L.import("cpk") end
            local okm, a = pcall(cpk.open_file, mp)
            if okm then text = a:read(e[2] .. ".map") end
          end
        end
        local starts, file = nil, nil
        if text then starts, file = parse_map(text) end
        m = starts and { starts = starts, file = file } or false
        maps[chunk] = m
      end
      if not m then return nil end
      local line = map_line(m.starts, tonumber(n))
      if line then return m.file .. ":" .. line .. ":" end
    end))
  end

  local function load_entry(pkgid, path)
    local key = pkgid .. ":" .. path
    if cache[key] ~= nil then return cache[key] end
    if loading[key] then error("circular import of " .. key, 0) end
    local src = L.read(pkgid, path)
    if not src then error("module file missing: " .. key, 0) end
    loading[key] = true
    local short = path:gsub("^lib/", "")
    chunks[short] = { pkgid, path }
    local import = L.import_for(pkgid, dirname(path))
    local cubic_chunk = src:find("^local __rt, __import = %.%.%.") ~= nil
    local env = _G
    if not cubic_chunk then env = setmetatable({ import = import }, { __index = _G }) end
    local fn, err = load(src, "=" .. short, "t", env)
    if not fn then
      loading[key] = nil
      error(L.map_error(tostring(err)), 0)
    end
    local ok, res = pcall(fn, rtlib, import)
    loading[key] = nil
    if not ok then error(L.map_error(res), 0) end
    if res == nil then res = {} end
    cache[key] = res
    return res
  end

  function L.import_for(pkgid, base)
    return function(spec)
      local p, path = L.resolve(spec, pkgid, base or "")
      return load_entry(p, path)
    end
  end

  -- прямые зависимости модуля (для порядка предзагрузки): строки __import("...") в готовом Lua
  function L.deps(name)
    local ok, p, path = pcall(L.resolve, name)
    if not ok then return {} end
    local src = L.read(p, path) or ""
    local out = {}
    for dep in src:gmatch("__import%(\"([%w_%.]+)\"%)") do out[#out + 1] = dep end
    return out
  end

  L.import = L.import_for(nil, "")
  return L
end

return P
