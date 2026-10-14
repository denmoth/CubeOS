-- Вышка: отвечает на пинг и пишет метки времени в /hb.txt. По паузам в метках видно, что компьютер был выгружен.
-- Запуск: tower   (чтобы стартовало само после выгрузки чанка: copy tower startup)
local modem = peripheral.find("modem")
if not modem then
  print("no modem attached")
  return
end
rednet.open(peripheral.getName(modem))
rednet.host("tower", "t1")
print("tower up, computer id " .. os.getComputerID())

local f = fs.open("/hb.txt", "a")
f.writeLine("boot " .. os.epoch("utc"))
f.close()

while true do
  local id, msg = rednet.receive(5)
  if id then
    rednet.send(id, "pong " .. tostring(msg))
    print("ping from " .. id .. ": " .. tostring(msg))
  end
  local h = fs.open("/hb.txt", "a")
  h.writeLine(os.epoch("utc"))
  h.close()
end
