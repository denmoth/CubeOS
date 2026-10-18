-- Сборка пакетов (docs/packages/03-build.md). Запуск в CraftOS-PC (tools/build_packages.sh) или в Actions Cobble.
--   loadfile('/repo/tools/build_packages.lua')()                 вся система: packages/system/*.json5 -> build/packages/
--                                                                 (.cpk, .entry.json5 и index.json5 для источника path)
--   loadfile('/cubeos/tools/build_packages.lua')(src, out)        каждая подпапка src с package.json5 -> out (так собирает Cobble)
-- Корень репозитория берётся из пути этого файла.
local args = { ... }
local self_path = (debug and debug.getinfo and debug.getinfo(1, "S").source or "@/repo/tools/build_packages.lua"):gsub("^@", "")
local ROOT = self_path:match("^(.*)/tools/[^/]+$") or "/repo"
if ROOT:sub(1, 1) ~= "/" then ROOT = "/" .. ROOT end

local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
local loader = cubic.new_loader({ roots = { ROOT .. "/lib" } })
local pack, json5 = loader.import("stew.pack"), loader.import("json5")

local function breathe() os.queueEvent("bp"); os.pullEvent("bp") end
local function read(p) local f = fs.open(p, "rb"); if not f then return nil end local s = f.readAll(); f.close(); return s end
local function write(p, d) fs.makeDir(fs.getDir(p)); local f = fs.open(p, "wb"); f.write(d); f.close() end

local log = {}
local function say(s) log[#log + 1] = s; print(s); write(ROOT .. "/build/build-packages.txt", table.concat(log, "\n") .. "\n") end
local failed = 0

local function build_one(base, opts)
  local ok, r = pcall(pack.build, fs, base, opts)
  if not ok then
    failed = failed + 1
    say("FAIL " .. (opts.label or base) .. ": " .. tostring(r))
    return nil
  end
  return r
end

local out_dir
if args[1] then
  -- режим Cobble: подпапки с package.json5
  local src = args[1]
  out_dir = args[2] or "/work/out"
  local names = fs.list(src)
  table.sort(names)
  for _, name in ipairs(names) do
    local base = fs.combine(src, name)
    if fs.isDir(base) and fs.exists(fs.combine(base, "package.json5")) then
      local r = build_one(base, { cubic = cubic, label = name, on_block = breathe, on_step = breathe })
      if r then
        pack.write(fs, r, out_dir)
        say(string.format("ok   %s  %d bytes (%d installed)", r.name, #r.data, r.manifest.installed_size))
      end
      breathe()
    end
  end
else
  -- вся система из репозитория
  out_dir = ROOT .. "/build/packages"
  if fs.exists(out_dir) then fs.delete(out_dir) end
  local list = {}
  for _, top in ipairs({ "assets", "lib", "src", "sys" }) do
    for _, rel in ipairs(pack.list_files(fs, ROOT .. "/" .. top)) do list[#list + 1] = top .. "/" .. rel end
  end
  local index = { format = 1, packages = {} }
  local names = fs.list(ROOT .. "/packages/system")
  table.sort(names)
  local total, total_raw = 0, 0
  for _, name in ipairs(names) do
    if name:match("%.json5$") then
      local text = read(ROOT .. "/packages/system/" .. name)
      local t0 = os.epoch("utc")
      local r = build_one(ROOT, { cubic = cubic, manifest_text = text, list = list, label = name,
        on_block = breathe, on_step = breathe, source = "CubeOS repo" })
      if r then
        local cpk_path = pack.write(fs, r, out_dir)
        local e = r.entry
        local p = index.packages[e.id] or {
          name = e.name, description = e.description, author = e.author, kind = e.kind, category = e.category,
          priority = e.priority, homepage = e.homepage, versions = {},
        }
        local v = {}
        for k, val in pairs(e) do
          if k ~= "id" and k ~= "name" and k ~= "description" and k ~= "author" and k ~= "kind" and k ~= "category"
            and k ~= "priority" and k ~= "homepage" and k ~= "version" then v[k] = val end
        end
        v.url = fs.getName(cpk_path)
        p.versions[e.version] = v
        index.packages[e.id] = p
        total, total_raw = total + #r.data, total_raw + r.manifest.installed_size
        say(string.format("ok   %-28s %7d bytes (%d installed) %d ms", r.name, #r.data, r.manifest.installed_size, os.epoch("utc") - t0))
      end
      breathe()
    end
  end
  write(out_dir .. "/index.json5", json5.stringify(index, { json5 = true, indent = 2 }) .. "\n")
  say(string.format("total %d bytes packed, %d installed", total, total_raw))
end
say(failed == 0 and "build ok" or ("build FAILED: " .. failed))
write(ROOT .. "/build/build-packages.txt", table.concat(log, "\n") .. "\n")
if not args[1] then os.shutdown() end
