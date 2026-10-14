-- Как хост считает длину строк с байтами выше 127. На компьютере: /repo/game/diag3.lua
-- Результат печатается и пишется в /repo/build/diag3-result.txt
local OUT = "/repo/build/diag3-result.txt"
if fs.exists(OUT) then fs.delete(OUT) end
local function say(line)
  print(line)
  local f = fs.open(OUT, "a")
  if f then f.write(line .. "\n") f.close() end
end

-- строка из 4 байт: d0 b2 d1 81 (две русские буквы в UTF-8), собранная без литералов с юникодом
local s = string.char(0xd0, 0xb2, 0xd1, 0x81)
say("== diag3 ==")
say("real byte count (loop of s:byte(i)): " .. (function() local n = 0 while s:byte(n + 1) do n = n + 1 end return n end)() .. " (expected 4)")
say("#s: " .. #s)
say("string.len(s): " .. string.len(s))
say("s:len(): " .. s:len())
say("select('#', s:byte(1, -1)): " .. select("#", s:byte(1, -1)))
say("utf8.len(s): " .. tostring(utf8 and utf8.len(s)))
say("#(s .. s): " .. #(s .. s))
say("#string.rep(s, 3): " .. #string.rep(s, 3))
say("s:sub(1, 4) bytes: " .. select("#", s:sub(1, 4):byte(1, -1)))
say("s:sub(3, 4) first byte: " .. tostring(s:sub(3, 4):byte(1)) .. " (expected 209)")
say("#s:sub(1, 3): " .. #s:sub(1, 3) .. " (3 bytes, last one is a partial char)")
local ascii = "hello"
say("#ascii: " .. #ascii)
local mixed = "ab" .. s .. "cd"
say("#mixed (8 bytes, 6 chars): " .. #mixed .. ", string.len: " .. string.len(mixed))
say("mixed:find('c', 1, true): " .. tostring(mixed:find("c", 1, true)) .. " (expected 7)")
say("mixed:sub(-2): " .. mixed:sub(-2))

-- те же проверки для чтения файла
local path = "/repo/tests/modules/t.cub"
local f = fs.open(path, "rb")
local text = f.readAll()
f.close()
local real = 0
local chunk = 1
-- считаем байты циклом (медленно, но надёжно)
while text:byte(real + 1) do real = real + 1 end
say("t.cub: real bytes " .. real .. ", #text " .. #text .. ", string.len " .. string.len(text) .. " (disk 560)")
say("== done ==")
