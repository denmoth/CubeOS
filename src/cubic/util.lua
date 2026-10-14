-- Cubic: общие помощники (ошибки, множества, экранирование строк)
local U = {}

U.ErrorMT = {}
U.ErrorMT.__index = U.ErrorMT
U.ErrorMT.__tostring = function(e)
  return (e.file or "?") .. ":" .. (e.line or 0) .. ":" .. (e.col or 0) .. ": " .. e.msg
end

-- Бросает ошибку компиляции (таблица, чтобы её можно было отличить от ошибок Lua)
function U.fail(file, line, col, msg)
  error(setmetatable({ file = file, line = line, col = col, msg = msg, cubic = true }, U.ErrorMT), 0)
end

function U.set(list)
  local s = {}
  for _, v in ipairs(list) do s[v] = true end
  return s
end

U.LUA_RESERVED = U.set({
  "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in",
  "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
})

function U.is_lua_name(s)
  return type(s) == "string" and s:match("^[%a_][%w_]*$") ~= nil and not U.LUA_RESERVED[s]
end

-- Строка Lua-литерала без реальных переводов строк
function U.quote(s)
  local out = s:gsub('[%c\\"\127]', function(c)
    if c == "\\" then return "\\\\" end
    if c == '"' then return '\\"' end
    if c == "\n" then return "\\n" end
    if c == "\r" then return "\\r" end
    if c == "\t" then return "\\t" end
    return string.format("\\%03d", c:byte())
  end)
  return '"' .. out .. '"'
end

-- UTF-8 кодирование кодовой точки
function U.utf8(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  else
    return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
      0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
end

-- Длина строки в БАЙТАХ. В хосте с поддержкой UTF-8 (например, с модом cc-tweaked-unicode-support) оператор # и
-- string.len считают символы, а не байты, и разбор текста с кириллицей обрывается раньше конца файла.
-- s:byte(i) байтовый всегда, поэтому длина ищется по нему, если # не совпал с реальной.
function U.blen(s)
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

return U
