-- Переход на области Cubic 1.0: где функция присваивает имени, которое есть снаружи (теперь это своя переменная), и где код
-- читает такую переменную до присваивания (ошибка компиляции). Запуск в CraftOS-PC, отчёт в build/scope-report.txt
local ROOT = "/repo"
local DIR_ARG = ...
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
local function read(p) local f = fs.open(p, "rb"); local s = f.readAll(); f.close(); return s end
local lines = {}
local function walk(dir, rel)
  for _, name in ipairs(fs.list(dir)) do
    local p = dir .. "/" .. name
    local r = rel == "" and name or (rel .. "/" .. name)
    if fs.isDir(p) then walk(p, r)
    elseif name:match("%.cub$") then
      local ok, code, lmap, warns = pcall(cubic.compile, read(p), r, { report_shadow = true, banner = false })
      if not ok then lines[#lines + 1] = "ERROR " .. tostring(code)
      else
        for _, w in ipairs(warns or {}) do
          if w:find("shadow-outer", 1, true) then lines[#lines + 1] = w end
        end
      end
    end
  end
end
walk(ROOT .. "/" .. (DIR_ARG or "lib"), "")
local f = fs.open(ROOT .. "/build/scope-report.txt", "w") f.write(table.concat(lines, "\n") .. "\n") f.close()
os.shutdown()
