-- Cubic: защищённые встроенные имена и отображение встроенных функций языка
local U = ...

local B = {}

-- Ядро Lua и встроенные функции Cubic: присвоение или объявление без `override` это ошибка
-- Cubic 1.0: короткие слова, которые естественно брать для своих переменных (copy, load, next, len, str, num, select...),
-- больше не защищены: присвоение делает локальную переменную, она скрывает встроенную только в своей области
B.PROTECTED = U.set({
  "assert", "collectgarbage", "error", "getfenv", "getmetatable", "ipairs", "loadstring",
  "pairs", "pcall", "print", "rawequal", "rawget", "rawset", "setfenv", "setmetatable", "tonumber", "tostring",
  "type", "xpcall", "_G", "_ENV", "_VERSION",
  "math", "string", "table", "os", "io", "coroutine", "debug", "bit", "bit32", "utf8", "package",
  "isinstance", "Error",
})

-- API CC: Tweaked: перекрытие даёт предупреждение (локальная переменная скрывает глобальный API)
B.SHADOW_WARN = U.set({
  "term", "fs", "peripheral", "rednet", "redstone", "rs", "colors", "colours", "disk", "gps", "help", "http",
  "keys", "multishell", "paintutils", "parallel", "pocket", "settings", "shell", "textutils", "turtle",
  "vector", "window", "commands", "sleep", "write", "read", "printError",
})

-- Встроенные функции Cubic -> выражение в сгенерированном Lua
B.MAP = {
  copy = "__rt.copy",
  deepcopy = "__rt.deepcopy",
  len = "__rt.len",
  count = "__rt.count",
  chars = "__rt.chars",
  str = "__tostring",
  num = "__tonumber",
  isinstance = "__rt.isinstance",
  Error = "__rt.Error",
}

return B
