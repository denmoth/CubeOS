-- Замеры для формата .cpk (docs/packages/README.md, шаг 0). Запуск: tools/pkg_measure.sh (CraftOS-PC без окна).
-- Пишет build/pkg-measure.txt и build/dist/lib/*.lua (выпускная сборка, её же читает tools/pkg_measure.py для zlib).
local ROOT = "/repo"
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
local loader = cubic.new_loader({ roots = { ROOT .. "/lib" } })
local deflate, lzfast = loader.import("deflate"), loader.import("lzfast")

local out = {}
local function say(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
local function read(p) local f = fs.open(p, "rb"); local s = f.readAll(); f.close(); return s end
local function write(p, d) fs.makeDir(fs.getDir(p)); local f = fs.open(p, "wb"); f.write(d); f.close() end
local function breathe() os.queueEvent("m"); os.pullEvent("m") end
local function now() return os.epoch("utc") end
local function flush() write(ROOT .. "/build/pkg-measure.txt", table.concat(out, "\n") .. "\n") end

-- 1. сколько места съедает файл и папка
local probe = "/pkgprobe"
if fs.exists(probe) then fs.delete(probe) end
local free0 = fs.getFreeSpace("/")
fs.makeDir(probe)
local free1 = fs.getFreeSpace("/")
write(probe .. "/a", "x")
local free2 = fs.getFreeSpace("/")
write(probe .. "/b", string.rep("x", 600))
local free3 = fs.getFreeSpace("/")
fs.delete(probe)
say("free space: total %s", free0)
say("empty dir costs %s, 1-byte file costs %s, 600-byte file costs %s", free0 - free1, free1 - free2, free2 - free3)

-- 2. выпускная сборка lib (минификация), порядок файлов: по папкам, как они лежат
local files = {}
local function walk(dir, rel)
  local names = fs.list(dir)
  table.sort(names)
  for _, name in ipairs(names) do
    local p = dir .. "/" .. name
    local r = rel == "" and name or (rel .. "/" .. name)
    if fs.isDir(p) then walk(p, r)
    elseif name:match("%.cub$") then
      local ok, code = pcall(cubic.compile, read(p), "lib/" .. r, { minify = true, banner = false, release = true })
      if ok and type(code) == "string" then
        files[#files + 1] = { path = r:gsub("%.cub$", ".lua"), code = code }
        write(ROOT .. "/build/dist/lib/" .. files[#files].path, code)
      else say("compile failed: %s: %s", r, tostring(code):sub(1, 100)) end
      breathe()
    end
  end
end
walk(ROOT .. "/lib", "")
local rtcode = read(ROOT .. "/src/cubic/rt.lua")
files[#files + 1] = { path = "cubic/rt.lua", code = rtcode }

local total, cc_cost = 0, 0
for _, f in ipairs(files) do total = total + #f.code; cc_cost = cc_cost + math.max(500, #f.code) end
say("release lua: %s files, %s bytes, as loose files in CC %s bytes", #files, total, cc_cost)
flush()

-- 3. сжатие: по файлу, блоками, (целиком считает pkg_measure.py через zlib)
local function measure(label, groups, method)
  local stored, cc, t, maxdec, decsum = 0, 0, 0, 0, 0
  for _, g in ipairs(groups) do
    local t0 = now()
    local c = method == "deflate" and deflate.deflate(g) or lzfast.compress(g)
    t = t + (now() - t0)
    breathe()
    local t1 = now()
    local back = method == "deflate" and deflate.inflate(c) or lzfast.decompress(c)
    local dt = now() - t1
    decsum = decsum + dt
    if dt > maxdec then maxdec = dt end
    if back ~= g then say("  ROUNDTRIP FAILED in %s", label) end
    stored = stored + #c
    cc = cc + math.max(500, #c)
    breathe()
  end
  say("%-22s %-7s groups=%s stored=%s asfiles=%s pack_ms=%s unpack_ms=%s (max block %s ms, %.0f KB/s)",
    label, method, #groups, stored, cc, t, decsum, maxdec, total / 1024 / math.max(decsum, 1) * 1000)
  flush()
end

local function blocks(limit)
  local groups, cur = {}, {}
  local size = 0
  for _, f in ipairs(files) do
    if #f.code >= limit then
      groups[#groups + 1] = f.code
    else
      if size + #f.code > limit and #cur > 0 then
        groups[#groups + 1] = table.concat(cur); cur = {}; size = 0
      end
      cur[#cur + 1] = f.code; size = size + #f.code
    end
  end
  if #cur > 0 then groups[#groups + 1] = table.concat(cur) end
  return groups
end

local per = {}
for _, f in ipairs(files) do per[#per + 1] = f.code end
measure("per file", per, "lzfast")
measure("per file", per, "deflate")
for _, lim in ipairs({ 8192, 16384, 32768 }) do
  local g = blocks(lim)
  measure("blocks " .. lim, g, "lzfast")
  measure("blocks " .. lim, g, "deflate")
end

-- 4. память: сколько весит распакованный текст (верхняя граница кэша на блок) и текст всей системы в памяти
if collectgarbage then
  local ok, kb = pcall(collectgarbage, "count")
  if ok and kb then say("lua heap now: %s KB", kb) end
end
say("done")
flush()
os.shutdown()
