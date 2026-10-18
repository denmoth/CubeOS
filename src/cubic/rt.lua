-- Cubic: рантайм (вспомогательные функции для сгенерированного Lua)
local rt = {}

local unpack = table.unpack or unpack
local setmetatable, getmetatable, type, pairs, ipairs, next, select, pcall, error, rawget, rawset, tostring =
  setmetatable, getmetatable, type, pairs, ipairs, next, select, pcall, error, rawget, rawset, tostring

rt.VERSION = "1.0.0"

-- Маркеры управления потоком для try
rt.RET = {}
rt.BRK = {}
rt.CNT = {}

function rt.pack(...)
  return { n = select("#", ...), ... }
end

function rt.unpack(t)
  return unpack(t, 1, t.n)
end

---------------------------------------------------------------- классы

local META = { "__tostring", "__eq", "__lt", "__le", "__add", "__sub", "__mul", "__div", "__mod", "__pow",
  "__unm", "__concat", "__len", "__call" }

function rt.class(name, base)
  local cls = {}
  cls.__index = cls
  cls.__name = name
  cls.__base = base
  if base then
    for _, k in ipairs(META) do
      if rawget(base, k) ~= nil then cls[k] = base[k] end
    end
  end
  setmetatable(cls, {
    __index = base,
    __call = function(c, ...)
      local o = setmetatable({}, c)
      local init = c.init
      if init then init(o, ...) end
      return o
    end,
    __tostring = function() return "<class " .. name .. ">" end,
  })
  return cls
end

function rt.isinstance(obj, cls)
  if type(obj) ~= "table" then return false end
  local mt = getmetatable(obj)
  while mt do
    if mt == cls then return true end
    mt = mt.__base
  end
  return false
end

---------------------------------------------------------------- ошибки

local Error = rt.class("Error")
function Error.init(self, message)
  self.message = message
end
Error.__tostring = function(self)
  return tostring(self.message)
end
rt.Error = Error

-- Строка или другое значение ошибки превращается в объект Error
function rt.wrap(e)
  if type(e) == "table" and getmetatable(e) ~= nil then return e end
  local w = Error(tostring(e))
  w.raw = e
  return w
end

function rt.rethrow(e)
  error(e, 0)
end

-- body/catch/finally возвращают (код, упакованные значения) для return/break/continue
function rt.try(body, catch, finally)
  local ok, c, v = pcall(body)
  if not ok and catch then
    local err = c
    ok, c, v = pcall(catch, err)
  end
  if finally then
    local fok, ferr = pcall(finally)
    if not fok then error(ferr, 0) end
  end
  if not ok then error(c, 0) end
  return c, v
end

---------------------------------------------------------------- копирование

function rt.copy(x)
  if type(x) ~= "table" then return x end
  local r = {}
  for k, v in next, x do r[k] = v end
  return setmetatable(r, getmetatable(x))
end

local function deep(x, seen)
  if type(x) ~= "table" then return x end
  if seen[x] then return seen[x] end
  local r = {}
  seen[x] = r
  for k, v in next, x do
    r[deep(k, seen)] = deep(v, seen)
  end
  return setmetatable(r, getmetatable(x))
end

function rt.deepcopy(x)
  return deep(x, {})
end

---------------------------------------------------------------- коллекции

-- длина строки в байтах, даже если хост считает # в символах UTF-8 (см. util.lua, U.blen)
local function blen(s)
  local n = #s
  if s:byte(n + 1) == nil then return n end
  local lo = n + 1
  local hi = lo * 2
  while s:byte(hi) do
    lo = hi
    hi = hi * 2
  end
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if s:byte(mid) then lo = mid else hi = mid end
  end
  return lo
end
rt.blen = blen

function rt.len(x)
  local t = type(x)
  if t == "string" then return blen(x) end
  if t ~= "table" then error("len() expects a string or a table, got " .. t, 2) end
  local n = #x
  if n > 0 then return n end
  local c = 0
  for _ in next, x do c = c + 1 end
  return c
end

-- то, что перебирает for x in e: таблица как есть, строка списком символов, функция-итератор списком значений
function rt.seq(e)
  local t = type(e)
  if t == "table" then return e end
  if t == "string" then return rt.chars(e) end
  if t == "function" then
    local out = {}
    for v in e do out[#out + 1] = v end
    return out
  end
  error("cannot iterate over a " .. t, 2)
end

-- список символов строки (UTF-8 целиком: «ё» один символ): for ch in chars(s)
function rt.chars(s)
  local out = {}
  for ch in tostring(s):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
  return out
end

-- len() в сборке для разработки: как #, но словарь (ключи без списка) это ошибка с подсказкой
function rt.lenc(x)
  local t = type(x)
  if t == "string" then return #x end
  if t ~= "table" then error("len() expects a list or a string, got " .. t, 2) end
  local n = #x
  if n == 0 and next(x) ~= nil then error("len() of a dictionary (it has keys, not list items): use count(d)", 2) end
  return n
end

-- число ключей таблицы (len() это длина списка или строки, как # в Lua)
function rt.count(x)
  if type(x) ~= "table" then error("count() expects a table, got " .. type(x), 2) end
  local c = 0
  for _ in next, x do c = c + 1 end
  return c
end

-- Строка: подстрока; таблица с элементами в массиве: значение; иначе: ключ
function rt.contains(container, v)
  local t = type(container)
  if t == "string" then
    if type(v) ~= "string" then return false end
    return container:find(v, 1, true) ~= nil
  elseif t == "table" then
    if #container > 0 then
      for i = 1, #container do
        if container[i] == v then return true end
      end
      return false
    end
    return container[v] ~= nil
  end
  error("'in' needs a string or a table on the right side, got " .. t, 2)
end

-- for x in e: значения
function rt.iter1(e)
  local t = type(e)
  if t == "function" then return e end
  if t == "table" then
    local i = 0
    return function()
      i = i + 1
      return e[i]
    end
  end
  if t == "string" then
    local i = 0
    return function()
      i = i + 1
      if i <= #e then return e:sub(i, i) end
    end
  end
  error("cannot iterate over a " .. t, 2)
end

-- for k, v in e: пары
function rt.iter2(e)
  local t = type(e)
  if t == "function" then return e end
  if t == "table" then return next, e, nil end
  error("cannot iterate over a " .. t, 2)
end

---------------------------------------------------------------- срезы, списки, словари

function rt.slice(x, i, j, step)
  local t = type(x)
  local n
  if t == "string" or t == "table" then n = #x else error("cannot slice a " .. t, 2) end
  step = step or 1
  if step == 0 then error("slice step cannot be zero", 2) end
  if step > 0 then
    i = i or 1
    j = j or n
  else
    i = i or n
    j = j or 1
  end
  if i < 0 then i = n + 1 + i end
  if j < 0 then j = n + 1 + j end
  if step > 0 then
    if i < 1 then i = 1 end
    if j > n then j = n end
  else
    if i > n then i = n end
    if j < 1 then j = 1 end
  end
  if t == "string" then
    if step == 1 then return x:sub(i, j) end
    local parts, c = {}, 0
    for k = i, j, step do
      c = c + 1
      parts[c] = x:sub(k, k)
    end
    return table.concat(parts)
  end
  local out, c = {}, 0
  for k = i, j, step do
    c = c + 1
    out[c] = x[k]
  end
  return out
end

function rt.cat(...)
  local out, c = {}, 0
  for a = 1, select("#", ...) do
    local t = (select(a, ...))
    for k = 1, #t do
      c = c + 1
      out[c] = t[k]
    end
  end
  return out
end

function rt.merge(...)
  local out = {}
  for a = 1, select("#", ...) do
    for k, v in next, (select(a, ...)) do out[k] = v end
  end
  return out
end

function rt.unpack_list(t)
  return unpack(t, 1, #t)
end

---------------------------------------------------------------- именованные аргументы

local sigs = setmetatable({}, { __mode = "k" })
local sig_cache = {}

function rt.sig(fn, names)
  sigs[fn] = names
  return fn
end

local function sig_list(s)
  local l = sig_cache[s]
  if not l then
    l = {}
    for name in s:gmatch("[^,]+") do l[#l + 1] = name end
    sig_cache[s] = l
  end
  return l
end

local function bind(names, skip, kw, nargs, args)
  local maxn = nargs
  for k, v in next, kw do
    local idx
    for p = 1, #names do
      if names[p] == k then idx = p break end
    end
    if not idx then error("unexpected keyword argument '" .. tostring(k) .. "'", 3) end
    idx = idx - skip
    if idx < 1 then error("cannot pass '" .. tostring(k) .. "' by keyword", 3) end
    if idx <= nargs then error("argument '" .. tostring(k) .. "' was given twice", 3) end
    args[idx] = v
    if idx > maxn then maxn = idx end
  end
  return maxn
end

function rt.kcall(fn, kw, ...)
  local s = sigs[fn]
  local skip = 0
  if not s and type(fn) == "table" then
    local init = fn.init
    s = init and sigs[init]
    skip = 1
  end
  if not s then error("this function does not accept keyword arguments", 2) end
  local args = { ... }
  local maxn = bind(sig_list(s), skip, kw, select("#", ...), args)
  return fn(unpack(args, 1, maxn))
end

function rt.kcallm(obj, name, kw, ...)
  local fn = obj[name]
  local s = sigs[fn]
  if not s then error("method '" .. tostring(name) .. "' does not accept keyword arguments", 2) end
  local args = { obj, ... }
  local maxn = bind(sig_list(s), 0, kw, select("#", ...) + 1, args)
  return fn(unpack(args, 1, maxn))
end

---------------------------------------------------------------- with, match

function rt.release(v)
  if type(v) == "table" then
    local ex = v.__exit
    if ex then return ex(v) end
    local c = v.close
    if c then return c(v) end
  end
end

function rt.match_attr(obj, cls, i)
  local args = cls.__match_args
  if not args then
    error("class " .. tostring(cls.__name) .. " has no __match_args for positional patterns", 0)
  end
  return obj[args[i]]
end

---------------------------------------------------------------- форматирование f-строк

local fmt_cache = {}

local function parse_spec(spec)
  local s = spec
  local P = {}
  local f, a, r = s:match("^(.)([<>^=])(.*)$")
  if f then
    P.fill, P.align, s = f, a, r
  else
    a, r = s:match("^([<>^=])(.*)$")
    if a then P.align, s = a, r end
  end
  local sign, r2 = s:match("^([+%- ]?)(.*)$")
  P.sign, s = sign, r2
  local zero, r3 = s:match("^(0?)(.*)$")
  P.zero, s = (zero == "0"), r3
  local width, r4 = s:match("^(%d*)(.*)$")
  P.width, s = tonumber(width), r4
  local comma, r5 = s:match("^([,_]?)(.*)$")
  P.comma, s = comma, r5
  local prec, r6 = s:match("^%.(%d+)(.*)$")
  if prec then
    P.prec, s = tonumber(prec), r6
  end
  if #s > 1 then error("invalid format specifier '" .. spec .. "'", 0) end
  P.type = s
  return P
end

local function group_thousands(str, sep)
  local int, rest = str:match("^(%-?%d+)(.*)$")
  if not int then return str end
  local sign = ""
  if int:sub(1, 1) == "-" then
    sign, int = "-", int:sub(2)
  end
  local out = int:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
  if out:sub(1, #sep) == sep then out = out:sub(#sep + 1) end
  return sign .. out .. rest
end

function rt.fmt(v, spec)
  local P = fmt_cache[spec]
  if not P then
    P = parse_spec(spec)
    fmt_cache[spec] = P
  end
  local typ = P.type
  local str
  local numeric = type(v) == "number"
  if typ == "d" then
    if not numeric or v ~= math.floor(v) then error("format 'd' needs an integer, got " .. tostring(v), 0) end
    str = string.format("%d", v)
  elseif typ == "f" or typ == "F" then
    if not numeric then error("format 'f' needs a number", 0) end
    str = string.format("%." .. (P.prec or 6) .. "f", v)
  elseif typ == "e" or typ == "E" or typ == "g" or typ == "G" then
    if not numeric then error("format '" .. typ .. "' needs a number", 0) end
    str = string.format("%" .. (P.prec and ("." .. P.prec) or "") .. typ, v)
  elseif typ == "x" or typ == "X" or typ == "o" then
    if not numeric then error("format '" .. typ .. "' needs a number", 0) end
    str = string.format("%" .. typ, v)
  elseif typ == "b" then
    if not numeric then error("format 'b' needs a number", 0) end
    local n, bits = math.floor(v), {}
    if n == 0 then bits[1] = "0" end
    while n > 0 do
      table.insert(bits, 1, tostring(n % 2))
      n = math.floor(n / 2)
    end
    str = table.concat(bits)
  elseif typ == "%" then
    str = string.format("%." .. (P.prec or 6) .. "f", v * 100) .. "%"
  else
    if numeric and P.prec then
      str = string.format("%." .. P.prec .. "g", v)
    else
      str = tostring(v)
      if P.prec and not numeric then str = str:sub(1, P.prec) end
    end
  end
  if numeric then
    if P.sign == "+" and v >= 0 then str = "+" .. str
    elseif P.sign == " " and v >= 0 then str = " " .. str end
    if P.comma ~= "" then str = group_thousands(str, P.comma == "_" and "_" or ",") end
  end
  if P.width and #str < P.width then
    local pad = P.width - #str
    local fill = P.fill or (P.zero and "0" or " ")
    local align = P.align or (P.zero and "=") or (numeric and ">" or "<")
    if align == "=" then
      local sg, body = str:match("^([+%- ]?)(.*)$")
      str = sg .. fill:rep(pad) .. body
    elseif align == ">" then
      str = fill:rep(pad) .. str
    elseif align == "<" then
      str = str .. fill:rep(pad)
    else
      local left = math.floor(pad / 2)
      str = fill:rep(left) .. str .. fill:rep(pad - left)
    end
  end
  return str
end

---------------------------------------------------------------- прочее

function rt.nvl(a, b)
  if a ~= nil then return a end
  return b
end

function rt.nvl_lazy(a, f)
  if a ~= nil then return a end
  return f()
end

function rt.oget(o, k)
  if o == nil then return nil end
  return o[k]
end

---------------------------------------------------------------- автоматическая отдача управления

-- Код, скомпилированный с опцией yield (--yield), вызывает rt.tick() каждые 256 итераций цикла.
-- Два режима:
--   * ядро CubeOS ставит rt.slice_hook: если с начала кванта (rt.slice_t0) прошло не меньше rt.slice_ms,
--     вызывается hook(now): ядро уступает управление планировщику и само обновляет rt.slice_t0;
--   * без ядра: если с последней отдачи прошло не меньше rt.sys_ms, управление отдаётся самому CC
--     (иначе он убьёт программу за "Too long without yielding", предел около 7 секунд).
rt.slice_ms = 50
rt.sys_ms = 2500
rt.native_yields = 0

local function clock_ms()
  if os.epoch then return os.epoch("utc") end
  return os.clock() * 1000
end
rt.clock_ms = clock_ms
rt.slice_t0 = clock_ms()
rt.sys_t0 = rt.slice_t0

-- отдаёт управление CC и возвращается; чужие события сохраняются и возвращаются в очередь
function rt.native_yield()
  rt.native_yields = rt.native_yields + 1
  if not (os.queueEvent and os.pullEventRaw) then
    rt.sys_t0 = clock_ms()
    return
  end
  local stash = {}
  os.queueEvent("cubic_yield")
  while true do
    local ev = table.pack(os.pullEventRaw())
    if ev[1] == "cubic_yield" then break end
    if ev[1] == "terminate" then error("Terminated", 0) end
    stash[#stash + 1] = ev
  end
  for _, ev in ipairs(stash) do os.queueEvent(table.unpack(ev, 1, ev.n)) end
  rt.sys_t0 = clock_ms()
end

function rt.tick()
  local now = clock_ms()
  local hook = rt.slice_hook
  if hook then
    if now - rt.slice_t0 >= rt.slice_ms then hook(now) end
    return
  end
  if now - rt.sys_t0 >= rt.sys_ms then rt.native_yield() end
end

return rt
