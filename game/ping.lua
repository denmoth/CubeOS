-- Пинг вышки с карманного компьютера. Запуск: ping
local modem = peripheral.find("modem")
if not modem then
  print("no modem attached")
  return
end
rednet.open(peripheral.getName(modem))
for i = 1, 5 do
  rednet.broadcast("ping " .. i)
  local id, msg = rednet.receive(3)
  print(i, id and ("reply from " .. id .. ": " .. tostring(msg)) or "no reply")
end
