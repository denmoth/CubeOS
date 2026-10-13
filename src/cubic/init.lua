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
  if not opts.headers or #opts.headers == 0 then return base_env end
  local env = copy_env(base_env)
  for _, h in ipairs(opts.headers) do
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

return C
