-- Как игра читает файлы с UTF-8 (русские комментарии в исходниках). На компьютере: /repo/game/diag2.lua
-- Результат печатается и пишется в /repo/build/diag2-result.txt
local OUT = "/repo/build/diag2-result.txt"
if fs.exists(OUT) then fs.delete(OUT) end
local function say(line)
  print(line)
  local f = fs.open(OUT, "a")
  if f then f.write(line .. "\n") f.close() end
end

local function hex(s, n)
  local out = {}
  for i = 1, math.min(#s, n) do out[i] = string.format("%02x", s:byte(i)) end
  return table.concat(out, " ")
end

local path = "/repo/tests/modules/t.cub"
say("== diag2 on " .. path .. " (on disk: 560 bytes, starts with '# ' + 41 Cyrillic letters) ==")

local function try(label, mode, how)
  local f = fs.open(path, mode)
  if not f then say(label .. ": cannot open") return end
  local ok, s = pcall(function()
    if how == "all" then return f.readAll() end
    if how == "line" then return f.readLine(true) end
    if how == "n" then return f.read(60) end
    if how == "byte" then
      local t = {}
      for i = 1, 30 do
        local b = f.read(1)
        if not b then break end
        t[#t + 1] = type(b) == "number" and string.char(b) or b
      end
      return table.concat(t)
    end
  end)
  f.close()
  if not ok then say(label .. ": ERROR " .. tostring(s)) return end
  s = s or ""
  say(label .. ": #" .. #s .. " | " .. hex(s, 30))
end

try("rb  readAll", "rb", "all")
try("rb  readLine", "rb", "line")
try("rb  read(60)", "rb", "n")
try("rb  read(1)x30", "rb", "byte")
try("r   readAll", "r", "all")
try("r   readLine", "r", "line")

local f = fs.open(path, "rb")
local s = f.readAll()
f.close()
local counts = {}
for i = 1, #s do
  local b = s:byte(i)
  if b > 127 then counts[b] = (counts[b] or 0) + 1 end
end
local hi = 0
for _ in pairs(counts) do hi = hi + 1 end
say("rb readAll: bytes above 127: " .. hi .. " distinct values")
say("has newline in first line: " .. tostring(s:find("\n", 1, true)) .. " (disk: 48)")
say("first line as read: " .. s:sub(1, (s:find("\n", 1, true) or 60)):gsub("[^%g ]", "?"))

-- не байты ли это уже после преобразования строки
local u = "\xd0\xb2"
say("literal UTF-8 string length in Lua source: " .. #u .. " (expected 2)")
say("utf8.len of the file text: " .. tostring(utf8 and utf8.len(s)))
say("== done ==")
