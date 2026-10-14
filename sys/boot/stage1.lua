-- CubeOS, этап 1 загрузки (D204, D207, docs/16-kernel-integration.md). Чистый Lua: без компилятора и библиотек.
-- Вызывается из startup.lua. Результат: nil (выключить), "reboot" или "craftos" (отдать управление оболочке CraftOS).
-- Делает: ждёт клавишу меню (F2) или Ctrl около секунды, показывает меню, выбирает и запускает загрузчик DE,
-- при любом сбое загрузчика уходит в восстановление с паролем (rescue.lua), а не в голый CraftOS.
-- Ctrl+T не прерывает: startup.lua подменяет os.pullEvent на os.pullEventRaw, здесь везде только raw.

local B = "/cubeos/sys/boot/"
local CONF, DE_CONF, USERS = "/cubeos/sys/cfg/boot.conf", "/cubeos/sys/cfg/de.conf", "/cubeos/sys/cfg/users.conf"
local raw = os.pullEventRaw

local function rd(path)
  local f = fs.open(path, "r")
  if not f then return nil end
  local s = f.readAll()
  f.close()
  return s
end

-- значение плоского ключа из JSON5 (хватает для boot.conf и de.conf: строки, числа, true/false)
local function opt(text, key, def)
  if not text then return def end
  text = text:gsub("//[^\n]*", "")
  local v = text:match("[%s{,\"']" .. key .. "[\"']?%s*:%s*([^,}\n]+)")
  if not v then return def end
  v = v:gsub("^%s+", ""):gsub("%s+$", "")
  if v == "true" then return true end
  if v == "false" then return false end
  local q = v:match("^[\"'](.*)[\"']$")
  if q then return q end
  return tonumber(v) or v
end

local ITEMS = {
  { "CubeOS", "boot" },
  { "CubeOS (safe mode)", "safe" },
  { "Recovery", "recovery" },
  { "CraftOS", "craftos" },
}

local function say(row, text, fg, bg)
  term.setCursorPos(2, row)
  if term.isColor() then term.setTextColor(fg or colors.white) term.setBackgroundColor(bg or colors.black) end
  term.write(text)
end

local function draw(sel, left)
  if term.isColor() then term.setBackgroundColor(colors.black) end
  term.clear()
  say(2, "CubeOS boot menu", colors.cyan)
  for i, it in ipairs(ITEMS) do
    local on = i == sel
    say(3 + i, (on and "> " or "  ") .. it[1] .. string.rep(" ", 24 - #it[1]), on and colors.black or colors.white, on and colors.cyan or colors.black)
  end
  say(4 + #ITEMS + 1, "Up/Down, Enter" .. (left and ("  (auto in " .. left .. " s)") or ""), colors.gray)
end

-- меню выбора; таймаут автовыбора первого пункта сбрасывается любой клавишей
local function menu(conf)
  local sel = 1
  local left = tonumber(opt(conf, "menu_timeout", 10)) or 0
  if left <= 0 then left = nil end
  local timer = left and os.startTimer(1)
  while true do
    draw(sel, left)
    local e, a = raw()
    if e == "timer" and a == timer then
      left = left - 1
      if left <= 0 then return ITEMS[sel][2] end
      timer = os.startTimer(1)
    elseif e == "key" then
      left, timer = nil, nil
      if a == keys.up then sel = (sel - 2) % #ITEMS + 1
      elseif a == keys.down then sel = sel % #ITEMS + 1
      elseif a == keys.enter then return ITEMS[sel][2] end
    end
  end
end

-- восстановление или проверка пароля перед CraftOS (arg: {reason=, gate=})
local function rescue(arg)
  local f = loadfile(B .. "rescue.lua")
  if f then
    local ok, r = pcall(f, arg)
    if ok then return r end
    arg = { reason = tostring(r) }
  end
  term.clear()
  term.setCursorPos(1, 1)
  print("CubeOS: rescue.lua is missing or broken.")
  if not fs.exists(USERS) then return "craftos" end
  print("Recovery is locked. Press any key to restart.")
  repeat local e = raw() until e == "key"
  return "reboot"
end

local function run(conf)
  local caps = { pixel = type(term.setGraphicsMode) == "function", color = term.isColor() }
  local mode = opt(conf, "menu", "key")                      -- "key" (F2 открывает меню), "always", "off"
  local window = (tonumber(opt(conf, "key_window_ms", 1000)) or 1000) / 1000
  local name = tostring(opt(conf, "menu_key", "f2"))
  local menukey = keys[name] or keys[name:lower()]
  local want_menu, ctrl = mode == "always", false
  if mode ~= "always" and window > 0 then
    local w, h = term.getSize()
    if term.isColor() then term.setTextColor(colors.gray) term.setBackgroundColor(colors.black) end
    term.setCursorPos(1, h)
    term.write(name:upper() .. ": menu   Ctrl: recovery")
    local timer = os.startTimer(window)
    while true do
      local e, a = raw()
      if e == "timer" and a == timer then break end
      if e == "key" then
        if a == keys.leftCtrl or a == keys.rightCtrl then ctrl = true break end
        if a == menukey and mode ~= "off" then want_menu = true break end
      end
    end
    term.setCursorPos(1, h)
    term.clearLine()
  end

  local choice = "boot"
  if ctrl then choice = "recovery" end
  while true do
    if want_menu and not ctrl then choice = menu(conf) end
    if choice == "recovery" then return rescue({ reason = "requested at startup" }) end
    if choice == "craftos" then
      local r = rescue({ gate = true })
      if r == "craftos" then return r end
      if not want_menu then return r end
    else
      break
    end
  end

  local de = rd(DE_CONF)
  local path = opt(de, "boot", B .. "stage2.lua")
  local fn, err = loadfile(path)
  if not fn then return rescue({ reason = "cannot load the boot loader: " .. tostring(err) }) end
  local ctx = { caps = caps, mode = choice == "safe" and "safe" or nil, menu = want_menu, boot_dir = B, conf_path = CONF }
  local ok, res, why = pcall(fn, ctx)
  if not ok then return rescue({ reason = tostring(res) }) end
  if res == "recovery" then return rescue({ reason = why or "requested by the boot loader" }) end
  return res
end

return run(rd(CONF))
