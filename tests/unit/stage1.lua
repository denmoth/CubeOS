-- Этап 1 загрузки, восстановление и runtime (sys/boot/*.lua) на подставных os/fs/term
-- Called by tests/run.lua as: chunk(cubic, ROOT, record)
local cubic, ROOT, record = ...

local function check(name, cond, detail)
  record("stage1: " .. name, cond and true or false, tostring(detail or ""))
end

local function slurp(path)
  local f = fs.open(path, "rb")
  local s = f.readAll()
  f.close()
  return s
end

local SRC = {
  stage1 = slurp(ROOT .. "/sys/boot/stage1.lua"),
  rescue = slurp(ROOT .. "/sys/boot/rescue.lua"),
  startup = slurp(ROOT .. "/sys/startup.lua"),
}
local B = "/cubeos/sys/boot/"

-- Окружение: files {путь = текст}, loaders {путь = функция(ctx) или текст "stage1"/"rescue" для настоящих файлов},
-- events: очередь событий (строки или таблицы; {"timer"} получает id последнего запущенного таймера), reads: ответы read().
local function world(o)
  local w = { out = {}, files = o.files or {}, events = o.events or {}, reads = o.reads or {}, timers = 0, last = 0 }
  local env
  local function chunk(name, src)
    local fn, err = load(src, "=" .. name, "t", env)
    assert(fn, err)
    return fn
  end
  w.term = setmetatable({
    isColor = function() return false end,
    getSize = function() return 51, 19 end,
    clear = function() w.out[#w.out + 1] = "<clear>" end,
    clearLine = function() end,
    setCursorPos = function() end,
    setTextColor = function() end,
    setBackgroundColor = function() end,
    write = function(s) w.out[#w.out + 1] = tostring(s) end,
  }, { __index = o.graphics and { setGraphicsMode = function() end } or nil })
  w.os = {
    pullEventRaw = function()
      local e = table.remove(w.events, 1)
      if e == nil then error("test: event queue is empty", 0) end
      if type(e) == "string" then e = { e } end
      if e[1] == "timer" and e[2] == nil then return "timer", w.last end
      if e[1] == "key" and type(e[2]) == "string" then return "key", keys[e[2]] end
      return table.unpack(e)
    end,
    startTimer = function() w.timers = w.timers + 1; w.last = w.timers; return w.timers end,
  }
  w.fs = {
    open = function(path)
      local text = w.files[path]
      if text == nil then return nil end
      return { readAll = function() return text end, close = function() end }
    end,
    exists = function(path) return w.files[path] ~= nil end,
  }
  env = setmetatable({
    os = w.os, fs = w.fs, term = w.term, colors = colors, keys = keys,
    print = function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      w.out[#w.out + 1] = table.concat(parts, " ")
    end,
    write = function(s) w.out[#w.out + 1] = tostring(s) end,
    read = function() return table.remove(w.reads, 1) end,
    sleep = function() end,
    loadfile = function(path)
      local l = o.loaders and o.loaders[path]
      if l == "rescue" then return chunk("rescue", SRC.rescue) end
      if type(l) == "function" then return l end
      return nil, path .. ": No such file"
    end,
  }, { __index = _G })
  w.run = function(name) return chunk(name, SRC[name])() end
  w.text = function() return table.concat(w.out, "\n") end
  return w
end

local function rescue_stub(log)
  return function(arg) log[#log + 1] = arg; return "reboot" end
end

-- 1. без клавиш: окно истекает, запускается загрузчик с контекстом
do
  local seen
  local w = world({ events = { { "timer" } }, graphics = true,
    loaders = { [B .. "stage2.lua"] = function(ctx) seen = ctx; return nil end } })
  local r = w.run("stage1")
  check("plain boot returns nil", r == nil, r)
  check("loader got caps", seen and seen.caps.pixel == true and seen.caps.color == false)
  check("normal mode has no override", seen and seen.mode == nil and seen.menu == false)
  check("hint is shown", w.text():find("F2: menu", 1, true) ~= nil)
end

-- 2. Ctrl+T (terminate) во время окна и меню ничего не ломает
do
  local seen
  local w = world({ events = { "terminate", { "timer" } },
    loaders = { [B .. "stage2.lua"] = function(ctx) seen = ctx end } })
  w.run("stage1")
  check("terminate is ignored in the key window", seen ~= nil)
end

-- 3. F2 открывает меню; Enter запускает обычную загрузку
do
  local seen
  local w = world({ events = { { "key", "f2" }, { "key", "enter" } }, loaders = { [B .. "stage2.lua"] = function(ctx) seen = ctx end } })
  w.run("stage1")
  check("menu is drawn", w.text():find("CubeOS boot menu", 1, true) ~= nil)
  check("F2 then Enter boots normally", seen and seen.mode == nil and seen.menu == true)
end

-- 4. F2, вниз, Enter: безопасный режим
do
  local seen
  local w = world({ events = { { "key", "f2" }, { "key", "down" }, { "key", "enter" } },
    loaders = { [B .. "stage2.lua"] = function(ctx) seen = ctx end } })
  w.run("stage1")
  check("safe mode is passed to the loader", seen and seen.mode == "safe")
end

-- 5. Ctrl в окне: восстановление (настоящий rescue.lua; без учётных записей открыто, пункт 3 выключает)
do
  local w = world({ events = { { "key", "leftCtrl" } }, reads = { "3" }, loaders = { [B .. "rescue.lua"] = "rescue" } })
  local r = w.run("stage1")
  check("Ctrl opens recovery", r == "shutdown", r)
  check("recovery prints its title and reason", w.text():find("CubeOS recovery", 1, true) and w.text():find("requested at startup", 1, true))
end

-- 6. сбой загрузчика ведёт в восстановление, а не в CraftOS
do
  local log = {}
  local w = world({ events = { { "timer" } },
    loaders = { [B .. "stage2.lua"] = function() error("boom", 0) end, [B .. "rescue.lua"] = rescue_stub(log) } })
  local r = w.run("stage1")
  check("loader crash goes to rescue", r == "reboot" and log[1] and log[1].reason == "boom", log[1] and log[1].reason)
end

-- 7. загрузчик просит восстановление
do
  local log = {}
  local w = world({ events = { { "timer" } },
    loaders = { [B .. "stage2.lua"] = function() return "recovery", "two failed boots" end, [B .. "rescue.lua"] = rescue_stub(log) } })
  w.run("stage1")
  check("loader can request recovery", log[1] and log[1].reason == "two failed boots")
end

-- 8. загрузчика нет
do
  local log = {}
  local w = world({ events = { { "timer" } }, loaders = { [B .. "rescue.lua"] = rescue_stub(log) } })
  w.run("stage1")
  check("missing loader goes to rescue", log[1] and log[1].reason:find("cannot load the boot loader", 1, true) ~= nil)
end

-- 9. de.conf выбирает загрузчик
do
  local seen
  local w = world({ events = { { "timer" } }, files = { ["/cubeos/sys/cfg/de.conf"] = "{ boot: '/cubeos/de/cde/boot.lua' }" },
    loaders = { ["/cubeos/de/cde/boot.lua"] = function(ctx) seen = true end } })
  w.run("stage1")
  check("de.conf selects the loader", seen == true)
end

-- 10. пункт меню CraftOS: без учётных записей открыт, при отказе возврат в меню
do
  local w = world({ events = { { "key", "f2" }, { "key", "down" }, { "key", "down" }, { "key", "down" }, { "key", "enter" } },
    loaders = { [B .. "rescue.lua"] = "rescue" } })
  local r = w.run("stage1")
  check("CraftOS entry without accounts", r == "craftos", r)
end
do
  local calls, log = 0, {}
  local w = world({ events = { { "key", "f2" }, { "key", "down" }, { "key", "down" }, { "key", "down" }, { "key", "enter" }, { "key", "enter" } },
    loaders = { [B .. "rescue.lua"] = function(arg) calls = calls + 1; log[#log + 1] = arg.gate; return "reboot" end,
      [B .. "stage2.lua"] = function() return "booted" end } })
  local r = w.run("stage1")
  check("failed CraftOS gate returns to the menu", calls == 1 and log[1] == true and r == "booted", tostring(r))
end

-- 11. настройки boot.conf: always, menu_timeout, off, окно 0, своя клавиша, комментарии
do
  local seen
  local w = world({ events = { { "timer" }, { "timer" } }, files = { ["/cubeos/sys/cfg/boot.conf"] = "{ menu: 'always', menu_timeout: 2 }" },
    loaders = { [B .. "stage2.lua"] = function(ctx) seen = ctx end } })
  w.run("stage1")
  check("menu always with auto-select", seen and seen.menu == true and w.text():find("auto in 2 s", 1, true) ~= nil)

  seen = nil
  w = world({ events = {}, files = { ["/cubeos/sys/cfg/boot.conf"] = "{\n  // comment: 1\n  key_window_ms: 0,\n}" },
    loaders = { [B .. "stage2.lua"] = function(ctx) seen = ctx end } })
  w.run("stage1")
  check("zero window skips waiting", seen ~= nil)

  seen = nil
  w = world({ events = { { "key", "f2" }, { "timer" } }, files = { ["/cubeos/sys/cfg/boot.conf"] = "{ menu: \"off\" }" },
    loaders = { [B .. "stage2.lua"] = function(ctx) seen = ctx end } })
  w.run("stage1")
  check("menu off ignores the key", seen and seen.menu == false)

  seen = nil
  w = world({ events = { { "key", "f3" }, { "timer" } }, files = { ["/cubeos/sys/cfg/boot.conf"] = "{ menu_key: 'f3', menu_timeout: 1 }" },
    loaders = { [B .. "stage2.lua"] = function(ctx) seen = ctx end } })
  w.run("stage1")
  check("menu key is configurable", seen and seen.menu == true)
end

-- 12. rescue.lua: с учётными записями без runtime заперто; с runtime пароль решает
do
  local files = { ["/cubeos/sys/cfg/users.conf"] = "{}" }
  local w = world({ files = files, loaders = { [B .. "rescue.lua"] = "rescue" } })
  local r = w.run("rescue")
  check("locked without runtime", r == "reboot" and w.text():find("runtime.lua is missing", 1, true) ~= nil, r)

  local ok_answer = true
  w = world({ files = files, reads = { "1" }, loaders = { [B .. "runtime.lua"] = function() return { recovery_login = function() return ok_answer end } end } })
  r = w.run("rescue")
  check("correct password opens the menu", r == "craftos", r)

  ok_answer = false
  w = world({ files = files, loaders = { [B .. "runtime.lua"] = function() return { recovery_login = function() return ok_answer end } end } })
  r = w.run("rescue")
  check("wrong password restarts", r == "reboot" and w.text():find("Restarting", 1, true) ~= nil, r)
end

-- 13. startup.lua: короткая точка входа
do
  check("startup is short", select(2, SRC.startup:gsub("\n", "")) < 20)
  check("startup uses raw events", SRC.startup:find("os.pullEvent = os.pullEventRaw", 1, true) ~= nil)
  check("stage1 is small", #SRC.stage1 < 6000, #SRC.stage1)
end

-- 14. runtime.recovery_login с настоящими CFS и Auth (временный корень данных)
do
  local root = ROOT .. "/build/rt-root"
  if fs.exists(root) then fs.delete(root) end
  fs.makeDir(root)
  local loader = cubic.new_loader({ roots = { ROOT .. "/lib" } })
  local cfs, auth_mod = loader.import("cfs"), loader.import("boot.auth")
  local fsys = cfs.new({})
  fsys:mount("/", cfs.host(root))
  local a = auth_mod.new(fsys, { rounds = 10 })
  a:create_user({ name = "root" }, "secret", true)

  local rt = loadfile(ROOT .. "/sys/boot/runtime.lua")()
  local function console(answers)
    local c = { lines = {} }
    function c:write_line(t) self.lines[#self.lines + 1] = t end
    function c:read_line() return table.remove(answers, 1) end
    return c
  end
  check("runtime exposes import", type(rt.import) == "function" and rt.source == "/repo")
  check("recovery accepts the right password", rt.recovery_login(console({ "secret" }), { root = root }) == true)
  check("recovery rejects wrong passwords", rt.recovery_login(console({ "a", "b", "c" }), { root = root }) == false)
  fs.delete(root)
  fs.makeDir(root)
  check("recovery is open without accounts", rt.recovery_login(console({}), { root = root }) == true)
  fs.delete(root)
end
