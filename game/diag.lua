-- Ищет, где лексер/парсер Cubic в игре расходится с эмулятором. На компьютере: /repo/game/diag.lua
-- Результат печатается и пишется в /repo/build/diag-result.txt
local ROOT = "/repo"
if not fs.exists(ROOT .. "/build") then fs.makeDir(ROOT .. "/build") end
local OUT = ROOT .. "/build/diag-result.txt"
if fs.exists(OUT) then fs.delete(OUT) end
local function say(line)
  print(line)
  local f = fs.open(OUT, "a")
  if f then f.write(line .. "\n") f.close() end
end
local function yield() os.queueEvent("d") os.pullEvent("d") end

local function read(path)
  local f = fs.open(path, "rb")
  if not f then return nil end
  local s = f.readAll()
  f.close()
  return s
end

local function adler(s)
  local a, b = 1, 0
  for i = 1, #s do
    a = (a + s:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return string.format("%08x", b * 65536 + a)
end

local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
local U = cubic.util
local lexer = loadfile(ROOT .. "/src/cubic/lexer.lua")(U)

local function hex(s)
  local out = {}
  for i = 1, #s do out[i] = string.format("%02x", s:byte(i)) end
  return table.concat(out, " ")
end

-- 1. сведения о файлах и о хосте
say("== diag ==")
for _, p in ipairs({ "/repo/lib/sha256.cub", "/repo/lib/crc32.cub", "/repo/tests/modules/t.cub", "/repo/lib/lzfast.cub" }) do
  local s = read(p)
  say(p .. ": " .. tostring(s and #s) .. " bytes, adler32 " .. tostring(s and adler(s)) .. ", CR count " .. tostring(s and select(2, s:gsub("\r", ""))))
end

-- 2. поведение строковых функций хоста на тех же вызовах, что делает лексер
say("")
say("-- string function probes --")
local s = "  for i in range[2, n]:\nx"
local a, b = s:find("^ *", 1)
say("find('^ *',1): " .. tostring(a) .. "," .. tostring(b))
a, b = s:find("^ *", 3)
say("find('^ *',3): " .. tostring(a) .. "," .. tostring(b) .. " (expected 3,2)")
a, b = s:find("^[%a_][%w_]*", 7)
say("find word at 7: " .. tostring(a) .. "," .. tostring(b) .. " (expected 7,9)")
a, b = s:find("\n", 5, true)
say("find plain newline: " .. tostring(a) .. "," .. tostring(b) .. " (expected 23,23)")
say("sub(24,25): '" .. s:sub(24, 25) .. "'")
say("('x'):rep(3): " .. ("x"):rep(3))
say("match '%d': " .. tostring(("5"):match("%d")) .. ", '[%a_]': " .. tostring(("_"):match("[%a_]")))
local t = "a_b"
say("gsub underscore: " .. tostring(select(1, ("1_000"):gsub("_", ""))))

-- 3. деление исходника на строки: первая строка, на которой лексер падает
local function lines_of(text)
  local r = {}
  for l in (text .. "\n"):gmatch("([^\n]*)\n") do r[#r + 1] = l end
  return r
end

local function first_failure(path)
  local text = read(path)
  if not text then say(path .. ": cannot read") return end
  local lines = lines_of(text)
  say("")
  say("-- bisect " .. path .. " (" .. #lines .. " lines) --")
  local last_ok = 0
  for n = 1, #lines do
    local chunk = table.concat(lines, "\n", 1, n) .. "\n"
    local ok, err = pcall(lexer.tokenize, chunk, path)
    if ok then
      last_ok = n
    else
      local msg = type(err) == "table" and tostring(err) or tostring(err)
      -- незакрытая скобка в середине выражения это нормально, ищем ошибку другого рода
      if not msg:find("unclosed bracket", 1, true) and not msg:find("unterminated", 1, true) then
        say("lexer error after line " .. n .. ": " .. msg)
        say("line " .. n .. ": " .. lines[n])
        say("bytes: " .. hex(lines[n]:sub(1, 60)))
        return
      end
    end
    if n % 40 == 0 then yield() end
  end
  local ok, err = pcall(lexer.tokenize, text, path)
  say("full file lexing: " .. (ok and "ok" or tostring(err)))
  if ok then
    local ok2, err2 = pcall(cubic.compile, text, path, {})
    say("full file compile: " .. (ok2 and "ok" or tostring(err2)))
  end
end

first_failure("/repo/tests/modules/t.cub")
first_failure("/repo/lib/crc32.cub")

-- 4. токены одной проблемной строки
local function tokens_of(snippet)
  local ok, toks = pcall(lexer.tokenize, snippet, "snippet")
  if not ok then
    say("snippet " .. snippet:gsub("\n", "\\n") .. " -> ERROR " .. tostring(toks))
    return
  end
  local parts = {}
  for _, tk in ipairs(toks) do parts[#parts + 1] = tk.t .. (tk.v ~= nil and tk.t ~= tk.v and ("(" .. tostring(tk.v) .. ")") or "") end
  say("snippet " .. snippet:gsub("\n", "\\n") .. " -> " .. table.concat(parts, " "))
end

say("")
say("-- tokens of small snippets --")
tokens_of("for i in range[2, rounds]:\n    u = 1\n")
tokens_of("x = hmac(password, salt .. \"\\0\\0\\0\\1\")\n")
tokens_of("eq(1, \"1.2.3\", \"inc pre\")\n")
tokens_of("override print = print\n")
tokens_of("if lo >= 56320 and lo <= 57343:\n    pass\n")
tokens_of("print(\"FAIL \" .. label .. \": got \" .. textutils.serialize(got))\n")
tokens_of("x = \"a\" .. \"b\"\n")
say("== done ==")
