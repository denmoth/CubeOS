-- Cubic: types of imported modules.
-- When strict code imports a module, the compiler needs to know (at least minimally) what that module exports.
-- For .cub modules the exports are inferred by the type checker and saved as a .cuh header in a cache directory;
-- the cache entry is valid while the source file's modification time and size are unchanged.
-- For plain .lua modules a rough stub (function names and parameter names, all types any) is made from the text.
local U, parser, checker, read_file, dirname, version = ...

local M = {}

local mem_headers = {} -- path -> { stamp, text, open }
local info_cache = {} -- path -> { stamp, env, info }

local function file_stamp(path)
  if fs and fs.attributes then
    local ok, a = pcall(fs.attributes, path)
    if ok and a then return tostring(a.modified or 0) .. ":" .. tostring(a.size or 0) end
  end
  return nil
end

local function write_file(path, text)
  if fs and fs.open then
    pcall(function()
      local dir = path:match("^(.*)/[^/]*$")
      if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
      local f = fs.open(path, "wb")
      if f then
        f.write(text)
        f.close()
      end
    end)
  end
end

-- header text of a plain Lua module (rough: names and parameter names only)
local function lua_stub(src)
  local fns, vars, order = {}, {}, {}
  local function add_fn(name, args)
    if not name:match("^[%a_][%w_]*$") then return end
    if fns[name] == nil and vars[name] == nil then order[#order + 1] = name end
    fns[name] = args
  end
  local function add_var(name)
    if not name:match("^[%a_][%w_]*$") then return end
    if fns[name] == nil and vars[name] == nil then order[#order + 1] = name end
    vars[name] = true
  end
  for line in src:gmatch("[^\n]+") do
    local owner, name, args = line:match("^function%s+([%w_]+)[%.:]([%w_]+)%s*%(([^)]*)%)")
    if owner then
      add_fn(name, args)
    else
      local o2, n2, a2 = line:match("^([%w_]+)%.([%w_]+)%s*=%s*function%s*%(([^)]*)%)")
      if o2 then
        add_fn(n2, a2)
      else
        local o3, n3 = line:match("^([%w_]+)%.([%w_]+)%s*=")
        if o3 then
          add_var(n3)
        else
          local lname, largs = line:match("^local%s+function%s+([%w_]+)%s*%(([^)]*)%)")
          if lname then add_fn(lname, largs) end
        end
      end
    end
  end
  -- only names returned in `return { a = a, b = b }` or defined with a table prefix are exported
  local exported = {}
  local ret = src:match("return%s*(%b{})%s*$")
  if ret then
    for key in ret:gmatch("([%a_][%w_]*)%s*=") do exported[key] = true end
  end
  local lines = {}
  for _, name in ipairs(order) do
    if fns[name] ~= nil then
      local params = {}
      for p in fns[name]:gmatch("[^,]+") do
        p = p:gsub("%s+", "")
        if p == "..." then
          params[#params + 1] = "*rest: any"
        elseif p:match("^[%a_][%w_]*$") and p ~= "self" then
          params[#params + 1] = p .. ": any = ..."
        end
      end
      lines[#lines + 1] = "def " .. name .. "(" .. table.concat(params, ", ") .. ") -> any"
    else
      lines[#lines + 1] = name .. ": any"
    end
  end
  return table.concat(lines, "\n") .. "\n"
end

local function cache_name(dir, path)
  return dir .. "/" .. (path:gsub("[/\\:]", "_")) .. ".cuh"
end

local make_resolver

-- header text of a module and whether unknown members are allowed (open)
local function header_text(path, opts, env, stack)
  local stamp = file_stamp(path)
  local mem = mem_headers[path]
  if mem and stamp ~= nil and mem.stamp == stamp and mem.version == version then
    return mem.text, mem.open
  end
  local first_line = "# cubic-header 1 " .. tostring(stamp) .. " " .. version
  local cache_file = opts.header_cache and cache_name(opts.header_cache, path)
  if cache_file and stamp ~= nil then
    local cached = read_file(cache_file)
    if cached then
      local head, rest = cached:match("^([^\n]*)\n(.*)$")
      if head and head:sub(1, #first_line) == first_line then
        local open = head:find(" open", 1, true) ~= nil
        mem_headers[path] = { stamp = stamp, text = rest, open = open, version = version }
        return rest, open
      end
    end
  end
  if stack[path] then return nil end
  stack[path] = true
  local src = read_file(path)
  local text, open = nil, false
  if src then
    if path:sub(-4) == ".cub" then
      local ok, result = pcall(function()
        local ast = parser.parse(src, path)
        local sub = setmetatable({
          strict = true,
          exports_mode = true,
          banner = false,
          module_types = make_resolver(path, opts, env, stack),
        }, { __index = opts })
        return checker.check(ast, path, env, false, sub) or ""
      end)
      if ok then text = result end
    else
      text, open = lua_stub(src), true
    end
  end
  stack[path] = nil
  if text == nil then return nil end
  mem_headers[path] = { stamp = stamp, text = text, open = open, version = version }
  if cache_file and stamp ~= nil then
    write_file(cache_file, first_line .. (open and " open" or "") .. "\n" .. text)
  end
  return text, open
end

-- header text -> { members = { name -> type }, open = bool }
local function header_info(path, text, open, env)
  local stamp = file_stamp(path)
  local hit = info_cache[path]
  if hit and stamp ~= nil and hit.stamp == stamp and hit.env == env then return hit.info end
  local ok, info = pcall(function()
    local hast = parser.parse_header(text, path .. ".cuh")
    local child = {
      vars = setmetatable({}, { __index = env.vars }),
      types = setmetatable({}, { __index = env.types }),
      periph = env.periph,
    }
    checker.check(hast, path .. ".cuh", child, true)
    local members = {}
    for k, v in pairs(child.vars) do members[k] = v end
    return { members = members, open = open }
  end)
  if not ok then return nil end
  info_cache[path] = { stamp = stamp, env = env, info = info }
  return info
end

-- Returns spec -> info function for the file being compiled, or nil when there is no module loader.
function make_resolver(file, opts, env, stack)
  local loader = opts.loader
  if not loader then return nil end
  local dir = opts.base_dir or dirname(file)
  return function(spec)
    local ok, path = pcall(loader.resolve, spec, dir)
    if not ok then return nil end
    local text, open = header_text(path, opts, env, stack)
    if not text then return nil end
    return header_info(path, text, open, env)
  end
end

M.make_resolver = make_resolver
M.header_text = header_text

-- exported for tools: header of a module file (no type environment needed for .lua stubs)
function M.stub_for_lua(src)
  return lua_stub(src)
end

return M
