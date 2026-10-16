-- Запуск тестов Cubic внутри CraftOS-PC.
-- Каждый tests/cases/NAME.cub может иметь файлы:
--   NAME.out      : ожидаемый вывод print (точное совпадение)
--   NAME.err      : подстрока ожидаемой ошибки компиляции
--   NAME.rterr    : подстрока ожидаемой ошибки времени выполнения
--   NAME.exports  : отсортированные имена экспортов через пробел
--   NAME.opts     : опции компиляции, по одной в строке (minify, keep_comments)
--   NAME.luahas   : строки, которые должны встретиться в сгенерированном Lua (по одной в строке)
--   NAME.luahasnot: строки, которых там быть не должно
--   NAME.loader   : наличие файла включает настоящий загрузчик модулей (lib/ и tests/modules/)
-- Каждый тест без .err и .rterr дополнительно прогоняется с минификацией (имя "min:NAME").
-- Результат пишется в /repo/build/test-result.txt (второй аргумент раннера: другое имя файла в build/, для одновременных прогонов)

local ROOT = "/repo"
-- В игре (CUBIC_GAME_TEST = true): компьютер не выключается, между тестами есть yield (иначе CC убьёт долгий код),
-- результаты дописываются в /repo/build/progress.txt по мере выполнения.
local IN_GAME = rawget(_G, "CUBIC_GAME_TEST") == true
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")

local function read(path)
  local f = fs.open(path, "rb")
  if not f then return nil end
  local s = f.readAll()
  f.close()
  return s
end

local function lines_of(text)
  local r = {}
  if text then
    for line in text:gmatch("[^\n]+") do r[#r + 1] = line end
  end
  return r
end

local results, failed, passed = {}, 0, 0

local function record(name, ok, detail)
  if IN_GAME then
    local pf = fs.open(ROOT .. "/build/progress.txt", "a")
    if pf then
      pf.write((ok and "ok    " or "FAIL  ") .. name .. (ok and "" or ("\n" .. tostring(detail))) .. "\n")
      pf.close()
    end
  end
  if ok then
    passed = passed + 1
    results[#results + 1] = "ok    " .. name
  else
    failed = failed + 1
    results[#results + 1] = "FAIL  " .. name .. "\n" .. detail
  end
end

local function run_case(name, label, force)
  -- между тестами отдаём управление: иначе весь прогон идёт без yield и CC (в игре и в эмуляторе) убивает его за «Too long without yielding»
  collectgarbage()
  os.queueEvent("cubic_yield")
  os.pullEvent("cubic_yield")
  local base = ROOT .. "/tests/cases/" .. name
  local src = read(base .. ".cub")
  local want_out = read(base .. ".out")
  local want_err = read(base .. ".err")
  local want_rterr = read(base .. ".rterr")
  local want_exports = read(base .. ".exports")
  local luahas = lines_of(read(base .. ".luahas"))
  local luahasnot = lines_of(read(base .. ".luahasnot"))

  local opts = {}
  for _, o in ipairs(lines_of(read(base .. ".opts"))) do
    local k, v = o:match("^([%w_]+)=(.*)$")
    if k == "mods" then
      opts.mods = {}
      for id in v:gmatch("[^,]+") do opts.mods[#opts.mods + 1] = id end
    elseif k then
      opts[k] = v
    else
      opts[o] = true
    end
  end
  for k, v in pairs(force or {}) do opts[k] = v end

  local buf = {}
  opts.env = setmetatable({
    print = function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      buf[#buf + 1] = table.concat(parts, "\t")
    end,
    cubic_host = cubic,  -- для тестов, которым нужен сам компилятор (rt, load)
    -- тесты не должны трогать настоящую периферию (в игре у компьютера есть монитор, колонка, принтер)
    peripheral = {
      find = function() return nil end,
      wrap = function() return nil end,
      getNames = function() return {} end,
      getType = function() return nil end,
      isPresent = function() return false end,
    },
  }, { __index = _G })
  opts.import = function(p) return { path = p } end
  if fs.exists(base .. ".loader") then
    local L = cubic.new_loader({
      roots = { ROOT .. "/lib", ROOT .. "/tests/modules" },
      aliases = { m = ROOT .. "/tests/modules" },
      env = opts.env,
    })
    opts.import = L.import_for(ROOT .. "/tests/cases")
    opts.loader = L
    opts.base_dir = ROOT .. "/tests/cases"
    opts.header_cache = ROOT .. "/build/cuh-cache"
  end

  local ok, runner, lua = pcall(cubic.load, src, name .. ".cub", opts)
  if want_err then
    if ok then return record(label, false, "expected a compile error containing: " .. want_err:gsub("\n$", "")) end
    local msg = tostring(runner)
    local needle = want_err:gsub("\n$", "")
    if msg:find(needle, 1, true) then return record(label, true) end
    return record(label, false, "compile error mismatch\n  want: " .. needle .. "\n  got:  " .. msg)
  end
  if not ok then
    return record(label, false, "compile error: " .. tostring(runner))
  end
  for _, s in ipairs(luahas) do
    if not lua:find(s, 1, true) then return record(label, false, "generated Lua should contain: " .. s .. "\n" .. lua) end
  end
  for _, s in ipairs(luahasnot) do
    if lua:find(s, 1, true) then return record(label, false, "generated Lua should not contain: " .. s .. "\n" .. lua) end
  end
  local rok, rerr = pcall(runner)
  if want_rterr then
    local needle = want_rterr:gsub("\n$", "")
    if rok then return record(label, false, "expected a runtime error containing: " .. needle) end
    if tostring(rerr):find(needle, 1, true) then return record(label, true) end
    return record(label, false, "runtime error mismatch\n  want: " .. needle .. "\n  got:  " .. tostring(rerr))
  end
  if not rok then
    return record(label, false, "runtime error: " .. tostring(rerr) .. "\n--- generated Lua ---\n" .. tostring(lua))
  end
  if want_exports then
    local keys = {}
    for k in pairs(rerr or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    local got_exports = table.concat(keys, " ")
    local want = want_exports:gsub("\n$", "")
    if got_exports ~= want then
      return record(label, false, "exports mismatch\n  want: " .. want .. "\n  got:  " .. got_exports)
    end
  end
  local got = table.concat(buf, "\n")
  if got ~= "" then got = got .. "\n" end
  if want_out == nil then
    if #luahas > 0 or #luahasnot > 0 then return record(label, true) end
    return record(label, false, "missing .out file; actual output:\n" .. got)
  end
  if got == want_out then return record(label, true) end
  return record(label, false, "output mismatch\n--- want ---\n" .. want_out .. "--- got ---\n" .. got .. "--- generated Lua ---\n" .. tostring(lua))
end

local names = {}
for _, f in ipairs(fs.list(ROOT .. "/tests/cases")) do
  local n = f:match("^(.+)%.cub$")
  if n then names[#names + 1] = n end
end
table.sort(names)

-- аргумент: подстрока имени, либо «=имя1,имя2,...» (точный список; «=unit» это только unit-тесты, «=:» ничего из cases)
local only, out_name = ...
local exact
if only and only:sub(1, 1) == "=" then
  exact = {}
  for n in only:sub(2):gmatch("[^,]+") do exact[n] = true end
  only = nil
end
local timings = {}
for _, n in ipairs(names) do
  if (exact and exact[n]) or (not exact and (not only or n:find(only, 1, true))) then
    local t0 = os.epoch("utc")
    local ok, err = pcall(run_case, n, n)
    if not ok then record(n, false, "test runner error: " .. tostring(err)) end
    local has_err = fs.exists(ROOT .. "/tests/cases/" .. n .. ".err") or fs.exists(ROOT .. "/tests/cases/" .. n .. ".rterr")
    if not has_err then
      local ok2, err2 = pcall(run_case, n, "min:" .. n, { minify = true })
      if not ok2 then record("min:" .. n, false, "test runner error: " .. tostring(err2)) end
    end
    timings[#timings + 1] = { n, os.epoch("utc") - t0 }
  end
end

-- unit-тесты на Lua: tests/unit/*.lua вызываются как chunk(cubic, ROOT, record)
if (exact and exact.unit) or (not exact and (not only or ("unit"):find(only, 1, true))) then
  if fs.isDir(ROOT .. "/tests/unit") then
    for _, f in ipairs(fs.list(ROOT .. "/tests/unit")) do
      if f:match("%.lua$") then
        local fn, lerr = loadfile(ROOT .. "/tests/unit/" .. f)
        if not fn then
          record("unit:" .. f, false, tostring(lerr))
        else
          local ok, err = pcall(fn, cubic, ROOT, function(name, passed, detail)
            record("unit:" .. name, passed, detail)
          end)
          if not ok then record("unit:" .. f, false, tostring(err)) end
        end
      end
    end
  end
end

-- самые медленные тесты (мс), чтобы замечать, что прогон разбухает
table.sort(timings, function(a, b) return a[2] > b[2] end)
local tf = fs.open(ROOT .. "/build/test-timing.txt", "w")
if tf then
  for i = 1, math.min(15, #timings) do tf.write(timings[i][1] .. " " .. timings[i][2] .. " ms\n") end
  tf.close()
end

local out = fs.open(ROOT .. "/build/" .. (out_name or "test-result.txt"), "w")
out.write(table.concat(results, "\n") .. "\n\n" .. passed .. " passed, " .. failed .. " failed\n")
out.close()
if not IN_GAME then os.shutdown() end
