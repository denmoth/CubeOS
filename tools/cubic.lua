-- Консольная утилита Cubic. Запускается внутри CC / CraftOS-PC.
--   cubic compile <файл.cub> [вывод.lua]   компиляция
--   cubic check   <файл.cub>               только проверка
--   cubic run     <файл.cub>               компиляция и запуск
-- В CraftOS-PC вывод `print` не попадает в stdout, поэтому весь вывод дополнительно пишется в файл
-- /repo/build/cli-output.txt (если каталог существует).

local ROOT = fs.exists("/repo/src/cubic/init.lua") and "/repo" or fs.getDir(fs.getDir(shell and shell.getRunningProgram() or "/"))
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")

local args = { ... }
local lines = {}

local function say(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  local s = table.concat(parts, "\t")
  lines[#lines + 1] = s
  print(s)
end

local function read(path)
  local f = fs.open(path, "rb")
  if not f then return nil end
  local s = f.readAll()
  f.close()
  return s
end

local function write(path, data)
  local f = fs.open(path, "wb")
  f.write(data)
  f.close()
end

local function finish(code)
  if fs.isDir(ROOT .. "/build") then
    write(ROOT .. "/build/cli-output.txt", table.concat(lines, "\n") .. "\n" .. "exit:" .. code .. "\n")
  end
  if os.shutdown and not shell then os.shutdown() end
  return code
end

local cmd, input, output = args[1], args[2], args[3]
if not cmd or not input then
  say("usage: cubic compile|check|run <file.cub> [out.lua]")
  return finish(2)
end

local src = read(input)
if not src then
  say("error: cannot read " .. input)
  return finish(1)
end

local name = fs.getName(input)
local lua, linemap, warnings = cubic.try_compile(src, name)
if not lua then
  say("error: " .. tostring(linemap))
  return finish(1)
end
for _, w in ipairs(warnings or {}) do say(w) end

if cmd == "compile" then
  output = output or input:gsub("%.cub$", "") .. ".lua"
  write(output, lua)
  say("compiled " .. input .. " -> " .. output .. " (" .. #lua .. " bytes)")
elseif cmd == "run" then
  local ok, err = pcall(cubic.run, src, name, { env = setmetatable({ print = say }, { __index = _G }) })
  if not ok then
    say("runtime error: " .. tostring(err))
    return finish(1)
  end
elseif cmd == "check" then
  say("ok: " .. input)
else
  say("unknown command: " .. cmd)
  return finish(2)
end
return finish(0)
