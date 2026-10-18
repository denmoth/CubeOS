-- Сквозная проверка пакетов (docs/packages): на чистом компьютере CraftOS-PC stew ставит набор из build/packages (источник path),
-- потом загрузчик установленной системы (sys/boot/runtime.lua без /repo и без компилятора) грузит модули ранней загрузки.
-- Запуск: tools/e2e_stew.sh [набор] [storage]. Итог: build/e2e-stew.txt.
local args = { ... }
local SET = args[1] or "cubeos.minimal"
local STORAGE = args[2] or "auto"
local out = {}
local function say(s) out[#out + 1] = tostring(s); local f = fs.open("/repo/build/e2e-stew.txt", "w"); f.write(table.concat(out, "\n") .. "\n"); f.close() end

-- чистый диск: всё, кроме /repo и /rom
for _, name in ipairs(fs.list("/")) do
  if name ~= "repo" and name ~= "rom" then fs.delete("/" .. name) end
end

local cubic = loadfile("/repo/src/cubic/init.lua")("/repo/src/cubic")
local loader = cubic.new_loader({ roots = { "/repo/lib" } })
local stew = loader.import("stew")
local s = stew.new({ fs = fs, root = "/" })
s:save_sources({ { name = "local", kind = "path", url = "/repo/build/packages", trust = "official" } })
local r = s:refresh()
say("refresh: " .. table.concat(r.ok, ",") .. " failed " .. #r.failed)
local p = s:plan({ install = { SET }, storage = STORAGE, no_want = args[3] == "nowant" })
local packed, unpacked = 0, 0
for _, st in ipairs(p.steps) do if st.storage == "packed" then packed = packed + 1 else unpacked = unpacked + 1 end end
say(string.format("plan: ok=%s steps=%d (unpacked %d, packed %d) download=%d delta=%d missing=%s conflicts=%s",
  tostring(p.ok), #p.steps, unpacked, packed, p.download, p.installed_delta, table.concat(p.missing, ";"), table.concat(p.conflicts, ";")))
local t0 = os.epoch("utc")
local res = s:apply(p, {})
say("apply: ok=" .. tostring(res.ok) .. " " .. tostring(res.error or "") .. " in " .. (os.epoch("utc") - t0) .. " ms")
if not res.ok then os.shutdown() return end

local used = 0
local function du(path)
  if fs.isDir(path) then
    local n = 500
    for _, x in ipairs(fs.list(path)) do n = n + du(fs.combine(path, x)) end
    return n
  end
  return math.max(fs.getSize(path), 500)
end
used = du("/cubeos") + du("/startup.lua")
say("disk used (CC counting, 500 B minimum per file and folder): " .. used)
for _, d in ipairs({ "/cubeos/pkg", "/cubeos/share", "/cubeos/sys", "/cubeos/var/stew", "/cubeos/var/stew/cache" }) do
  if fs.exists(d) then say("  " .. d .. ": " .. du(d)) end
end
say("startup.lua: " .. tostring(fs.exists("/startup.lua")) .. ", boot.idx: " .. tostring(fs.exists("/cubeos/var/stew/boot.idx")) ..
  ", rt.lua: " .. tostring(fs.exists("/cubeos/sys/cubic/rt.lua")))

-- загрузчик установленной системы: /repo больше не нужен
local rt = dofile("/cubeos/sys/boot/runtime.lua")
say("runtime installed=" .. tostring(rt.installed) .. " compiler=" .. tostring(rt.has_compiler) .. " source=" .. tostring(rt.source))
local names = { "version", "json5", "cfs", "boot", "boot.auth", "boot.console", "kernel", "kernel.cc", "svc.logd", "clock", "cush.shell", "term.session", "stew" }
local order = rt.plan(names)
say("preload order: " .. #order .. " modules")
local fails = 0
for _, name in ipairs(order) do
  local ok, err = pcall(rt.import, name)
  if not ok then fails = fails + 1; say("  FAIL " .. name .. ": " .. tostring(err)) end
  os.queueEvent("e2e"); os.pullEvent("e2e")
end
say("imports: " .. (#order - fails) .. " ok, " .. fails .. " failed")
-- ошибка в готовом коде показывает строку исходника через карту
local ok, err = pcall(function() rt.import("json5").parse("{ bad") end)
say("error text: " .. tostring(err))
say(fails == 0 and "E2E OK" or "E2E FAILED")
os.shutdown()
