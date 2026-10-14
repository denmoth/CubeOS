-- plain Lua module (no types): the compiler makes a rough stub from this text
local M = {}

function M.hello(name, greeting)
  return "hi " .. name
end

M.VERSION = "1.0"

function M:method(a)
  return a
end

function M.vararg(...)
  return select("#", ...)
end

return M
