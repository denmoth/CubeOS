-- Unit checks for the header cache of imported modules (modification-time based invalidation).
-- Called by tests/run.lua as: chunk(cubic, ROOT, record)
local cubic, ROOT, record = ...

local function write(path, text)
  local f = fs.open(path, "w")
  f.write(text)
  f.close()
end

local function read(path)
  local f = fs.open(path, "r")
  if not f then return nil end
  local s = f.readAll()
  f.close()
  return s
end

local dir = ROOT .. "/build/unit_modtypes"
if fs.exists(dir) then fs.delete(dir) end
fs.makeDir(dir)
local cache = dir .. "/cache"

local loader = cubic.new_loader({ roots = { dir } })
local opts = { loader = loader, header_cache = cache, base_dir = dir }

local importer = "#!strict\nimport m\nx: num = m.f(1)\n"

-- version 1: f returns a number
write(dir .. "/m.cub", "export def f(a: num) -> num:\n    return a\n")
local lua1, err1 = cubic.try_compile(importer, "main.cub", opts)
record("modtypes: valid import compiles", lua1 ~= nil, tostring(err1))

local cached_files = fs.list(cache)
local has_header = false
for _, name in ipairs(cached_files) do
  local text = read(cache .. "/" .. name) or ""
  if text:sub(1, 17) == "# cubic-header 1 " then has_header = true end
end
record("modtypes: header file saved in the cache directory", has_header, table.concat(cached_files, ","))

-- version 2: f now returns a string (the file size changes, so the cache entry is stale)
write(dir .. "/m.cub", "export def f(a: num) -> str:\n    return \"text result\"\n")
local lua2, err2 = cubic.try_compile(importer, "main.cub", opts)
record("modtypes: changed module invalidates the cached header", lua2 == nil and tostring(err2):find("cannot initialize 'x'", 1, true) ~= nil, tostring(err2))

-- without a cache directory the result is the same
local opts2 = { loader = loader, base_dir = dir }
local lua3, err3 = cubic.try_compile(importer, "main.cub", opts2)
record("modtypes: works without a cache directory", lua3 == nil and tostring(err3):find("cannot initialize 'x'", 1, true) ~= nil, tostring(err3))

-- banner of a compiled file
local out = cubic.compile("x = 1\n", "b.cub")
local b = cubic.parse_banner(out)
record("banner: parse_banner reads version and size", b ~= nil and b.size == 6 and b.file == "b.cub", tostring(out:match("^[^\n]*")))
record("banner: is_up_to_date true for the same source", cubic.is_up_to_date(out, "x = 1\n"), "")
record("banner: is_up_to_date false for a changed source", not cubic.is_up_to_date(out, "x = 2\n"), "")
local plain = cubic.compile("x = 1\n", "b.cub", { banner = false })
record("banner: can be disabled", cubic.parse_banner(plain) == nil, "")
