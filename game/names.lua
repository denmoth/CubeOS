-- Как игра хранит русские имена файлов (CFS разрешает кириллицу в именах). На компьютере: /repo/game/names.lua
-- Результат печатается и пишется в /repo/build/names-result.txt
local OUT = "/repo/build/names-result.txt"
if fs.exists(OUT) then fs.delete(OUT) end
local function say(line)
  print(line)
  local f = fs.open(OUT, "a")
  if f then f.write(line .. "\n") f.close() end
end

local base = "/repo/build/names_probe"
if fs.exists(base) then fs.delete(base) end
fs.makeDir(base)

local function hex(s)
  local out = {}
  for i = 1, #s do out[i] = string.format("%02x", s:byte(i)) end
  return table.concat(out, " ")
end

local names = { "Привет.txt", "Мир.txt", "Файл 1.txt", "abc.txt" }
say("== names probe ==")
for _, name in ipairs(names) do
  local ok, err = pcall(function()
    local h = fs.open(base .. "/" .. name, "wb")
    if not h then error("cannot open") end
    h.write("data:" .. name)
    h.close()
  end)
  say("write " .. name .. ": " .. (ok and "ok" or ("ERROR " .. tostring(err))))
end

local listed = fs.list(base)
say("listed " .. #listed .. " entries (wrote " .. #names .. ")")
for _, n in ipairs(listed) do
  say("  [" .. n .. "] bytes: " .. hex(n))
end

local all_ok = true
for _, name in ipairs(names) do
  local exists = fs.exists(base .. "/" .. name)
  local content
  if exists then
    local h = fs.open(base .. "/" .. name, "rb")
    content = h.readAll()
    h.close()
  end
  local good = exists and content == "data:" .. name
  say("read " .. name .. ": " .. (good and "ok" or ("MISMATCH exists=" .. tostring(exists) .. " content=" .. tostring(content))))
  if not good then all_ok = false end
end

local found_exact = 0
for _, name in ipairs(names) do
  for _, n in ipairs(listed) do
    if n == name then found_exact = found_exact + 1 end
  end
end
say("names listed back byte-for-byte: " .. found_exact .. " of " .. #names)
say(all_ok and found_exact == #names and "RESULT: Cyrillic file names work" or "RESULT: Cyrillic file names are NOT preserved on this host")
fs.delete(base)
