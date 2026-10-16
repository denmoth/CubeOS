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

-- этапы и их веса на полосе. Замер каждой загрузки пишется в /cubeos/var/boot.timing, и следующая загрузка берёт веса из него:
-- полоса идёт ровно по времени, а не рывками. boot.conf (stage_weights) задаёт веса вручную и важнее замера.
local ORDER = { "libs", "fs", "kernel", "system", "shell", "setup", "services", "login" }
local weights = { libs = 0.20, fs = 0.08, kernel = 0.15, system = 0.10, shell = 0.17, setup = 0.05, services = 0.20, login = 0.05 }

local splash, rt, booted
-- подписи экрана на языке системы (locale.conf: lang), из boot.lang языкового пакета
local boot_tr = {}
local function tr(s) return boot_tr[s] or s end
local function load_boot_lang(json5, assets)
  pcall(function()
    local f = fs.open((ctx.root or "") .. "/cubeos/sys/cfg/locale.conf", "r")
    if not f then return end
    local conf = json5.parse(f.readAll())
    f.close()
    local lang = type(conf) == "table" and conf.lang
    if type(lang) ~= "string" or lang == "en" or not lang:match("^[%w_%-]+$") then return end
    for _, root in ipairs({ assets .. "/lang", (ctx.root or "") .. "/cubeos/share/lang" }) do
      local h = fs.open(root .. "/" .. lang .. "/boot.lang", "r")
      if h then
        local id
        local function unq(s) return (s:gsub('\\"', '"'):gsub("\\n", "\n")) end
        for line in h.readAll():gmatch("[^\n]+") do
          local a = line:match('^msgid%s+"(.*)"%s*$')
          local b = line:match('^msgstr%s+"(.*)"%s*$')
          if a then id = unq(a) elseif b and id then if b ~= "" then boot_tr[id] = unq(b) end id = nil end
        end
        h.close()
        return
      end
    end
  end)
end
local function report(stage, f, text)
  if not splash then return end
  text = text and tr(text)
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

-- журнал загрузки /cubeos/var/log/boot.log: пишется с первой секунды (до logd), переживает сбой; прошлый уходит в boot.log.1.
-- Строка как в logd: «время уровень boot текст». logd потом кладёт эти же строки в system.log (system.bootlog).
local bootlog = {}
local blog_path = (ctx.root or "") .. "/cubeos/var/log/boot.log"
local blog_rotated = false
local blog_stamp   -- местное время по time.conf, когда библиотеки уже загружены (до этого UTC)
local function blog(level, text)
  bootlog[#bootlog + 1] = { ms = os.epoch("utc"), level = level, text = tostring(text) }
end
local function blog_flush()
  pcall(function()
    local dir = fs.getDir(blog_path)
    if not fs.exists(dir) then fs.makeDir(dir) end
    if not blog_rotated then
      blog_rotated = true
      if fs.exists(blog_path) then
        if fs.exists(blog_path .. ".1") then fs.delete(blog_path .. ".1") end
        fs.move(blog_path, blog_path .. ".1")
      end
    end
    local f = fs.open(blog_path, "w")
    for _, r in ipairs(bootlog) do
      f.write((blog_stamp and blog_stamp(r.ms) or os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(r.ms / 1000))) .. " " .. r.level .. " boot " .. r.text:gsub("[\r\n]+", " ") .. "\n")
    end
    f.close()
  end)
end

local function reset_screen()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
end

local function main()
  -- до экрана загрузки только чёрный экран (первый кадр системы это уже экран загрузки)
  reset_screen()
  blog("info", "stage 2 started (pixel=" .. tostring(ctx.caps and ctx.caps.pixel) .. ", mode=" .. tostring(ctx.mode or "normal") .. ")")
  for _, n in ipairs(ctx.notes or {}) do blog("info", n) end

  rt = dofile(B .. "runtime.lua")
  local import = rt.import

  -- минимум для экрана, потом он показывается и дальше полоса ведёт загрузку
  rt.preload({ "version", "json5", "boot.splash" })
  local version = import("version")
  splash = ctx.splash or import("boot.splash").new({ caps = ctx.caps, term = term, assets = rt.source .. "/assets", title = version.full(), tr = tr })
  splash:open()
  local json5 = import("json5")
  load_boot_lang(json5, rt.source .. "/assets")
  -- веса по прошлой загрузке (финал «login» не считается: он идёт по своему времени)
  pcall(function()
    local f = fs.open((ctx.root or "") .. "/cubeos/var/boot.timing", "r")
    if not f then return end
    local t = json5.parse(f.readAll())
    f.close()
    local st, sum = type(t) == "table" and t.stages, 0
    if type(st) ~= "table" then return end
    for _, n in ipairs(ORDER) do
      if n ~= "login" and tonumber(st[n]) then sum = sum + tonumber(st[n]) end
    end
    if sum <= 0 then return end
    for _, n in ipairs(ORDER) do
      if n ~= "login" and tonumber(st[n]) then weights[n] = math.max(0.02, tonumber(st[n]) / sum) end
    end
    weights.login = 0.02
  end)
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
    blog("info", label .. " ...")
    local t0 = now()
    local count = 0
    rt.preload(names, function(name, i, n)
      count = n
      report(stage, i / n, label)
      splash:tick()
    end)
    mark(stage)
    blog("info", label .. ": " .. count .. " modules in " .. string.format("%.2f", now() - t0) .. " s")
    blog_flush()
  end
  load("libs", "Loading libraries", { "unicode", "sha256", "crc32", "base64", "std.str", "std.path" })
  load("fs", "Loading the filesystem", { "cfs" })
  load("kernel", "Loading the kernel", { "kernel", "kernel.cc", "boot", "boot.console", "crash", "sysfs" })
  -- модули служб подгружаются заранее: иначе они компилировались бы в процессе init одним куском
  load("system", "Loading system services", { "svc.logd", "svc.timed", "svc.devd", "svc.powerd", "svc.crashd", "svc.permd", "svc.notifyd",
    "svc.clipboard", "svc.stub", "svc.fontd", "svc.inputd", "svc.audiod", "svc.netd" })
  -- после входа рабочий стол CDE (D249), если есть CC: Graphics. Полноэкранный терминал: без CC: Graphics, boot.conf de: "tui",
  -- пункт меню загрузки «CubeOS (terminal)» (на одну загрузку) и безопасный режим
  local want_cde = term.setGraphicsMode ~= nil and not ctx.terminal and ctx.mode ~= "safe"
  pcall(function()
    local f = fs.open((ctx.root or "") .. "/cubeos/sys/cfg/boot.conf", "r")
    local text = f and f.readAll() or ""
    if f then f.close() end
    if text:find("de%s*:%s*[\"']tui[\"']") then want_cde = false end
  end)
  if not ctx.shell then
    if want_cde then
      load("shell", "Loading the desktop", { "ui", "term.session", "cde.theme", "cde.window", "cde.wallpaper", "cde.icons", "cde.panel", "cde.compositor",
        "cde.wm", "cde.app", "cde.winout", "cde.terminal", "cdk.style", "cdk.icons", "cdk.widget", "cdk.controls", "cdk.input", "cdk.ui",
        "cdk", "cdk.gallery", "cde.session" })
    else
      load("shell", "Loading the terminal", { "ui", "term.session" })
    end
  end

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
  pcall(function()
    local f = fs.open((ctx.root or "") .. "/cubeos/sys/cfg/time.conf", "r")
    local text = f and f.readAll()
    if f then f.close() end
    local c, logd = import("clock").from_text(text), import("svc.logd")
    blog_stamp = function(ms) return logd.stamp(ms, c) end
  end)
  local system
  local b = boot.new({
    fsys = fsys,
    console = ctx.console or console_mod.TermConsole(),
    mode = ctx.mode,
    import = rt.import,
    shell = ctx.shell or function(session)
      if want_cde and not (session.env and session.env.de == "tui") then
        return import("cde.session").program(session, { assets = rt.source .. "/assets" })
      end
      return import("term.session").program(session, { assets = rt.source .. "/assets" })
    end,
    kernel = { rt = rt.cubic.rt, cubic = rt.cubic, pull = cckernel.pull },
    power = power,
    bootlog = bootlog,
    input_log = ctx.input_log,
    -- службы подняты: экран загрузки закрывается ЗДЕСЬ, до экрана входа (вход идёт в этом же процессе после возврата), и текст чистится,
    -- иначе строки загрузки проступали бы под экраном входа
    on_ready = function(_, ksys)
      ready = true
      mark("services")
      blog("info", "services are up, closing the boot screen")
      pcall(function() report("login", 0, "Ready") splash:done(ksys and ksys.sleep or function() end) end)
      pcall(function() splash:close() end)
      reset_screen()
      mark("login")
      timing.total = now() - started
      blog("info", "boot finished in " .. string.format("%.2f", timing.total) .. " s")
      blog_flush()
      pcall(function()
        fsys:write_file(nil, "/cubeos/var/boot.timing", json5.stringify({ total = timing.total, stages = timing }, { json5 = true, indent = 2 }) .. "\n")
      end)
    end,
  })
  system = b:start()
  booted = true
  blog("info", "boot started: mode " .. tostring(system.mode) .. (system.reason and (" (" .. tostring(system.reason) .. ")") or "") ..
    (system.unclean and ", the previous shutdown was not clean" or ""))
  if ctx.hooks and ctx.hooks.after_start then ctx.hooks.after_start(system) end
  mark("setup")
  blog_flush()
  if system.mode == "recovery" then
    splash:close()
    reset_screen()
    return "recovery", system.reason
  end

  -- процесс «bootscreen»: ведёт полосу по состоянию служб и показывает под ней последние важные строки журнала ядра
  system.kernel:spawn(function(sys)
    report("services", 0, "Starting services")
    local seen = 0
    while not ready do
      local total, up = 0, 0
      for _, e in ipairs(system.services:list()) do
        total = total + 1
        if e.state ~= "starting" and e.state ~= "stopped" then up = up + 1 end
      end
      report("services", total == 0 and 1 or up / total, "Starting services")
      local recs
      recs, seen = system.kernel:records_since(seen)
      for _, r in ipairs(recs) do
        if r.level ~= "debug" then
          blog(r.level, "kernel: " .. r.text)
          pcall(function() splash:message(r.text) end)
        end
      end
      splash:tick()
      sys.sleep(0.05)
    end
    blog_flush()
  end, {}, { name = "bootscreen", subject = system.subject })

  local ok, err = pcall(function() system.kernel:run() end)
  if not ok then
    blog("error", "kernel stopped: " .. tostring(err))
    blog_flush()
    return "recovery", "kernel stopped: " .. tostring(err)
  end
  blog("info", "kernel stopped normally")
  blog_flush()
  return nil
end

local ok, res, why = xpcall(main, function(e) return tostring(e) end)
if ok then return res, why end

-- сбой загрузки: отчёт в /cubeos/var/crash, экран ошибки с кодом причины и отсчётом. Клавиша открывает восстановление;
-- по истечении времени: перезагрузка, если загрузка уже начата (счётчик неудач в boot.state доведёт до безопасного режима и
-- восстановления), иначе восстановление (до начала загрузки счёт вести нечем, перезагрузка зациклилась бы)
local code = "E-????????"
local report_path
blog("crit", "boot failed: " .. tostring(res))
blog_flush()
pcall(function()
  local crash = rt.import("crash")
  local lines = {}
  for _, r in ipairs(bootlog) do lines[#lines + 1] = r.level .. " " .. r.text end
  local r = crash.build({ kind = "boot", error = res }, { log = lines })
  code = r.code
  report_path = crash.write(function(path, text)
    local full = (ctx.root or "") .. path
    fs.makeDir(fs.getDir(full))
    local f = fs.open(full, "w")
    f.write(text)
    f.close()
  end, r)
end)
local delay = ctx.crash_delay or 10
local text = res .. "\n\nReason code " .. code .. (report_path and ("\nReport: " .. report_path) or "")
if splash then
  local pressed = false
  local left = delay
  while true do
    pcall(function()
      splash:error(text .. "\n\n" .. (booted and ("Restarting in " .. left .. " s. ") or "") .. "Press any key to open recovery.")
    end)
    if left <= 0 then break end
    local timer = os.startTimer(1)
    while true do
      local e, a = os.pullEventRaw()
      if e == "key" then pressed = true break end
      if e == "timer" and a == timer then break end
    end
    if pressed then break end
    left = left - 1
  end
  pcall(function() splash:close() end)
  if not pressed and booted then return "reboot" end
end
return "recovery", res
