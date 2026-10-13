-- Запуск тестов Cubic внутри CraftOS-PC.
-- Каждый tests/cases/NAME.cub:
--   NAME.out : ожидаемый вывод print (точное совпадение)
--   NAME.err : подстрока ожидаемой ошибки компиляции
--   NAME.rterr : подстрока ожидаемой ошибки времени выполнения
-- Результат пишется в /repo/build/test-result.txt

local ROOT = "/repo"
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")

local function read(path)
  local f = fs.open(path, "rb")
  if not f then return nil end
  local s = f.readAll()
  f.close()
  return s
end

local results, failed, passed = {}, 0, 0

local function record(name, ok, detail)
  if ok then
    passed = passed + 1
    results[#results + 1] = "ok    " .. name
  else
    failed = failed + 1
    results[#results + 1] = "FAIL  " .. name .. "\n" .. detail
  end
end

local function run_case(name)
  local base = ROOT .. "/tests/cases/" .. name
  local src = read(base .. ".cub")
  local want_out = read(base .. ".out")
  local want_err = read(base .. ".err")
  local want_rterr = read(base .. ".rterr")
  local buf = {}
  local env = setmetatable({
    print = function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      buf[#buf + 1] = table.concat(parts, "\t")
    end,
  }, { __index = _G })

  local ok, runner, lua = pcall(cubic.load, src, name .. ".cub", { env = env, import = function(p) return { path = p } end })
  if want_err then
    if ok then return record(name, false, "expected a compile error containing: " .. want_err:gsub("\n$", "")) end
    local msg = tostring(runner)
    local needle = want_err:gsub("\n$", "")
    if msg:find(needle, 1, true) then return record(name, true) end
    return record(name, false, "compile error mismatch\n  want: " .. needle .. "\n  got:  " .. msg)
  end
  if not ok then
    return record(name, false, "compile error: " .. tostring(runner))
  end
  local rok, rerr = pcall(runner)
  local want_exports = read(base .. ".exports")
  if want_rterr then
    local needle = want_rterr:gsub("\n$", "")
    if rok then return record(name, false, "expected a runtime error containing: " .. needle) end
    if tostring(rerr):find(needle, 1, true) then return record(name, true) end
    return record(name, false, "runtime error mismatch\n  want: " .. needle .. "\n  got:  " .. tostring(rerr))
  end
  if not rok then
    return record(name, false, "runtime error: " .. tostring(rerr) .. "\n--- generated Lua ---\n" .. tostring(lua))
  end
  local got = table.concat(buf, "\n")
  if got ~= "" then got = got .. "\n" end
  if want_out == nil then
    return record(name, false, "missing .out file; actual output:\n" .. got)
  end
  if got == want_out then return record(name, true) end
  return record(name, false, "output mismatch\n--- want ---\n" .. want_out .. "--- got ---\n" .. got .. "--- generated Lua ---\n" .. tostring(lua))
end

local names = {}
for _, f in ipairs(fs.list(ROOT .. "/tests/cases")) do
  local n = f:match("^(.+)%.cub$")
  if n then names[#names + 1] = n end
end
table.sort(names)

local only = ...
for _, n in ipairs(names) do
  if not only or n:find(only, 1, true) then
    local ok, err = pcall(run_case, n)
    if not ok then record(n, false, "test runner error: " .. tostring(err)) end
  end
end

local out = fs.open(ROOT .. "/build/test-result.txt", "w")
out.write(table.concat(results, "\n") .. "\n\n" .. passed .. " passed, " .. failed .. " failed\n")
out.close()
os.shutdown()
