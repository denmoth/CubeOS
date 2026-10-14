-- Длина в байтах не должна зависеть от того, как хост считает # (см. util.lua, U.blen)
-- Called by tests/run.lua as: chunk(cubic, ROOT, record)
local cubic, ROOT, record = ...
local U = cubic.util

local function check(name, got, want)
  record("blen: " .. name, got == want, "got " .. tostring(got) .. " want " .. tostring(want))
end

check("empty", U.blen(""), 0)
check("ascii", U.blen("hello"), 5)
check("high bytes", U.blen(string.char(0xd0, 0xb2, 0xd1, 0x81)), 4)
check("long mixed", U.blen(string.rep("ab" .. string.char(0xd0, 0xb2, 0x00, 0xff), 1000)), 6000)
check("single high byte", U.blen(string.char(255)), 1)
check("rt.len on string", cubic.rt.len(string.char(0xd0, 0xb2)), 2)
check("rt.len on table", cubic.rt.len({ 1, 2, 3 }), 3)

-- русский комментарий не должен влиять на разбор
local src = "# комментарий на русском\nx = 1\nprint(x)\n"
local lua, err = cubic.try_compile(src, "ru.cub", {})
check("compiles with cyrillic comment", lua ~= nil, true)
