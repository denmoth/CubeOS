-- Запуск тестов Cubic в настоящем CC (Cobalt). На компьютере: /repo/game/runtests.lua [фильтр]
-- Ход выполнения дописывается в /repo/build/progress.txt, итог в /repo/build/test-result.txt.
if not fs.exists("/repo/build") then fs.makeDir("/repo/build") end
if fs.exists("/repo/build/progress.txt") then fs.delete("/repo/build/progress.txt") end
if fs.exists("/repo/build/test-result.txt") then fs.delete("/repo/build/test-result.txt") end
_G.CUBIC_GAME_TEST = true
local started = os.epoch("utc")
print("Cubic tests: started (may take a few minutes)")
local chunk, err = loadfile("/repo/tests/run.lua")
if not chunk then error(err, 0) end
local ok, e = pcall(chunk, ...)
_G.CUBIC_GAME_TEST = nil
local secs = (os.epoch("utc") - started) / 1000
if not ok then
  print("RUNNER ERROR: " .. tostring(e))
end
local f = fs.open("/repo/build/test-result.txt", "r")
if f then
  local text = f.readAll()
  f.close()
  local summary = text:match("(%d+ passed, %d+ failed)")
  print((summary or "no summary") .. string.format("  (%.0f s)", secs))
  local fails = {}
  for name in text:gmatch("FAIL  ([^\n]+)") do fails[#fails + 1] = name end
  for i = 1, math.min(#fails, 15) do print("  FAIL " .. fails[i]) end
  if #fails > 15 then print("  ... and " .. (#fails - 15) .. " more, see /repo/build/test-result.txt") end
else
  print("no result file: the run was cut off, see /repo/build/progress.txt")
end
