-- Проверки и замеры Cubic в настоящем CC. На компьютере: /repo/game/bench.lua
-- Результаты печатаются и сразу дописываются в /repo/build/bench-result.txt (на случай, если компьютер упадёт).
local ROOT = "/repo"
if not fs.exists(ROOT .. "/build") then fs.makeDir(ROOT .. "/build") end
local RESULT = ROOT .. "/build/bench-result.txt"
if fs.exists(RESULT) then fs.delete(RESULT) end

local function say(line)
  print(line)
  local f = fs.open(RESULT, "a")
  if f then
    f.write(line .. "\n")
    f.close()
  end
end

local function now() return os.epoch("utc") end

local function mem()
  local ok, kb = pcall(collectgarbage, "count")
  if ok and type(kb) == "number" then return kb end
  return nil
end

local function yield()
  os.queueEvent("bench_y")
  os.pullEvent("bench_y")
end

local function read(path)
  local f = fs.open(path, "rb")
  if not f then return nil end
  local s = f.readAll()
  f.close()
  return s
end

-- Выполняет fn повторно не дольше budget секунд (с yield между повторами). Возвращает повторы, секунды.
local function loop(fn, budget)
  local start = now()
  local n = 0
  repeat
    fn()
    n = n + 1
    yield()
  until (now() - start) >= budget * 1000
  return n, (now() - start) / 1000
end

local function timed(label, fn)
  local t0 = now()
  local ok, res = pcall(fn)
  local ms = now() - t0
  if ok then
    say(string.format("%-34s %7d ms", label, ms))
  else
    say(string.format("%-34s ERROR: %s", label, tostring(res)))
  end
  yield()
  return ok, res
end

say("== Cubic in-game check ==")
say("host: " .. tostring(_HOST))
say("lua: " .. tostring(_VERSION) .. ", bit32: " .. tostring(bit32 ~= nil) .. ", utf8: " .. tostring(utf8 ~= nil))
say("computer id: " .. tostring(os.getComputerID()) .. ", free space: " .. tostring(fs.getFreeSpace("/")))
local m0 = mem()
say("memory at start: " .. tostring(m0 and math.floor(m0)) .. " KB")
local names = {}
for _, n in ipairs(peripheral.getNames()) do names[#names + 1] = n .. "=" .. tostring(peripheral.getType(n)) end
say("peripherals: " .. (#names > 0 and table.concat(names, ", ") or "none"))
say("term graphics: " .. tostring(term.setGraphicsMode ~= nil) .. ", term size: " .. table.concat({ term.getSize() }, "x"))

-- 1. goto (используется для continue)
say("")
say("-- language features of the host --")
local goto_fn, goto_err = load("local s = 0 for i = 1, 5 do if i == 3 then goto continue end s = s + i ::continue:: end return s", "goto", "t", {})
if goto_fn then
  local ok, v = pcall(goto_fn)
  say("goto/continue: " .. (ok and ("works, result " .. tostring(v) .. " (expected 12)") or ("load ok, run error " .. tostring(v))))
else
  say("goto/continue: NOT SUPPORTED: " .. tostring(goto_err))
end
local fn53 = load("return 7 // 2", "idiv", "t", {})
say("integer division // in host Lua: " .. tostring(fn53 ~= nil))
say("string.pack: " .. tostring(string.pack ~= nil) .. ", table.unpack: " .. tostring(table.unpack ~= nil) .. ", unpack: " .. tostring(unpack ~= nil))

-- 2. загрузка компилятора
say("")
say("-- compiler --")
local cubic
local ok = timed("load compiler (init + modules)", function()
  cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
end)
if not ok then return end
local m1 = mem()
say("memory after load: " .. tostring(m1 and math.floor(m1)) .. " KB (+" .. tostring(m0 and m1 and math.floor(m1 - m0)) .. ")")

local src = read(ROOT .. "/lib/json5.cub")
say("sample: lib/json5.cub, " .. #src .. " bytes")
local compiled
timed("compile (plain)", function() compiled = cubic.compile(src, "json5.cub", {}) end)
timed("compile (plain, second run)", function() cubic.compile(src, "json5.cub", {}) end)
timed("compile (--minify)", function() cubic.compile(src, "json5.cub", { minify = true }) end)
timed("compile (--strict, first: headers)", function() cubic.compile(src, "json5.cub", { strict = true }) end)
timed("compile (--strict, second)", function() cubic.compile(src, "json5.cub", { strict = true }) end)
say("compiled size: " .. tostring(compiled and #compiled) .. " bytes")
local m2 = mem()
say("memory after compiles: " .. tostring(m2 and math.floor(m2)) .. " KB")

-- 3. редакторские функции
say("")
say("-- editor tooling --")
local T = cubic.tooling
timed("highlight (whole file)", function() T.highlight(src) end)
timed("symbols (whole file)", function() T.symbols(src) end)
local sample = "class Box:\n    def init(self):\n        self.size = 3\n    def grow(self, by: num) -> num:\n        return self.size + by\nb = Box()\nb."
timed("complete after 'b.' (first)", function() T.complete(sample, 7, 3, {}) end)
timed("complete after 'b.' (second)", function() T.complete(sample, 7, 3, {}) end)
timed("diagnostics (whole file)", function() T.diagnostics(src, "json5.cub", {}) end)

-- 4. библиотеки: скорость
say("")
say("-- library speed --")
local loader = cubic.new_loader({ roots = { ROOT .. "/lib" } })
local function lib(name)
  local mod
  local t0 = now()
  local ok2, err = pcall(function() mod = loader.import(name) end)
  if not ok2 then say("import " .. name .. ": ERROR " .. tostring(err)) return nil end
  say(string.format("import %-28s %7d ms (compile + run)", name, now() - t0))
  yield()
  return mod
end

local sha = lib("sha256")
if sha then
  local data = string.rep("abcdefghij", 100) -- 1000 байт
  local n, secs = loop(function() sha.hex(data) end, 3)
  say(string.format("sha256: %.1f KB/s (%d x 1 KB in %.1f s)", n / secs, n, secs))
  local pn, psecs = loop(function() sha.pbkdf2("password", "salt", 20) end, 3)
  say(string.format("pbkdf2: %.0f rounds/s (so 1000 rounds take about %.1f s)", pn * 20 / psecs, 1000 / (pn * 20 / psecs)))
end

local crc = lib("crc32")
if crc then
  local data = string.rep("abcdefghij", 1600) -- 16 КБ
  local n, secs = loop(function() crc.crc32(data) end, 2)
  say(string.format("crc32: %.0f KB/s", n * 16 / secs))
end

local text = read(ROOT .. "/lib/json5.cub") or ""
local lz = lib("lzfast")
if lz then
  local packed
  local n, secs = loop(function() packed = lz.compress(text) end, 2)
  say(string.format("lzfast compress: %.0f KB/s, ratio %.1f%% (%d -> %d)", n * #text / 1024 / secs, 100 * #packed / #text, #text, #packed))
  local n2, secs2 = loop(function() lz.decompress(packed) end, 2)
  say(string.format("lzfast decompress: %.0f KB/s", n2 * #text / 1024 / secs2))
end

local df = lib("deflate")
if df then
  local sample_text = text:sub(1, 8192)
  local packed
  local n, secs = loop(function() packed = df.deflate(sample_text) end, 3)
  say(string.format("deflate compress: %.1f KB/s, ratio %.1f%% (%d -> %d)", n * #sample_text / 1024 / secs, 100 * #packed / #sample_text, #sample_text, #packed))
  local n2, secs2 = loop(function() df.inflate(packed) end, 3)
  say(string.format("inflate: %.1f KB/s", n2 * #sample_text / 1024 / secs2))
end

local js = lib("json5")
if js then
  local doc = '{"name": "demo", "list": [1, 2, 3, {"a": true, "b": null}], "text": "' .. string.rep("lorem ipsum ", 50) .. '"}'
  local n, secs = loop(function() js.parse(doc) end, 2)
  say(string.format("json5 parse: %.0f docs/s (%d bytes each)", n / secs, #doc))
end

-- 5. итог по памяти
local m3 = mem()
say("")
say("memory at end: " .. tostring(m3 and math.floor(m3)) .. " KB")
say("== done ==")
