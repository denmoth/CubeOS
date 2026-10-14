-- Cubic: генератор Lua
local U, B = ...

local M = {}

local RESERVED = U.LUA_RESERVED

local function mangle(name)
  if RESERVED[name] then return "__k_" .. name end
  return name
end

-- Собирает все идентификаторы из сырого Lua-кода
local function lua_idents(code, set)
  for id in code:gmatch("[%a_][%w_]*") do set[id] = true end
end

-- Обход AST: имена (Name) и идентификаторы в lua-вставках
local function scan_names(node, names, raw)
  if type(node) ~= "table" then return end
  if node.tag == "Name" then names[node.name] = true end
  if node.tag == "LuaBlock" or node.tag == "LuaExpr" then lua_idents(node.code, raw) end
  for k, v in pairs(node) do
    if type(v) == "table" and k ~= "comments" then scan_names(v, names, raw) end
  end
end

local SHORT_FIRST = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local SHORT_REST = SHORT_FIRST .. "0123456789"

function M.generate(ast, file, opts)
  opts = opts or {}
  local minify = opts.minify
  local out, lmap = {}, {}
  local level = 0
  local curline = 1
  local warnings = {}
  local scope = nil
  local ctx = {}
  local class_stack = {}
  local idseq = 0
  local exports = {}

  -- минификация: уникальные короткие имена для всех переменных модуля
  local avoid, keep = {}, {}
  local short_n = 0
  if minify then
    scan_names(ast, avoid, keep)
    for k in pairs(keep) do avoid[k] = true end
  end

  local function short_name()
    while true do
      short_n = short_n + 1
      local n = short_n - 1
      local first = n % #SHORT_FIRST
      local s = SHORT_FIRST:sub(first + 1, first + 1)
      n = math.floor(n / #SHORT_FIRST)
      while n > 0 do
        n = n - 1
        local r = n % #SHORT_REST
        s = s .. SHORT_REST:sub(r + 1, r + 1)
        n = math.floor(n / #SHORT_REST)
      end
      if not avoid[s] and not RESERVED[s] then return s end
    end
  end

  local function fail(line, msg)
    U.fail(file, line or curline, 1, msg)
  end

  local function warn(line, msg)
    warnings[#warnings + 1] = file .. ":" .. (line or curline) .. ": warning: " .. msg
  end

  local function emit(s)
    if minify then
      out[#out + 1] = s
    else
      out[#out + 1] = string.rep("  ", level) .. s
    end
    lmap[#lmap + 1] = curline
  end

  -- комментарии (--keep-comments)
  local comments = (opts.keep_comments and ast.comments) or {}
  local cidx = 1
  local function flush_comments(upto)
    while cidx <= #comments and comments[cidx].line <= upto do
      local c = comments[cidx]
      local save = curline
      curline = c.line
      emit("--" .. c.text)
      curline = save
      cidx = cidx + 1
    end
  end

  local function nextid()
    idseq = idseq + 1
    return idseq
  end

  ---------------------------------------------------------------- области видимости

  local function push_scope(is_fn)
    scope = { parent = scope, names = {}, is_fn = is_fn }
    return scope
  end

  local function pop_scope()
    scope = scope.parent
  end

  local function lookup_from(sc, name)
    while sc do
      local info = sc.names[name]
      if info then return info end
      sc = sc.parent
    end
    return nil
  end

  local function lookup(name)
    return lookup_from(scope, name)
  end

  local function check_name(name, line)
    if name:sub(1, 2) == "__" then
      fail(line, "names starting with '__' are reserved for the compiler: '" .. name .. "'")
    end
  end

  -- объявляет переменную в текущей области, возвращает её имя в Lua
  local function declare(name, kind, line)
    check_name(name, line)
    local lname
    if minify and not keep[name] then
      lname = short_name()
    else
      lname = mangle(name)
    end
    scope.names[name] = { kind = kind, lname = lname }
    return lname
  end

  local function lname_of(name)
    local info = lookup(name)
    return info and info.lname or mangle(name)
  end

  local function protected_error(name, line)
    fail(line, "cannot assign to builtin '" .. name .. "' (use 'override " .. name .. " = ...' to replace it deliberately)")
  end

  local function pattern_names(p, add)
    local tag = p.tag
    if tag == "PCapture" then add(p.name, p.line)
    elseif tag == "POr" then for _, a in ipairs(p.alts) do pattern_names(a, add) end
    elseif tag == "PList" then
      for _, it in ipairs(p.items) do pattern_names(it, add) end
      if p.star_name and p.star_name ~= "_" then add(p.star_name, p.line) end
    elseif tag == "PDict" then for _, e in ipairs(p.entries) do pattern_names(e.pat, add) end
    elseif tag == "PClass" then
      for _, a in ipairs(p.args) do pattern_names(a, add) end
      for _, kw in ipairs(p.kwargs) do pattern_names(kw.pat, add) end
    end
  end

  -- собирает имена, которые инструкции объявляют на уровне функции (как переменные Python)
  local function collect(stmts, names, seen)
    local function add(name, line, is_def)
      local e = seen[name]
      if e then
        if is_def then e.def = true end
        return
      end
      e = { name = name, line = line, def = is_def or false }
      seen[name] = e
      names[#names + 1] = e
    end
    for _, s in ipairs(stmts) do
      local tag = s.tag
      if tag == "Assign" then
        for _, t in ipairs(s.targets) do
          if t.tag == "Name" then add(t.name, s.line)
          elseif t.tag == "Starred" then add(t.name, s.line) end
        end
      elseif tag == "FuncDef" or tag == "ClassDef" or tag == "Import" then
        add(s.name, s.line, true)
      elseif tag == "AnnAssign" then
        add(s.name, s.line)
      elseif tag == "FromImport" then
        for _, n in ipairs(s.names) do add(n.alias, n.line, true) end
      elseif tag == "If" then
        collect(s.body, names, seen)
        for _, e in ipairs(s.elifs) do collect(e.body, names, seen) end
        if s.orelse then collect(s.orelse, names, seen) end
      elseif tag == "While" or tag == "ForRange" or tag == "ForIn" or tag == "With" or tag == "ModeBlock" then
        collect(s.body, names, seen)
      elseif tag == "Try" then
        collect(s.body, names, seen)
        for _, h in ipairs(s.handlers) do collect(h.body, names, seen) end
        if s.finally then collect(s.finally, names, seen) end
      elseif tag == "Match" then
        for _, c in ipairs(s.cases) do
          pattern_names(c.pattern, add)
          collect(c.body, names, seen)
        end
      end
    end
  end

  -- объявляет собранные имена локальными переменными текущей функции и выдаёт `local ...`
  local function hoist(stmts)
    local names = {}
    collect(stmts, names, {})
    local decl = {}
    for _, n in ipairs(names) do
      local name = n.name
      local outer = lookup_from(scope.parent, name)
      if not scope.names[name] and not outer then
        if B.PROTECTED[name] then protected_error(name, n.line) end
        if B.SHADOW_WARN[name] then warn(n.line, "'" .. name .. "' hides the CC global of the same name in this scope") end
        decl[#decl + 1] = declare(name, "local", n.line)
        scope.names[name].is_def = n.def
      elseif outer and outer.is_def and not n.def and not scope.names[name] then
        warn(n.line, "assignment to '" .. name .. "' replaces the function/class/import of the same name in the enclosing scope; use 'let " .. name .. " = ...' for a local variable")
      end
    end
    if #decl > 180 then
      fail(nil, "too many variables in one function (" .. #decl .. "); Lua allows about 200 locals, split the code")
    end
    if #decl > 0 then emit("local " .. table.concat(decl, ", ")) end
  end

  local function ref(name, line)
    check_name(name, line)
    local info = lookup(name)
    if info then return info.lname end
    if name == "super" then
      local cls = class_stack[#class_stack]
      if not cls then fail(line, "'super' can only be used inside a class") end
      return cls .. ".__base"
    end
    if B.MAP[name] then return B.MAP[name] end
    if RESERVED[name] then
      fail(line, "'" .. name .. "' is a reserved word in Lua and cannot be used as a global name")
    end
    return name
  end

  ---------------------------------------------------------------- выражения

  local E = {}
  local expr, block, stmt

  local SAFE_TRUTHY = U.set({ "Number", "String", "FString", "List", "Dict", "Lambda", "ListComp", "DictComp" })
  local NEEDS_PAREN = U.set({ "Number", "String", "FString", "List", "Dict", "Lambda", "Bool", "Nil", "Binary", "Unary", "Ternary", "LuaExpr", "ListComp", "DictComp" })

  local function base_expr(node)
    local code = expr(node)
    if NEEDS_PAREN[node.tag] and code:sub(1, 1) ~= "(" then
      return "(" .. code .. ")"
    end
    return code
  end

  local function attr_access(obj_code, name)
    if U.is_lua_name(name) then return obj_code .. "." .. name end
    return obj_code .. "[" .. U.quote(name) .. "]"
  end

  local function exprs(list)
    local r = {}
    for k, e in ipairs(list) do r[k] = expr(e) end
    return r
  end

  function expr(node)
    return E[node.tag](node)
  end

  -- знак шага: (динамический код | nil, знак | nil)
  local function sign_code(step_node)
    if not step_node then return "1", 1 end
    if step_node.tag == "Number" then
      return nil, (tonumber(step_node.v) or 1) >= 0 and 1 or -1
    elseif step_node.tag == "Unary" and step_node.op == "-" and step_node.e.tag == "Number" then
      return nil, -1
    end
    return "(" .. expr(step_node) .. " > 0 and 1 or -1)", nil
  end

  -- сдвиг границы для исключающих скобок: dir > 0 прибавляет знак шага, dir < 0 вычитает
  local function adjust_bound(code, dir, step_node)
    local dyn, sign = sign_code(step_node)
    local op = dir > 0 and " + " or " - "
    if dyn then return "(" .. code .. ")" .. op .. dyn end
    if sign == 1 then return "(" .. code .. ")" .. op .. "1" end
    return "(" .. code .. ")" .. (dir > 0 and " - 1" or " + 1")
  end

  -- границы диапазона/среза: возвращает lo, hi, step (строки Lua или nil)
  local function bounds(node)
    local lo = node.lo and expr(node.lo) or nil
    local hi = node.hi and expr(node.hi) or nil
    local step = node.step and expr(node.step) or nil
    if lo and not node.lo_incl then lo = adjust_bound(lo, 1, node.step) end
    if hi and not node.hi_incl then hi = adjust_bound(hi, -1, node.step) end
    return lo, hi, step
  end

  function E.Number(n) return n.v end
  function E.String(n) return U.quote(n.v) end
  function E.Bool(n) return n.v and "true" or "false" end
  function E.Nil() return "nil" end
  function E.Name(n) return ref(n.name, n.line) end
  function E.Paren(n) return "(" .. expr(n.e) .. ")" end
  function E.LuaExpr(n) return "(" .. n.code .. ")" end

  function E.FString(n)
    local parts = {}
    for _, p in ipairs(n.parts) do
      if p.kind == "str" then
        parts[#parts + 1] = U.quote(p.v)
      elseif p.spec then
        parts[#parts + 1] = "__rt.fmt(" .. expr(p.node) .. ", " .. U.quote(p.spec) .. ")"
      elseif p.node.tag == "String" then
        parts[#parts + 1] = U.quote(p.node.v)
      else
        parts[#parts + 1] = "__tostring(" .. expr(p.node) .. ")"
      end
    end
    if #parts == 0 then return '""' end
    if #parts == 1 and n.parts[1].kind == "str" then return parts[1] end
    return "(" .. table.concat(parts, " .. ") .. ")"
  end

  function E.List(n)
    local has_spread = false
    for _, it in ipairs(n.items) do
      if it.tag == "Spread" then has_spread = true end
    end
    if not has_spread then
      local items = {}
      for k, it in ipairs(n.items) do
        local code = expr(it)
        if k == #n.items and (it.tag == "Call" or it.tag == "Method" or it.tag == "LuaExpr") then
          code = "(" .. code .. ")"
        end
        items[k] = code
      end
      return "{" .. table.concat(items, ", ") .. "}"
    end
    local pieces, run = {}, {}
    local function flush()
      if #run > 0 then
        pieces[#pieces + 1] = "{" .. table.concat(run, ", ") .. "}"
        run = {}
      end
    end
    for _, it in ipairs(n.items) do
      if it.tag == "Spread" then
        flush()
        pieces[#pieces + 1] = expr(it.e)
      else
        run[#run + 1] = "(" .. expr(it) .. ")"
      end
    end
    flush()
    return "__rt.cat(" .. table.concat(pieces, ", ") .. ")"
  end

  local function dict_entry(en)
    local v = expr(en.value)
    if en.kind == "name" or en.kind == "str" then
      if U.is_lua_name(en.key) then return en.key .. " = " .. v end
      return "[" .. U.quote(en.key) .. "] = " .. v
    elseif en.kind == "num" then
      return "[" .. en.key .. "] = " .. v
    end
    return "[" .. expr(en.key) .. "] = " .. v
  end

  function E.Dict(n)
    local has_spread = false
    for _, en in ipairs(n.entries) do
      if en.kind == "spread" then has_spread = true end
    end
    if not has_spread then
      local items = {}
      for _, en in ipairs(n.entries) do items[#items + 1] = dict_entry(en) end
      return "{" .. table.concat(items, ", ") .. "}"
    end
    local pieces, run = {}, {}
    local function flush()
      if #run > 0 then
        pieces[#pieces + 1] = "{" .. table.concat(run, ", ") .. "}"
        run = {}
      end
    end
    for _, en in ipairs(n.entries) do
      if en.kind == "spread" then
        flush()
        pieces[#pieces + 1] = expr(en.value)
      else
        run[#run + 1] = dict_entry(en)
      end
    end
    flush()
    return "__rt.merge(" .. table.concat(pieces, ", ") .. ")"
  end

  function E.Index(n)
    return base_expr(n.obj) .. "[" .. expr(n.idx) .. "]"
  end

  function E.Slice(n)
    local lo, hi, step = bounds(n)
    return "__rt.slice(" .. expr(n.obj) .. ", " .. (lo or "nil") .. ", " .. (hi or "nil") .. ", " .. (step or "nil") .. ")"
  end

  function E.Attr(n)
    if n.opt then
      return "__rt.oget(" .. expr(n.obj) .. ", " .. U.quote(n.name) .. ")"
    end
    return attr_access(base_expr(n.obj), n.name)
  end

  local function call_args(args)
    local r = {}
    for k, a in ipairs(args) do
      if a.tag == "Spread" then
        r[k] = "__rt.unpack_list(" .. expr(a.e) .. ")"
      else
        r[k] = expr(a)
      end
    end
    return r
  end

  local function kw_table(kwargs)
    local items = {}
    for _, kw in ipairs(kwargs) do
      items[#items + 1] = "[" .. U.quote(kw.name) .. "] = " .. expr(kw.value)
    end
    return "{" .. table.concat(items, ", ") .. "}"
  end

  function E.Call(n)
    local args = call_args(n.args)
    if n.kwargs then
      local all = { kw_table(n.kwargs) }
      for _, a in ipairs(args) do all[#all + 1] = a end
      return "__rt.kcall(" .. expr(n.fn) .. ", " .. table.concat(all, ", ") .. ")"
    end
    return base_expr(n.fn) .. "(" .. table.concat(args, ", ") .. ")"
  end

  function E.Method(n)
    if RESERVED[n.name] then
      fail(n.line, "method name '" .. n.name .. "' is a Lua keyword and cannot be called with ':'")
    end
    local args = call_args(n.args)
    if n.kwargs then
      local all = { expr(n.obj), U.quote(n.name), kw_table(n.kwargs) }
      for _, a in ipairs(args) do all[#all + 1] = a end
      return "__rt.kcallm(" .. table.concat(all, ", ") .. ")"
    end
    return base_expr(n.obj) .. ":" .. n.name .. "(" .. table.concat(args, ", ") .. ")"
  end

  function E.Unary(n)
    if n.op == "-" then return "(-" .. expr(n.e) .. ")" end
    return "(not " .. expr(n.e) .. ")"
  end

  local SIMPLE_NODE = U.set({ "Number", "String", "Bool", "Nil", "Name" })

  function E.Binary(n)
    local op = n.op
    local l, r = expr(n.l), expr(n.r)
    if op == "and" or op == "or" then
      return "(" .. l .. " " .. op .. " " .. r .. ")"
    elseif op == "??" then
      if SIMPLE_NODE[n.r.tag] then
        return "__rt.nvl(" .. l .. ", " .. r .. ")"
      end
      return "__rt.nvl_lazy(" .. l .. ", function() return " .. r .. " end)"
    elseif op == "==" or op == "is" then
      return "(" .. l .. " == " .. r .. ")"
    elseif op == "!=" or op == "is not" then
      return "(" .. l .. " ~= " .. r .. ")"
    elseif op == "in" then
      return "__rt.contains(" .. r .. ", " .. l .. ")"
    elseif op == "not in" then
      return "(not __rt.contains(" .. r .. ", " .. l .. "))"
    elseif op == "//" then
      return "__floor(" .. l .. " / " .. r .. ")"
    elseif op == "**" then
      return "(" .. l .. " ^ " .. r .. ")"
    end
    return "(" .. l .. " " .. op .. " " .. r .. ")"
  end

  function E.Ternary(n)
    local c, a, b = expr(n.cond), expr(n.a), expr(n.b)
    if SAFE_TRUTHY[n.a.tag] or (n.a.tag == "Bool" and n.a.v) then
      return "(" .. c .. " and " .. a .. " or " .. b .. ")"
    end
    return "(function() if " .. c .. " then return " .. a .. " else return " .. b .. " end end)()"
  end

  function E.Lambda(n)
    push_scope(true)
    local plist = {}
    for k, p in ipairs(n.params) do
      plist[k] = declare(p, "param", n.line)
    end
    local body = expr(n.body)
    pop_scope()
    return "(function(" .. table.concat(plist, ", ") .. ") return " .. body .. " end)"
  end

  -- генераторы: возвращает IIFE-строку
  local function comprehension(clauses, init, body_fn)
    push_scope(true)
    local head, closers, pops = {}, 0, 0
    for _, c in ipairs(clauses) do
      if c.kind == "for" then
        local it = c.iter
        local header
        if it.tag == "Range" then
          local lo, hi, step = bounds(it)
          push_scope(false)
          pops = pops + 1
          local v = declare(c.vars[1], "local", c.line)
          header = "for " .. v .. " = " .. lo .. ", " .. hi .. (step and (", " .. step) or "") .. " do "
        else
          local src = expr(it)
          push_scope(false)
          pops = pops + 1
          local vars = {}
          for k, name in ipairs(c.vars) do vars[k] = declare(name, "local", c.line) end
          header = "for " .. table.concat(vars, ", ") .. " in " .. ((#vars == 1) and "__rt.iter1(" or "__rt.iter2(") .. src .. ") do "
        end
        head[#head + 1] = header
        closers = closers + 1
      else
        head[#head + 1] = "if " .. expr(c.cond) .. " then "
        closers = closers + 1
      end
    end
    local body = body_fn()
    for _ = 1, pops do pop_scope() end
    pop_scope()
    return "(function() " .. init .. table.concat(head) .. body .. string.rep("end ", closers) .. "return __r end)()"
  end

  function E.ListComp(n)
    return comprehension(n.clauses, "local __r, __n = {}, 0 ", function()
      return "__n = __n + 1 __r[__n] = (" .. expr(n.elem) .. ") "
    end)
  end

  function E.DictComp(n)
    return comprehension(n.clauses, "local __r = {} ", function()
      return "__r[" .. expr(n.key) .. "] = " .. expr(n.value) .. " "
    end)
  end

  ---------------------------------------------------------------- управление потоком

  local function find_loop(what, line)
    local crossed = {}
    for k = #ctx, 1, -1 do
      local c = ctx[k]
      if c.kind == "loop" then
        return c, crossed
      elseif c.kind == "try" or c.kind == "catch" then
        crossed[#crossed + 1] = c
      elseif c.kind == "finally" then
        fail(line, "'" .. what .. "' is not allowed inside a finally block")
      else
        break
      end
    end
    fail(line, "'" .. what .. "' outside of a loop")
  end

  local function emit_break(line)
    local _, crossed = find_loop("break", line)
    if #crossed == 0 then
      emit("do break end")
    else
      crossed[1].shared.uses_brk = true
      emit("do return __rt.BRK end")
    end
  end

  local function emit_continue(line)
    local target, crossed = find_loop("continue", line)
    if #crossed == 0 then
      target.cont_used = true
      emit("goto " .. target.label)
    else
      crossed[1].shared.uses_cnt = true
      emit("do return __rt.CNT end")
    end
  end

  local function emit_return(values_code, packed_code, line)
    local crossed
    for k = #ctx, 1, -1 do
      local c = ctx[k]
      if c.kind == "try" or c.kind == "catch" then
        crossed = crossed or c
      elseif c.kind == "finally" then
        fail(line, "'return' is not allowed inside a finally block")
      elseif c.kind == "func" then
        break
      elseif c.kind == "module" then
        fail(line, "'return' outside of a function")
      end
    end
    if not crossed then
      if packed_code then
        emit("do return __rt.unpack(" .. packed_code .. ") end")
      else
        emit("do return " .. values_code .. " end")
      end
    else
      crossed.shared.uses_ret = true
      if packed_code then
        emit("do return __rt.RET, " .. packed_code .. " end")
      else
        emit("do return __rt.RET, __rt.pack(" .. values_code .. ") end")
      end
    end
  end

  ---------------------------------------------------------------- инструкции

  local S = {}

  function block(stmts)
    for _, s in ipairs(stmts) do
      stmt(s)
    end
  end

  local function scoped_block(stmts)
    push_scope(false)
    level = level + 1
    block(stmts)
    level = level - 1
    pop_scope()
  end

  function stmt(s)
    curline = s.line or curline
    if opts.keep_comments then flush_comments(curline) end
    S[s.tag](s)
  end

  local function record_export(name, line)
    if #ctx > 1 or (scope and scope.parent) then
      fail(line, "export is only allowed at the top level of a module")
    end
    exports[#exports + 1] = name
  end

  local function target_code(t)
    if t.tag == "Name" then
      local info = lookup(t.name)
      if not info then
        check_name(t.name, t.line)
        fail(t.line, "internal: assignment to undeclared name '" .. t.name .. "'")
      end
      if info.kind == "const" then
        fail(t.line, "cannot assign to constant '" .. t.name .. "'")
      end
      return info.lname
    elseif t.tag == "Index" then
      return base_expr(t.obj) .. "[" .. expr(t.idx) .. "]"
    else
      return attr_access(base_expr(t.obj), t.name)
    end
  end

  function S.Pass() end

  function S.TypeAlias() end

  function S.ModeBlock(s)
    scoped_block(s.body)
  end

  function S.AnnAssign(s)
    if s.value then
      emit(target_code({ tag = "Name", name = s.name, line = s.line }) .. " = " .. expr(s.value))
    end
    if s.exported then record_export(s.name, s.line) end
  end

  function S.ExprStmt(s)
    local e = s.e
    local tag = e.tag
    if tag == "String" or tag == "Number" or tag == "Bool" or tag == "Nil" then return end
    local code = expr(e)
    if (tag == "Call" or tag == "Method") and code:sub(1, 1) ~= "(" then
      emit(code)
    else
      emit("do local _ = " .. code .. " end")
    end
  end

  -- распаковка списка в цели: targets_codes[i] (строка или nil для пропуска), star: индекс или nil
  local function emit_unpack(target_codes, star, rhs_code)
    local id = nextid()
    local t = "__t" .. id
    local n = #target_codes
    emit("do local " .. t .. " = " .. rhs_code)
    for k = 1, n do
      local code = target_codes[k]
      if star and k == star then
        local after = n - star
        emit("  " .. code .. " = __rt.slice(" .. t .. ", " .. star .. ", #" .. t .. " - " .. after .. ")")
      elseif star and k > star then
        emit("  " .. code .. " = " .. t .. "[#" .. t .. " - " .. (n - k) .. "]")
      else
        emit("  " .. code .. " = " .. t .. "[" .. k .. "]")
      end
    end
    emit("end")
  end

  function S.Assign(s)
    local star
    for k, t in ipairs(s.targets) do
      if t.tag == "Starred" then star = k end
    end
    local single = s.values[1]
    local unpack_list = star ~= nil or (#s.targets >= 2 and #s.values == 1 and single.tag ~= "Call" and single.tag ~= "Method" and single.tag ~= "LuaExpr")
    if unpack_list then
      local rhs = expr(single)
      local codes = {}
      for k, t in ipairs(s.targets) do
        if t.tag == "Starred" then
          codes[k] = target_code({ tag = "Name", name = t.name, line = t.line })
        else
          codes[k] = target_code(t)
        end
      end
      emit_unpack(codes, star, rhs)
    else
      local lhs, rhs = {}, exprs(s.values)
      for k, t in ipairs(s.targets) do lhs[k] = target_code(t) end
      emit(table.concat(lhs, ", ") .. " = " .. table.concat(rhs, ", "))
    end
    if s.exported then
      for _, t in ipairs(s.targets) do
        if t.tag == "Name" then record_export(t.name, s.line) end
      end
    end
  end

  local function binop_code(op, l, r)
    if op == "//" then return "__floor(" .. l .. " / " .. r .. ")" end
    if op == "**" then return "(" .. l .. " ^ " .. r .. ")" end
    return "(" .. l .. " " .. op .. " " .. r .. ")"
  end

  function S.AugAssign(s)
    local t = s.target
    if t.tag == "Name" then
      if not lookup(t.name) then
        fail(s.line, "variable '" .. t.name .. "' is used in '" .. s.op .. "=' before it is defined")
      end
      local name = target_code(t)
      emit(name .. " = " .. binop_code(s.op, name, expr(s.value)))
    elseif t.obj.tag == "Name" and (t.tag == "Attr" or t.idx.tag == "Number" or t.idx.tag == "String" or t.idx.tag == "Name") then
      local target = target_code(t)
      emit(target .. " = " .. binop_code(s.op, target, expr(s.value)))
    else
      local id = nextid()
      local o, k = "__o" .. id, "__k" .. id
      local key
      if t.tag == "Index" then key = expr(t.idx) else key = U.quote(t.name) end
      emit("do local " .. o .. ", " .. k .. " = " .. base_expr(t.obj) .. ", " .. key)
      emit("  " .. o .. "[" .. k .. "] = " .. binop_code(s.op, o .. "[" .. k .. "]", expr(s.value)) .. " end")
    end
  end

  local function let_like(s, kind, names, values)
    local codes = exprs(values)
    local decl = {}
    for k, name in ipairs(names) do
      if B.PROTECTED[name] and s.tag ~= "Override" then protected_error(name, s.line) end
      if B.SHADOW_WARN[name] and s.tag ~= "Override" then warn(s.line, "'" .. name .. "' hides the CC global of the same name in this scope") end
      decl[k] = declare(name, kind, s.line)
    end
    if s.star then
      emit("local " .. table.concat(decl, ", "))
      emit_unpack(decl, s.star, codes[1])
    elseif #codes > 0 then
      emit("local " .. table.concat(decl, ", ") .. " = " .. table.concat(codes, ", "))
    else
      emit("local " .. table.concat(decl, ", "))
    end
    if s.exported then
      for _, name in ipairs(names) do record_export(name, s.line) end
    end
  end

  function S.Let(s) let_like(s, "local", s.names, s.values) end
  function S.Const(s) let_like(s, "const", { s.name }, { s.value }) end
  function S.Override(s) let_like(s, "local", { s.name }, { s.value }) end

  function S.Return(s)
    emit_return(table.concat(exprs(s.values), ", "), nil, s.line)
  end

  function S.Break(s) emit_break(s.line) end
  function S.Continue(s) emit_continue(s.line) end

  function S.Raise(s)
    if s.value then
      emit("__error(" .. expr(s.value) .. ", 0)")
      return
    end
    for k = #ctx, 1, -1 do
      local c = ctx[k]
      if c.kind == "catch" then
        emit("__rt.rethrow(__e)")
        return
      elseif c.kind == "func" or c.kind == "module" then
        break
      end
    end
    fail(s.line, "a bare 'raise' is only allowed inside an except block")
  end

  function S.If(s)
    emit("if " .. expr(s.cond) .. " then")
    scoped_block(s.body)
    for _, e in ipairs(s.elifs) do
      curline = e.line
      emit("elseif " .. expr(e.cond) .. " then")
      scoped_block(e.body)
    end
    if s.orelse then
      emit("else")
      scoped_block(s.orelse)
    end
    emit("end")
  end

  local function loop_body()
    local label = "__cont" .. nextid()
    local lc = { kind = "loop", label = label, cont_used = false }
    ctx[#ctx + 1] = lc
    return lc
  end

  local function end_loop(lc)
    if lc.cont_used then
      level = level + 1
      emit("::" .. lc.label .. "::")
      level = level - 1
    end
    ctx[#ctx] = nil
    emit("end")
  end

  function S.While(s)
    emit("while " .. expr(s.cond) .. " do")
    local lc = loop_body()
    scoped_block(s.body)
    end_loop(lc)
  end

  function S.ForRange(s)
    local lo, hi, step = bounds(s.range)
    push_scope(false)
    if B.PROTECTED[s.var] or B.SHADOW_WARN[s.var] then warn(s.line, "loop variable '" .. s.var .. "' shadows a builtin") end
    local v = declare(s.var, "local", s.line)
    emit("for " .. v .. " = " .. lo .. ", " .. hi .. (step and (", " .. step) or "") .. " do")
    local lc = loop_body()
    level = level + 1
    block(s.body)
    level = level - 1
    end_loop(lc)
    pop_scope()
  end

  function S.ForIn(s)
    local src = expr(s.iter)
    push_scope(false)
    local vars = {}
    for k, v in ipairs(s.vars) do
      if B.PROTECTED[v] or B.SHADOW_WARN[v] then warn(s.line, "loop variable '" .. v .. "' shadows a builtin") end
      vars[k] = declare(v, "local", s.line)
    end
    local it = (#s.vars == 1) and "__rt.iter1(" or "__rt.iter2("
    emit("for " .. table.concat(vars, ", ") .. " in " .. it .. src .. ") do")
    local lc = loop_body()
    level = level + 1
    block(s.body)
    level = level - 1
    end_loop(lc)
    pop_scope()
  end

  -- тело функции. header: текст до "(" ("name = __rt.sig(function"); sig: строка имён параметров или nil
  local function function_body(header, params, vararg, body, line, sig)
    local plist = {}
    push_scope(true)
    local sig_names = {}
    for k, p in ipairs(params) do
      if B.PROTECTED[p.name] or B.SHADOW_WARN[p.name] then warn(p.line, "parameter '" .. p.name .. "' shadows a builtin") end
      plist[k] = declare(p.name, "param", p.line)
      sig_names[k] = p.name
    end
    if vararg then
      declare(vararg, "param", line)
      plist[#plist + 1] = "..."
    end
    emit(header .. "(" .. table.concat(plist, ", ") .. ")")
    level = level + 1
    ctx[#ctx + 1] = { kind = "func" }
    for _, p in ipairs(params) do
      if p.default then
        local n = lname_of(p.name)
        emit("if " .. n .. " == nil then " .. n .. " = " .. expr(p.default) .. " end")
      end
    end
    if vararg then emit("local " .. lname_of(vararg) .. " = {...}") end
    hoist(body)
    block(body)
    ctx[#ctx] = nil
    level = level - 1
    pop_scope()
    if sig then
      emit("end, " .. U.quote(table.concat(sig_names, ",")) .. ")")
    else
      emit("end")
    end
  end

  local function apply_decorators(decorators, target)
    if not decorators then return end
    for k = #decorators, 1, -1 do
      emit(target .. " = " .. expr(decorators[k]) .. "(" .. target .. ")")
    end
  end

  function S.FuncDef(s)
    local info = lookup(s.name)
    if info and info.kind == "const" then fail(s.line, "cannot redefine constant '" .. s.name .. "'") end
    local target = lname_of(s.name)
    function_body(target .. " = __rt.sig(function", s.params, s.vararg, s.body, s.line, true)
    apply_decorators(s.decorators, target)
    if s.exported then record_export(s.name, s.line) end
  end

  function S.ClassDef(s)
    local info = lookup(s.name)
    if info and info.kind == "const" then fail(s.line, "cannot redefine constant '" .. s.name .. "'") end
    local cname = lname_of(s.name)
    emit(cname .. " = __rt.class(" .. U.quote(s.name) .. ", " .. (s.base and expr(s.base) or "nil") .. ")")
    class_stack[#class_stack + 1] = cname
    for _, m in ipairs(s.body) do
      curline = m.line or curline
      if opts.keep_comments then flush_comments(curline) end
      if m.tag == "FuncDef" then
        local target = U.is_lua_name(m.name) and (cname .. "." .. m.name) or (cname .. "[" .. U.quote(m.name) .. "]")
        function_body(target .. " = __rt.sig(function", m.params, m.vararg, m.body, m.line, true)
        apply_decorators(m.decorators, target)
      elseif m.tag == "Assign" and #m.targets == 1 and m.targets[1].tag == "Name" and #m.values == 1 then
        local fname = m.targets[1].name
        local target = U.is_lua_name(fname) and (cname .. "." .. fname) or (cname .. "[" .. U.quote(fname) .. "]")
        emit(target .. " = " .. expr(m.values[1]))
      elseif m.tag == "AnnAssign" then
        if m.value then
          local target = U.is_lua_name(m.name) and (cname .. "." .. m.name) or (cname .. "[" .. U.quote(m.name) .. "]")
          emit(target .. " = " .. expr(m.value))
        end
      elseif m.tag == "Pass" or (m.tag == "ExprStmt" and m.e.tag == "String") then
        -- ничего
      else
        fail(m.line, "only methods (def) and simple fields (name = value) are allowed in a class body")
      end
    end
    class_stack[#class_stack] = nil
    apply_decorators(s.decorators, cname)
    if s.exported then record_export(s.name, s.line) end
  end

  function S.Import(s)
    emit(lname_of(s.name) .. " = __import(" .. U.quote(s.path) .. ")")
    if s.exported then record_export(s.name, s.line) end
  end

  function S.FromImport(s)
    local id = nextid()
    local m = "__m" .. id
    emit("do local " .. m .. " = __import(" .. U.quote(s.path) .. ")")
    for _, n in ipairs(s.names) do
      local info = lookup(n.alias)
      if info and info.kind == "const" then fail(n.line, "cannot assign to constant '" .. n.alias .. "'") end
      emit("  " .. lname_of(n.alias) .. " = " .. attr_access(m, n.name))
    end
    emit("end")
  end

  function S.LuaBlock(s)
    local base = s.line
    local k = 0
    for line in (s.code .. "\n"):gmatch("([^\n]*)\n") do
      curline = base + k
      emit(line)
      k = k + 1
    end
    curline = base
  end

  function S.Try(s)
    local id = nextid()
    local cvar, vvar = "__c" .. id, "__v" .. id
    local shared = { uses_ret = false, uses_brk = false, uses_cnt = false }
    emit("do local " .. cvar .. ", " .. vvar .. " = __rt.try(function()")
    ctx[#ctx + 1] = { kind = "try", shared = shared }
    scoped_block(s.body)
    ctx[#ctx] = nil

    if #s.handlers > 0 then
      curline = s.handlers[1].line
      emit("end, function(__e)")
      ctx[#ctx + 1] = { kind = "catch", shared = shared }
      level = level + 1
      emit("__e = __rt.wrap(__e)")
      local first = true
      local bare
      for _, h in ipairs(s.handlers) do
        curline = h.line
        if h.type then
          emit((first and "if " or "elseif ") .. "__rt.isinstance(__e, " .. expr(h.type) .. ") then")
          first = false
          push_scope(false)
          level = level + 1
          if h.name then
            local v = declare(h.name, "local", h.line)
            emit("local " .. v .. " = __e")
          end
          block(h.body)
          level = level - 1
          pop_scope()
        else
          bare = h
        end
      end
      if bare then
        curline = bare.line
        if first then
          emit("do")
        else
          emit("else")
        end
        push_scope(false)
        level = level + 1
        if bare.name then
          local v = declare(bare.name, "local", bare.line)
          emit("local " .. v .. " = __e")
        end
        block(bare.body)
        level = level - 1
        pop_scope()
        emit("end")
      else
        emit("else")
        emit("  __rt.rethrow(__e)")
        emit("end")
      end
      level = level - 1
      ctx[#ctx] = nil
    end

    if s.finally then
      emit(#s.handlers > 0 and "end, function()" or "end, nil, function()")
      ctx[#ctx + 1] = { kind = "finally" }
      scoped_block(s.finally)
      ctx[#ctx] = nil
    end
    emit("end)")

    if shared.uses_ret then
      emit("if " .. cvar .. " == __rt.RET then")
      level = level + 1
      emit_return(nil, vvar, s.line)
      level = level - 1
      emit("end")
    end
    if shared.uses_brk then
      emit("if " .. cvar .. " == __rt.BRK then")
      level = level + 1
      emit_break(s.line)
      level = level - 1
      emit("end")
    end
    if shared.uses_cnt then
      emit("if " .. cvar .. " == __rt.CNT then")
      level = level + 1
      emit_continue(s.line)
      level = level - 1
      emit("end")
    end
    emit("end")
  end

  function S.With(s)
    emit("do")
    push_scope(false)
    level = level + 1
    local code = expr(s.expr)
    local v = declare(s.name, "local", s.line)
    emit("local " .. v .. " = " .. code)
    S.Try({ tag = "Try", body = s.body, handlers = {}, finally = { { tag = "Release", name = s.name, line = s.line } }, line = s.line })
    level = level - 1
    pop_scope()
    emit("end")
  end

  function S.Release(s)
    emit("__rt.release(" .. lname_of(s.name) .. ")")
  end

  ---------------------------------------------------------------- match

  local function pat_check(p, path, caps)
    local tag = p.tag
    if tag == "PWild" then
      return "true"
    elseif tag == "PLit" then
      return path .. " == " .. expr(p.node)
    elseif tag == "PValue" then
      return path .. " == " .. expr(p.expr)
    elseif tag == "PCapture" then
      if p.name ~= "_" then caps[#caps + 1] = { name = p.name, path = path } end
      return "true"
    elseif tag == "POr" then
      local parts = {}
      for _, alt in ipairs(p.alts) do
        local sub = {}
        parts[#parts + 1] = "(" .. pat_check(alt, path, sub) .. ")"
        if #sub > 0 then fail(p.line, "captures are not allowed inside or-patterns ('|')") end
      end
      return "(" .. table.concat(parts, " or ") .. ")"
    elseif tag == "PList" then
      local n = #p.items
      local conds = { '__type(' .. path .. ') == "table"' }
      if p.star then
        conds[#conds + 1] = "#" .. path .. " >= " .. n
      else
        conds[#conds + 1] = "#" .. path .. " == " .. n
      end
      for k, item in ipairs(p.items) do
        local idx
        if p.star and k >= p.star then
          idx = "#" .. path .. " - " .. (n - k)
        else
          idx = tostring(k)
        end
        conds[#conds + 1] = pat_check(item, path .. "[" .. idx .. "]", caps)
      end
      if p.star_name and p.star_name ~= "_" then
        caps[#caps + 1] = { name = p.star_name, path = "__rt.slice(" .. path .. ", " .. p.star .. ", #" .. path .. " - " .. (n - p.star + 1) .. ")" }
      end
      return table.concat(conds, " and ")
    elseif tag == "PDict" then
      local conds = { '__type(' .. path .. ') == "table"' }
      for _, e in ipairs(p.entries) do
        local kp
        if e.key.kind == "str" then kp = attr_access(path, e.key.v) else kp = path .. "[" .. e.key.v .. "]" end
        conds[#conds + 1] = kp .. " ~= nil"
        conds[#conds + 1] = pat_check(e.pat, kp, caps)
      end
      return table.concat(conds, " and ")
    elseif tag == "PClass" then
      local cls = expr(p.cls)
      local conds = { "__rt.isinstance(" .. path .. ", " .. cls .. ")" }
      for i, a in ipairs(p.args) do
        conds[#conds + 1] = pat_check(a, "__rt.match_attr(" .. path .. ", " .. cls .. ", " .. i .. ")", caps)
      end
      for _, kw in ipairs(p.kwargs) do
        conds[#conds + 1] = pat_check(kw.pat, attr_access(path, kw.name), caps)
      end
      return table.concat(conds, " and ")
    end
    fail(p.line, "internal: unknown pattern " .. tostring(tag))
  end

  function S.Match(s)
    local id = nextid()
    local sv, dv = "__s" .. id, "__d" .. id
    emit("do local " .. sv .. ", " .. dv .. " = " .. expr(s.subject) .. ", false")
    level = level + 1
    for _, c in ipairs(s.cases) do
      curline = c.line
      local caps = {}
      local cond = pat_check(c.pattern, sv, caps)
      emit("if not " .. dv .. " and " .. cond .. " then")
      level = level + 1
      push_scope(false)
      for _, cap in ipairs(caps) do
        emit(target_code({ tag = "Name", name = cap.name, line = c.line }) .. " = " .. cap.path)
      end
      if c.guard then
        emit("if " .. expr(c.guard) .. " then")
        level = level + 1
      end
      emit(dv .. " = true")
      block(c.body)
      if c.guard then
        level = level - 1
        emit("end")
      end
      pop_scope()
      level = level - 1
      emit("end")
    end
    level = level - 1
    emit("end")
  end

  ---------------------------------------------------------------- модуль

  curline = 1
  if opts.banner ~= false then
    emit("-- Generated by Cubic " .. (opts.version or "?") .. " from " .. file .. " (" .. (opts.src_info or "") .. "). Do not edit.")
  end
  emit("local __rt, __import = ...")
  emit("local __floor, __tostring, __tonumber, __error, __type = math.floor, tostring, tonumber, error, type")
  emit("local __exports = {}")
  push_scope(true)
  ctx[#ctx + 1] = { kind = "module" }
  hoist(ast.body)
  block(ast.body)
  if opts.keep_comments then flush_comments(math.huge) end
  for _, name in ipairs(exports) do
    emit("__exports[" .. U.quote(name) .. "] = " .. lname_of(name))
  end
  emit("return __exports")

  return table.concat(out, "\n") .. "\n", lmap, warnings
end

return M
