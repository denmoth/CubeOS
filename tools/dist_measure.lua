-- Замер: собрать lib и sys в build/dist готовым (минифицированным) Lua. Запуск в CraftOS-PC (см. tools/dist_measure.sh).
local ROOT = "/repo"
local cubic = loadfile(ROOT .. "/src/cubic/init.lua")(ROOT .. "/src/cubic")
local function read(p) local f = fs.open(p, "rb"); local s = f.readAll(); f.close(); return s end
local function write(p, d) fs.makeDir(fs.getDir(p)); local f = fs.open(p, "wb"); f.write(d); f.close() end
local out, fails, n, rawb, outb = {}, {}, 0, 0, 0
local function walk(dir, rel)
  for _, name in ipairs(fs.list(dir)) do
    local p = dir .. "/" .. name
    local r = rel == "" and name or (rel .. "/" .. name)
    if fs.isDir(p) then walk(p, r)
    elseif name:match("%.cub$") then
      local src = read(p)
      local ok, code = pcall(cubic.compile, src, name, { minify = true, banner = false, release = true })
      if ok and type(code) == "string" then
        write(ROOT .. "/build/dist/lib/" .. r:gsub("%.cub$", ".lua"), code)
        n = n + 1; rawb = rawb + #src; outb = outb + #code
      else fails[#fails + 1] = r .. ": " .. tostring(code):sub(1, 120) end
    end
  end
end
walk(ROOT .. "/lib", "")
write(ROOT .. "/build/dist-report.txt", string.format("files=%d src=%d lua=%d\n%s\n", n, rawb, outb, table.concat(fails, "\n")))
os.shutdown()
