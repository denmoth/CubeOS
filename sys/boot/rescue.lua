-- CubeOS: восстановление (D204). Небольшое, не зависит от этапа 1 и загрузчика.
-- Вызывается как chunk(arg): arg.reason (почему), arg.gate = true (только проверка пароля перед CraftOS).
-- Пароль администратора проверяет runtime.lua (boot.recovery_login: три попытки; без учётных записей открыто).
-- Результат: "craftos", "reboot" или "shutdown". Без runtime.lua при наличии учётных записей восстановление заперто.
local arg = ... or {}
local B, USERS = "/cubeos/sys/boot/", "/cubeos/sys/cfg/users.conf"

local console = {}
function console:write_line(text) print(text) end
function console:read_line(prompt, hide)
  write(prompt)
  return read(hide and "*" or nil)
end

term.clear()
term.setCursorPos(1, 1)
print(arg.gate and "CubeOS: access to CraftOS" or "CubeOS recovery")
if arg.reason then print("Reason: " .. tostring(arg.reason)) end

-- хвост журнала загрузки: что происходило перед сбоем (читается без пароля: там нет секретов)
do
  local f = fs.open("/cubeos/var/log/boot.log", "r")
  if f then
    local lines = {}
    while true do
      local l = f.readLine()
      if not l then break end
      lines[#lines + 1] = l
    end
    f.close()
    local w = term.getSize()
    print("")
    print("Last lines of /cubeos/var/log/boot.log:")
    for i = math.max(1, #lines - 9), #lines do print(lines[i]:sub(1, w)) end
  end
end

local function unlocked()
  if not fs.exists(USERS) then return true end                -- ещё нет учётных записей
  local f = loadfile(B .. "runtime.lua")
  if not f then
    print("Cannot verify the password: runtime.lua is missing.")
    return false
  end
  local ok, rt = pcall(f)
  if not ok or type(rt) ~= "table" or not rt.recovery_login then
    print("Cannot verify the password: " .. tostring(rt))
    return false
  end
  local ok2, res = pcall(rt.recovery_login, console)
  if not ok2 then print("Cannot verify the password: " .. tostring(res)) end
  return ok2 and res == true
end

if not unlocked() then
  print("Restarting in 3 seconds.")
  sleep(3)
  return "reboot"
end
if arg.gate then return "craftos" end

while true do
  print("")
  print("1) CraftOS shell   2) Restart   3) Shut down")
  local c = console:read_line("> ")
  if c == "1" then return "craftos" end
  if c == "2" then return "reboot" end
  if c == "3" then return "shutdown" end
end
