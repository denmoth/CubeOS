-- Автоматическая отдача управления: код, скомпилированный с yield, периодически вызывает rt.tick()
-- Called by tests/run.lua as: chunk(cubic, ROOT, record)
local cubic, ROOT, record = ...
local rt = cubic.rt

local function check(name, cond, detail)
  record("yield: " .. name, cond and true or false, tostring(detail or ""))
end

local src = table.concat({
  "total = 0",
  "for i in range[1, 1000]:",
  "    total += i",
  "n = 0",
  "while n < 600:",
  "    n += 1",
  "result = total + n",
}, "\n")

-- без опции вызовов slice нет
local plain = cubic.compile(src, "p.cub", {})
check("no ticks without the option", plain:find("__rt.tick", 1, true) == nil)

local lua = cubic.compile(src, "p.cub", { yield = true })
check("ticks with the option", lua:find("__rt.tick()", 1, true) ~= nil)
check("counter declared", lua:find("local __s = 0", 1, true) ~= nil)

local minified = cubic.compile(src, "p.cub", { yield = true, minify = true })
check("works minified", minified:find("__rt.tick()", 1, true) ~= nil)

local function run(code)
  local fn = assert(load(code, "=p", "t", _G))
  return fn(rt, function() end)
end

-- режим ядра: hook вызывается, когда квант исчерпан
local calls = 0
rt.slice_hook = function(now)
  calls = calls + 1
  rt.slice_t0 = now
end
rt.slice_ms = 0
rt.slice_t0 = 0
run(lua)
check("hook called by loops", calls >= 6, calls)

-- квант ещё не исчерпан: hook не вызывается
calls = 0
rt.slice_ms = 1e12
rt.slice_t0 = rt.clock_ms()
run(lua)
check("hook not called inside the slice", calls == 0, calls)
rt.slice_hook = nil

-- режим без ядра: отдача управления самому CC
rt.native_yields = 0
rt.sys_ms = 0
rt.sys_t0 = 0
run(lua)
check("native yields happen", rt.native_yields >= 6, rt.native_yields)
rt.sys_ms = 2500
rt.native_yields = 0
rt.sys_t0 = rt.clock_ms()
run(lua)
check("no native yield inside the time budget", rt.native_yields == 0, rt.native_yields)

-- чужие события при отдаче управления не теряются
os.queueEvent("my_test_event", 42)
rt.sys_ms = 0
rt.sys_t0 = 0
run(lua)
local ev, value = os.pullEventRaw("my_test_event")
check("foreign events survive a native yield", ev == "my_test_event" and value == 42, tostring(ev) .. " " .. tostring(value))
rt.sys_ms = 2500
rt.sys_t0 = rt.clock_ms()
