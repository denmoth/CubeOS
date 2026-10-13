-- Консольная утилита Cubic. Запускается внутри CC / CraftOS-PC.
--   cubic compile <файл.cub> [вывод.lua] [--minify] [--keep-comments] [--map] [--strict] [--mods=a,b]
--   cubic check   <файл.cub>
--   cubic run     <файл.cub>
-- В CraftOS-PC вывод `print` не попадает в stdout, поэтому весь вывод дополнительно пишется в файл
-- /repo/build/cli-output.txt (если каталог существует).

local ROOT = fs.exists("/repo/src/cubic/init.lua") and "/repo" or fs.getDir(fs.getDir(shell and shell.getRunningProgram() or "/"))
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")

local raw = { ... }
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

-- разбор аргументов: позиционные и --флаги
local args, flags = {}, {}
for _, a in ipairs(raw) do
  local key, val = a:match("^%-%-([%w%-]+)=(.*)$")
  if key then
    flags[key] = val
  elseif a:sub(1, 2) == "--" then
    flags[a:sub(3)] = true
  else
    args[#args + 1] = a
  end
end
local cmd, input, output = args[1], args[2], args[3]
if not cmd or not input then
  say("usage: cubic compile|check|run <file.cub> [out.lua] [--minify] [--keep-comments] [--map] [--strict] [--mods=a,b]")
  return finish(2)
end

local src = read(input)
if not src then
  say("error: cannot read " .. input)
  return finish(1)
end

local name = fs.getName(input)
local opts = { minify = flags["minify"], keep_comments = flags["keep-comments"], strict = flags["strict"] }
if type(flags["mods"]) == "string" then
  opts.mods = {}
  for id in flags["mods"]:gmatch("[^,]+") do opts.mods[#opts.mods + 1] = id end
end
local lua, linemap, warnings = cubic.try_compile(src, name, opts)
if not lua then
  say("error: " .. tostring(linemap))
  return finish(1)
end
for _, w in ipairs(warnings or {}) do say(w) end

if cmd == "compile" then
  output = output or input:gsub("%.cub$", "") .. ".lua"
  write(output, lua)
  say("compiled " .. input .. " -> " .. output .. " (" .. #lua .. " bytes)")
  if flags["map"] then
    local map_path = output:gsub("%.lua$", "") .. ".map"
    write(map_path, cubic.map_to_string(linemap, name))
    say("map written to " .. map_path)
  end
elseif cmd == "run" then
  opts.env = setmetatable({ print = say }, { __index = _G })
  local ok, err = pcall(cubic.run, src, name, opts)
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
