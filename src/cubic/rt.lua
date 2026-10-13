-- Cubic: рантайм (вспомогательные функции для сгенерированного Lua)
local rt = {}

local unpack = table.unpack or unpack
local setmetatable, getmetatable, type, pairs, ipairs, next, select, pcall, error, rawget, rawset, tostring =
  setmetatable, getmetatable, type, pairs, ipairs, next, select, pcall, error, rawget, rawset, tostring

rt.VERSION = "0.1.0"

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

function rt.len(x)
  local t = type(x)
  if t == "string" then return #x end
  if t ~= "table" then error("len() expects a string or a table, got " .. t, 2) end
  local n = #x
  if n > 0 then return n end
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

return rt
