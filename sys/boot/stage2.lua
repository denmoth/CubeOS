-- CubeOS, этап 2: загрузчик (D204, D207, docs/16-kernel-integration.md). Запускается этапом 1 как loadfile(path)(ctx).
-- Показывает экран загрузки (boot.splash; позже его подменит экран DE), подгружает модули по одному с отдачей управления,
-- строит CFS, готовит загрузку (boot.new), запускает ядро и ведёт полосу, пока службы не поднимутся и не появится вход.
--
-- ctx (от этапа 1): caps {pixel, color}, mode ("safe" из меню или nil), boot_dir.
-- Для тестов: ctx.root (корень данных CFS, по умолчанию "/"), ctx.console, ctx.power {shutdown, reboot}, ctx.splash (готовый экран).
-- Возвращает nil (питание выключено ядром), либо "recovery", причина (этап 1 откроет восстановление).
-- Ctrl+T не прерывает: нигде нет os.pullEvent и sleep, только pullEventRaw и вызовы ядра.

local ctx = ...
ctx = ctx or {}
local B = ctx.boot_dir or "/cubeos/sys/boot/"

local function now() return os.epoch("utc") / 1000 end

-- этапы и их веса на полосе; реальные цифры лежат в boot.conf (stage_weights), замер каждой загрузки пишется в /cubeos/var/boot.timing
local ORDER = { "libs", "fs", "kernel", "setup", "services", "login" }
local weights = { libs = 0.30, fs = 0.10, kernel = 0.25, setup = 0.05, services = 0.25, login = 0.05 }

local splash
local function report(stage, f, text)
  if not splash then return end
  local sum, before = 0, 0
  for _, n in ipairs(ORDER) do
    if n == stage then before = sum end
    sum = sum + weights[n]
  end
  splash:progress((before + weights[stage] * f) / sum, text)
end

local timing, started = {}, now()
local stage_t = started
local function mark(stage)
  local t = now()
  timing[stage] = (timing[stage] or 0) + (t - stage_t)
  stage_t = t
end

local DIRS = { "/cubeos/sys/services", "/cubeos/sys/cfg", "/cubeos/sys/sec", "/cubeos/var", "/cubeos/shared", "/cubeos/users" }

local function main()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  term.write("Starting CubeOS...")

  local rt = dofile(B .. "runtime.lua")
  local import = rt.import

  -- минимум для экрана, потом он показывается и дальше полоса ведёт загрузку
  rt.preload({ "version", "json5", "boot.splash" })
  local version = import("version")
  splash = ctx.splash or import("boot.splash").new({ caps = ctx.caps, term = term, assets = rt.source .. "/assets", title = version.full() })
  splash:open()
  local json5 = import("json5")
  local conf_text
  do
    local f = fs.open((ctx.root or "") .. "/cubeos/sys/cfg/boot.conf", "r")
    if f then conf_text = f.readAll() f.close() end
  end
  if conf_text then
    local ok, conf = pcall(json5.parse, conf_text)
    if ok and type(conf) == "table" and type(conf.stage_weights) == "table" then
      for k, v in pairs(conf.stage_weights) do
        if weights[k] and tonumber(v) and tonumber(v) > 0 then weights[k] = tonumber(v) end
      end
    end
  end

  local function load(stage, label, names)
    report(stage, 0, label)
    rt.preload(names, function(name, i, n)
      report(stage, i / n, label)
      splash:tick()
    end)
    mark(stage)
  end
  load("libs", "Loading libraries", { "unicode", "sha256", "crc32", "base64", "std.str", "std.path" })
  load("fs", "Loading the filesystem", { "cfs" })
  load("kernel", "Loading the kernel", { "kernel", "kernel.cc", "boot", "boot.console" })

  report("setup", 0, "Preparing the system")
  local cfs, boot = import("cfs"), import("boot")
  local console_mod, cckernel = import("boot.console"), import("kernel.cc")
  local fsys = cfs.new({})
  fsys:mount("/", cfs.host(ctx.root or "/"))
  fsys:mount("/cubeos/tmp", cfs.tmp(65536))
  cfs.install_defaults(fsys)
  for _, dir in ipairs(DIRS) do fsys:mkdir(nil, dir, { parents = true }) end

  local ready = false
  local power = ctx.power or { shutdown = function() os.shutdown() end, reboot = function() os.reboot() end }
  local system
  local b = boot.new({
    fsys = fsys,
    console = ctx.console or console_mod.TermConsole(),
    mode = ctx.mode,
    import = rt.import,
    kernel = { rt = rt.cubic.rt, cubic = rt.cubic, pull = cckernel.pull },
    power = power,
    on_ready = function() ready = true end,
  })
  system = b:start()
  mark("setup")
  if system.mode == "recovery" then
    splash:close()
    return "recovery", system.reason
  end

  -- процесс «bootscreen»: ведёт полосу по состоянию служб, по готовности входа закрывает экран
  system.kernel:spawn(function(sys)
    report("services", 0, "Starting services")
    while not ready do
      local total, up = 0, 0
      for _, e in ipairs(system.services:list()) do
        total = total + 1
        if e.state ~= "starting" and e.state ~= "stopped" then up = up + 1 end
      end
      report("services", total == 0 and 1 or up / total, "Starting services")
      splash:tick()
      sys.sleep(0.05)
    end
    mark("services")
    report("login", 0, "Ready")
    splash:done(sys.sleep)
    splash:close()
    mark("login")
    timing.total = now() - started
    pcall(function()
      fsys:write_file(nil, "/cubeos/var/boot.timing", json5.stringify({ total = timing.total, stages = timing }, { json5 = true, indent = 2 }) .. "\n")
    end)
  end, {}, { name = "bootscreen", subject = system.subject })

  local ok, err = pcall(function() system.kernel:run() end)
  if not ok then return "recovery", "kernel stopped: " .. tostring(err) end
  return nil
end

local ok, res, why = xpcall(main, function(e) return tostring(e) end)
if ok then return res, why end
if splash then
  splash:error(res .. "\n\nPress any key to open recovery.")
  repeat local e = os.pullEventRaw() until e == "key"
  splash:close()
end
return "recovery", res
