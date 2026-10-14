-- Консольная утилита Cubic. Запускается внутри CC / CraftOS-PC.
--   cubic compile <файл.cub> [вывод.lua] [--minify] [--keep-comments] [--map] [--strict] [--mods=a,b]
--   cubic check   <файл.cub>
--   cubic run     <файл.cub>
--   Для редакторов (вывод JSON): language | grammar | tokens | symbols | diagnostics | complete | signature | hover
--     cubic complete <файл> --line=N --col=M      (столбцы и строки с единицы, столбец в байтах)
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
local EDITOR_CMDS = { tokens = true, symbols = true, diagnostics = true, complete = true, signature = true, hover = true }
local NO_INPUT = { language = true, grammar = true }
if not cmd or (not input and not NO_INPUT[cmd]) then
  say("usage: cubic compile|check|run <file.cub> [out.lua] [--minify] [--keep-comments] [--map] [--strict] [--mods=a,b]")
  say("       cubic language|grammar    |    cubic tokens|symbols|diagnostics|complete|signature|hover <file> [--line=N --col=M]")
  return finish(2)
end

if NO_INPUT[cmd] then
  local data = cmd == "language" and cubic.tooling.language() or cubic.tooling.textmate()
  say(textutils.serializeJSON(data))
  return finish(0)
end

local src = read(input)
if not src then
  say("error: cannot read " .. input)
  return finish(1)
end

local name = fs.getName(input)
local opts = { minify = flags["minify"], keep_comments = flags["keep-comments"], strict = flags["strict"] }

-- файл проекта cubic.json5 (ищется вверх от каталога исходника):
--   { mods: ["advancedperipherals"], headers: ["api/game.cuh"], strict: true, minify: false }
local function find_project_file(start_dir)
  local dir = start_dir
  while true do
    local candidate = fs.combine(dir, "cubic.json5")
    if fs.exists(candidate) then return candidate, dir end
    if dir == "" or dir == "/" or dir == ".." then return nil end
    dir = fs.getDir(dir)
  end
end

local project_cfg = nil
local project_file, project_dir = find_project_file(fs.getDir(input))
if project_file then
  local loader = cubic.new_loader({ roots = { ROOT .. "/lib" } })
  local json5 = loader.import("json5")
  local ok, cfg = pcall(json5.parse, read(project_file))
  if not ok then
    say("error: " .. project_file .. ": " .. tostring(cfg))
    return finish(1)
  end
  project_cfg = cfg
  say("project: " .. project_file)
  if cfg.strict and opts.strict == nil then opts.strict = true end
  if cfg.minify and opts.minify == nil then opts.minify = true end
  opts.mods = {}
  for _, id in ipairs(cfg.mods or {}) do opts.mods[#opts.mods + 1] = id end
  opts.headers = {}
  for _, rel in ipairs(cfg.headers or {}) do
    local path = fs.combine(project_dir, rel)
    local text = read(path)
    if not text then
      say("error: header not found: " .. path)
      return finish(1)
    end
    opts.headers[#opts.headers + 1] = { src = text, name = rel }
  end
end

if type(flags["mods"]) == "string" then
  opts.mods = opts.mods or {}
  for id in flags["mods"]:gmatch("[^,]+") do opts.mods[#opts.mods + 1] = id end
end
-- module loader: project libs, the project directory, the source directory and the system lib/
local roots = {}
local input_dir = fs.getDir(input)
if project_dir then roots[#roots + 1] = project_dir end
for _, rel in ipairs(project_cfg and project_cfg.libs or {}) do
  roots[#roots + 1] = fs.combine(project_dir or input_dir, rel)
end
roots[#roots + 1] = input_dir
roots[#roots + 1] = ROOT .. "/lib"
local loader = cubic.new_loader({ roots = roots, base = input_dir })
opts.loader = loader
opts.base_dir = input_dir
opts.header_cache = (project_cfg and project_cfg.cache) or (ROOT .. "/build/cuh-cache")

if EDITOR_CMDS[cmd] then
  local tl = cubic.tooling
  local line, col = tonumber(flags["line"]), tonumber(flags["col"])
  opts.file = name
  local data
  if cmd == "tokens" then
    local toks, embedded = tl.highlight(src)
    data = { tokens = toks, embedded = embedded }
  elseif cmd == "symbols" then
    data = tl.symbols(src)
  elseif cmd == "diagnostics" then
    data = tl.diagnostics(src, name, opts)
  elseif line and col then
    data = tl[cmd](src, line, col, opts)
  else
    say("error: " .. cmd .. " needs --line=N --col=M")
    return finish(2)
  end
  if data == nil then data = {} end
  say(textutils.serializeJSON(data))
  return finish(0)
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
  opts.import = loader.import_for(input_dir)
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
