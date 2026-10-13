-- Cubic: точка входа компилятора.
-- Использование:
--   local cubic = loadfile("/путь/к/src/cubic/init.lua")("/путь/к/src/cubic")
--   local lua_code, linemap = cubic.compile(source, "имя.cub", { minify = false, keep_comments = false })
--   local exports = cubic.run(source, "имя.cub", { env = ..., import = ... })
local root = ...

local function load_module(name, ...)
  local chunk, err = loadfile(root .. "/" .. name .. ".lua")
  if not chunk then error(err, 0) end
  return chunk(...)
end

local U = load_module("util")
local lexer = load_module("lexer", U)
local parser = load_module("parser", U, lexer)
local B = load_module("builtins", U)
local codegen = load_module("codegen", U, B)
local rt = load_module("rt")
local checker = load_module("checker", U)

local function read_file(path)
  if fs and fs.open then
    local f = fs.open(path, "rb")
    if not f then return nil end
    local s = f.readAll()
    f.close()
    return s
  end
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local C = {}
C.VERSION = "0.3.0"
C.rt = rt
C.util = U

local base_env

local function copy_env(env)
  local c = { vars = {}, types = {} }
  for k, v in pairs(env.vars) do c.vars[k] = v end
  for k, v in pairs(env.types) do c.types[k] = v end
  return c
end

-- Окружение типов: встроенные заголовки + пользовательские (opts.headers = { {src=..., name=...}, ... })
local function type_env(opts)
  if not base_env then
    base_env = checker.new_env()
    for _, name in ipairs({ "lua", "cc" }) do
      local src = read_file(root .. "/headers/" .. name .. ".cuh")
      if src then
        local hast = parser.parse_header(src, name .. ".cuh")
        checker.check(hast, name .. ".cuh", base_env, true)
      end
    end
  end
  local extra = {}
  for _, h in ipairs(opts.headers or {}) do extra[#extra + 1] = h end
  for _, mod in ipairs(opts.mods or {}) do
    local src = read_file(root .. "/headers/mods/" .. mod .. ".cuh")
    if not src then
      error("unknown mod for type headers: " .. tostring(mod) .. " (no headers/mods/" .. tostring(mod) .. ".cuh)", 0)
    end
    extra[#extra + 1] = { src = src, name = mod .. ".cuh" }
  end
  if #extra == 0 then return base_env end
  local env = copy_env(base_env)
  env.periph = {}
  for k, v in pairs(base_env.periph) do env.periph[k] = v end
  for _, h in ipairs(extra) do
    local hast = parser.parse_header(h.src, h.name or "header.cuh")
    checker.check(hast, h.name or "header.cuh", env, true)
  end
  return env
end

-- Компилирует исходник Cubic в Lua.
-- opts: minify (короткие имена, без отступов), keep_comments (переносит комментарии как --)
-- Возвращает: lua_code, linemap (строка Lua -> строка .cub), warnings
function C.compile(src, file, opts)
  file = file or "?"
  opts = opts or {}
  local ast = parser.parse(src, file)
  if checker.needs_check(ast, opts) then
    checker.check(ast, file, type_env(opts), false, opts)
  end
  return codegen.generate(ast, file, opts)
end

-- То же, но не бросает ошибку: возвращает nil, "сообщение"
function C.try_compile(src, file, opts)
  local ok, a, b, c = pcall(C.compile, src, file, opts)
  if ok then return a, b, c end
  if type(a) == "table" and a.cubic then return nil, tostring(a), a end
  return nil, tostring(a)
end

-- Карта строк в текстовом виде: "lua:src" через пробел, подряд идущие совпадения сжимаются
function C.map_to_string(linemap, file)
  local parts, prev = {}, nil
  for i, src in ipairs(linemap) do
    if src ~= prev then
      parts[#parts + 1] = i .. ":" .. src
      prev = src
    end
  end
  return "cubic-map 1 " .. (file or "?") .. "\n" .. table.concat(parts, " ") .. "\n"
end

function C.map_from_string(text)
  local header, body = text:match("^(.-)\n(.*)$")
  local file = header and header:match("^cubic%-map 1 (.*)$")
  if not file then return nil end
  local starts = {}
  for lua_line, src_line in body:gmatch("(%d+):(%d+)") do
    starts[#starts + 1] = { tonumber(lua_line), tonumber(src_line) }
  end
  local linemap = {}
  for k, st in ipairs(starts) do
    local last = (starts[k + 1] and starts[k + 1][1] - 1) or st[1]
    for l = st[1], last do linemap[l] = st[2] end
  end
  return linemap, file
end

-- Преобразует "chunk:LINE:" в сообщении об ошибке Lua в строку исходника .cub
function C.map_error(msg, linemap, chunkname, file)
  if type(msg) ~= "string" or not linemap then return msg end
  local escaped = chunkname:gsub("%p", "%%%0")
  return (msg:gsub(escaped .. ":(%d+):", function(n)
    local src = linemap[tonumber(n)]
    if src then return file .. ":" .. src .. ":" end
  end))
end

-- Компилирует и загружает модуль. Возвращает функцию, которая выполняет модуль и отдаёт его экспорты.
-- opts: env (окружение, по умолчанию _G), import (функция import(путь) -> модуль), плюс опции компиляции
function C.load(src, file, opts)
  opts = opts or {}
  file = file or "?"
  local lua, linemap, warnings = C.compile(src, file, opts)
  local chunkname = "=" .. file
  local fn, err = load(lua, chunkname, "t", opts.env or _G)
  if not fn then
    error("internal compiler error: generated Lua does not load: " .. tostring(err) .. "\n" .. lua, 0)
  end
  local import = opts.import or function(path)
    error("import is not available here: " .. path, 0)
  end
  local runner = function()
    local ok, res = pcall(fn, rt, import)
    if not ok then
      error(C.map_error(res, linemap, file, file), 0)
    end
    return res
  end
  return runner, lua, linemap, warnings
end

function C.run(src, file, opts)
  local runner = C.load(src, file, opts)
  return runner()
end

---------------------------------------------------------------- загрузчик модулей

local function dirname(p)
  return (p:match("^(.*)/[^/]*$")) or ""
end

local function join(a, b)
  if a == "" then return b end
  if b:sub(1, 1) == "/" then return b end
  return a .. "/" .. b
end

local function normalize(p)
  local abs = p:sub(1, 1) == "/"
  local parts = {}
  for seg in p:gmatch("[^/]+") do
    if seg == "." then
      -- пропускаем
    elseif seg == ".." then
      if #parts > 0 and parts[#parts] ~= ".." then
        parts[#parts] = nil
      elseif not abs then
        parts[#parts + 1] = ".."
      end
    else
      parts[#parts + 1] = seg
    end
  end
  return (abs and "/" or "") .. table.concat(parts, "/")
end

C.path = { dirname = dirname, join = join, normalize = normalize }

local default_fs = {
  read = read_file,
  exists = function(p)
    if fs and fs.exists then return fs.exists(p) and not fs.isDir(p) end
    local f = io.open(p, "rb")
    if f then f:close() return true end
    return false
  end,
}

-- Загрузчик модулей для import.
-- cfg: roots (каталоги поиска для `import a.b`), aliases ({имя = путь} для `$имя/...`),
--      env (окружение модулей), compile_opts, fs ({read, exists}), base (каталог для `./`)
-- Возвращает L с функциями L.import (для кода верхнего уровня) и L.import_for(каталог).
function C.new_loader(cfg)
  cfg = cfg or {}
  local rfs = cfg.fs or default_fs
  local roots = cfg.roots or {}
  local aliases = cfg.aliases or {}
  local cache, loading = {}, {}
  local L = {}

  local function find_file(base)
    for _, cand in ipairs({ base, base .. ".cub", base .. ".lua", base .. "/init.cub", base .. "/init.lua" }) do
      if rfs.exists(cand) then return cand end
    end
    return nil
  end

  local function load_file(path)
    if cache[path] ~= nil then return cache[path] end
    if loading[path] then error("circular import of " .. path, 0) end
    loading[path] = true
    local result
    local ok, err = pcall(function()
      local src = rfs.read(path)
      if not src then error("cannot read " .. path, 0) end
      local env = cfg.env or _G
      if path:sub(-4) == ".cub" then
        local opts = {}
        for k, v in pairs(cfg.compile_opts or {}) do opts[k] = v end
        opts.env = env
        opts.import = L.import_for(dirname(path))
        local runner = C.load(src, path, opts)
        result = runner()
      else
        local fn, e = load(src, "=" .. path, "t", env)
        if not fn then error(e, 0) end
        result = fn()
      end
    end)
    loading[path] = nil
    if not ok then error(err, 0) end
    if result == nil then result = {} end
    cache[path] = result
    return result
  end

  function L.resolve(spec, base_dir)
    local base
    if spec:sub(1, 2) == "./" or spec:sub(1, 3) == "../" then
      base = normalize(join(base_dir or "", spec))
    elseif spec:sub(1, 1) == "/" then
      base = normalize(spec)
    elseif spec:sub(1, 1) == "$" then
      local alias, rest = spec:match("^%$([%w_]+)(.*)$")
      local target = aliases[alias]
      if not target then error("unknown path alias $" .. tostring(alias), 0) end
      base = normalize(target .. rest)
    else
      local rel = spec:gsub("%.", "/")
      for _, root in ipairs(roots) do
        local f = find_file(normalize(join(root, rel)))
        if f then return f end
      end
      error("module '" .. spec .. "' not found in: " .. table.concat(roots, ", "), 0)
    end
    local f = find_file(base)
    if not f then error("module '" .. spec .. "' not found (" .. base .. ")", 0) end
    return f
  end

  function L.import_for(base_dir)
    return function(spec)
      return load_file(L.resolve(spec, base_dir))
    end
  end

  L.import = L.import_for(cfg.base or "")
  L.cache = cache
  return L
end

return C
