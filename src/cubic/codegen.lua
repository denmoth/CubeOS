-- Cubic: генератор Lua
local U, B = ...

local M = {}

local RESERVED = U.LUA_RESERVED

local function mangle(name)
  if RESERVED[name] then return "__k_" .. name end
  return name
end

function M.generate(ast, file, opts)
  opts = opts or {}
  local out, lmap = {}, {}
  local level = 0
  local curline = 1
  local warnings = {}
  local scope = nil
  local ctx = {}
  local idseq = 0
  local exports = {}

  local function fail(line, msg)
    U.fail(file, line or curline, 1, msg)
  end

  local function warn(line, msg)
    warnings[#warnings + 1] = file .. ":" .. (line or curline) .. ": warning: " .. msg
  end

  local function emit(s)
    out[#out + 1] = string.rep("  ", level) .. s
    lmap[#lmap + 1] = curline
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

  local function declare(name, kind, line)
    check_name(name, line)
    scope.names[name] = { kind = kind }
  end

  local function protected_error(name, line)
    fail(line, "cannot assign to builtin '" .. name .. "' (use 'override " .. name .. " = ...' to replace it deliberately)")
  end

  -- собирает имена, которые инструкции объявляют на уровне функции (как переменные Python)
  local function collect(stmts, names, seen)
    local function add(name, line)
      if not seen[name] then
        seen[name] = true
        names[#names + 1] = { name = name, line = line }
      end
    end
    for _, s in ipairs(stmts) do
      local tag = s.tag
      if tag == "Assign" then
        for _, t in ipairs(s.targets) do
          if t.tag == "Name" then add(t.name, s.line) end
        end
      elseif tag == "FuncDef" or tag == "ClassDef" or tag == "Import" then
        add(s.name, s.line)
      elseif tag == "FromImport" then
        for _, n in ipairs(s.names) do add(n.alias, n.line) end
      elseif tag == "If" then
        collect(s.body, names, seen)
        for _, e in ipairs(s.elifs) do collect(e.body, names, seen) end
        if s.orelse then collect(s.orelse, names, seen) end
      elseif tag == "While" or tag == "ForRange" or tag == "ForIn" then
        collect(s.body, names, seen)
      elseif tag == "Try" then
        collect(s.body, names, seen)
        for _, h in ipairs(s.handlers) do collect(h.body, names, seen) end
        if s.finally then collect(s.finally, names, seen) end
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
      if not scope.names[name] and not lookup_from(scope.parent, name) then
        if B.PROTECTED[name] then protected_error(name, n.line) end
        if B.SHADOW_WARN[name] then warn(n.line, "'" .. name .. "' hides the CC global of the same name in this scope") end
        declare(name, "local", n.line)
        decl[#decl + 1] = mangle(name)
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
    if info then return mangle(name) end
    if B.MAP[name] then return B.MAP[name] end
    if RESERVED[name] then
      fail(line, "'" .. name .. "' is a reserved word in Lua and cannot be used as a global name")
    end
    return name
  end

  ---------------------------------------------------------------- выражения

  local E = {}
  local expr, block, stmt

  local SAFE_TRUTHY = U.set({ "Number", "String", "FString", "List", "Dict", "Lambda" })
  local NEEDS_PAREN = U.set({ "Number", "String", "FString", "List", "Dict", "Lambda", "Bool", "Nil", "Binary", "Unary", "Ternary", "LuaExpr" })

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

  function E.Dict(n)
    local items = {}
    for _, en in ipairs(n.entries) do
      local v = expr(en.value)
      if en.kind == "name" or en.kind == "str" then
        if U.is_lua_name(en.key) then
          items[#items + 1] = en.key .. " = " .. v
        else
          items[#items + 1] = "[" .. U.quote(en.key) .. "] = " .. v
        end
      elseif en.kind == "num" then
        items[#items + 1] = "[" .. en.key .. "] = " .. v
      else
        items[#items + 1] = "[" .. expr(en.key) .. "] = " .. v
      end
    end
    return "{" .. table.concat(items, ", ") .. "}"
  end

  function E.Index(n)
    return base_expr(n.obj) .. "[" .. expr(n.idx) .. "]"
  end

  function E.Attr(n)
    if n.opt then
      return "__rt.oget(" .. expr(n.obj) .. ", " .. U.quote(n.name) .. ")"
    end
    return attr_access(base_expr(n.obj), n.name)
  end

  function E.Call(n)
    return base_expr(n.fn) .. "(" .. table.concat(exprs(n.args), ", ") .. ")"
  end

  function E.Method(n)
    if RESERVED[n.name] then
      fail(n.line, "method name '" .. n.name .. "' is a Lua keyword and cannot be called with ':'")
    end
    return base_expr(n.obj) .. ":" .. n.name .. "(" .. table.concat(exprs(n.args), ", ") .. ")"
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
    -- + - * / % .. < <= > >=
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
      declare(p, "param", n.line)
      plist[k] = mangle(p)
    end
    local body = expr(n.body)
    pop_scope()
    return "(function(" .. table.concat(plist, ", ") .. ") return " .. body .. " end)"
  end

  ---------------------------------------------------------------- управление потоком

  -- Ищет цель break/continue; возвращает (цель, список пересечённых замыканий try)
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
    local target, crossed = find_loop("break", line)
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

  -- values_code: строка со списком значений; packed_code: имя упакованной таблицы (взаимоисключающие)
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
      return mangle(t.name)
    elseif t.tag == "Index" then
      return base_expr(t.obj) .. "[" .. expr(t.idx) .. "]"
    else
      return attr_access(base_expr(t.obj), t.name)
    end
  end

  function S.Pass() end

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

  function S.Assign(s)
    local lhs, rhs = {}, exprs(s.values)
    for k, t in ipairs(s.targets) do lhs[k] = target_code(t) end
    emit(table.concat(lhs, ", ") .. " = " .. table.concat(rhs, ", "))
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
      -- объект и ключ простые, двойное вычисление безопасно
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
      declare(name, kind, s.line)
      decl[k] = mangle(name)
    end
    if #codes > 0 then
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

  local function loop_body(s, label_holder)
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
    local lc = loop_body(s)
    scoped_block(s.body)
    end_loop(lc)
  end

  local function sign_code(step_node)
    if not step_node then return "1", 1 end
    local n = step_node
    if n.tag == "Number" then
      return nil, (tonumber(n.v) or 1) >= 0 and 1 or -1
    elseif n.tag == "Unary" and n.op == "-" and n.e.tag == "Number" then
      return nil, -1
    end
    return "(" .. expr(step_node) .. " > 0 and 1 or -1)", nil
  end

  function S.ForRange(s)
    local r = s.range
    local lo, hi = expr(r.lo), expr(r.hi)
    local step = r.step and expr(r.step)
    local dyn, sign = sign_code(r.step)
    local function adjust(code, dir)
      -- dir: +1 прибавить знак шага, -1 вычесть знак шага
      local op = dir > 0 and " + " or " - "
      if dyn then return "(" .. code .. ")" .. op .. dyn end
      if sign == 1 or dyn == "1" then return "(" .. code .. ")" .. op .. "1" end
      return "(" .. code .. ")" .. (dir > 0 and " - 1" or " + 1")
    end
    if not r.lo_incl then lo = adjust(lo, 1) end
    if not r.hi_incl then hi = adjust(hi, -1) end
    push_scope(false)
    if B.PROTECTED[s.var] or B.SHADOW_WARN[s.var] then warn(s.line, "loop variable '" .. s.var .. "' shadows a builtin") end
    declare(s.var, "local", s.line)
    emit("for " .. mangle(s.var) .. " = " .. lo .. ", " .. hi .. (step and (", " .. step) or "") .. " do")
    local lc = loop_body(s)
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
      declare(v, "local", s.line)
      vars[k] = mangle(v)
    end
    local it = (#s.vars == 1) and "__rt.iter1(" or "__rt.iter2("
    emit("for " .. table.concat(vars, ", ") .. " in " .. it .. src .. ") do")
    local lc = loop_body(s)
    level = level + 1
    block(s.body)
    level = level - 1
    end_loop(lc)
    pop_scope()
  end

  -- тело функции: params, vararg, body; header: текст перед "(" (например "name = function")
  local function function_body(header, params, vararg, body, line)
    local plist = {}
    push_scope(true)
    for k, p in ipairs(params) do
      if B.PROTECTED[p.name] or B.SHADOW_WARN[p.name] then warn(p.line, "parameter '" .. p.name .. "' shadows a builtin") end
      declare(p.name, "param", p.line)
      plist[k] = mangle(p.name)
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
        local n = mangle(p.name)
        emit("if " .. n .. " == nil then " .. n .. " = " .. expr(p.default) .. " end")
      end
    end
    if vararg then emit("local " .. mangle(vararg) .. " = {...}") end
    hoist(body)
    block(body)
    ctx[#ctx] = nil
    level = level - 1
    pop_scope()
    emit("end")
  end

  function S.FuncDef(s)
    local info = lookup(s.name)
    if info and info.kind == "const" then fail(s.line, "cannot redefine constant '" .. s.name .. "'") end
    function_body(mangle(s.name) .. " = function", s.params, s.vararg, s.body, s.line)
    if s.exported then record_export(s.name, s.line) end
  end

  function S.ClassDef(s)
    local info = lookup(s.name)
    if info and info.kind == "const" then fail(s.line, "cannot redefine constant '" .. s.name .. "'") end
    local cname = mangle(s.name)
    emit(cname .. " = __rt.class(" .. U.quote(s.name) .. ", " .. (s.base and expr(s.base) or "nil") .. ")")
    for _, m in ipairs(s.body) do
      curline = m.line or curline
      if m.tag == "FuncDef" then
        local target = U.is_lua_name(m.name) and (cname .. "." .. m.name) or (cname .. "[" .. U.quote(m.name) .. "]")
        function_body(target .. " = function", m.params, m.vararg, m.body, m.line)
      elseif m.tag == "Assign" and #m.targets == 1 and m.targets[1].tag == "Name" and #m.values == 1 then
        local fname = m.targets[1].name
        local target = U.is_lua_name(fname) and (cname .. "." .. fname) or (cname .. "[" .. U.quote(fname) .. "]")
        emit(target .. " = " .. expr(m.values[1]))
      elseif m.tag == "Pass" or (m.tag == "ExprStmt" and m.e.tag == "String") then
        -- ничего
      else
        fail(m.line, "only methods (def) and simple fields (name = value) are allowed in a class body")
      end
    end
    if s.exported then record_export(s.name, s.line) end
  end

  function S.Import(s)
    emit(mangle(s.name) .. " = __import(" .. U.quote(s.path) .. ")")
    if s.exported then record_export(s.name, s.line) end
  end

  function S.FromImport(s)
    local id = nextid()
    local m = "__m" .. id
    emit("do local " .. m .. " = __import(" .. U.quote(s.path) .. ")")
    for _, n in ipairs(s.names) do
      local info = lookup(n.alias)
      if info and info.kind == "const" then fail(n.line, "cannot assign to constant '" .. n.alias .. "'") end
      emit("  " .. mangle(n.alias) .. " = " .. attr_access(m, n.name))
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
            declare(h.name, "local", h.line)
            emit("local " .. mangle(h.name) .. " = __e")
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
          declare(bare.name, "local", bare.line)
          emit("local " .. mangle(bare.name) .. " = __e")
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

  ---------------------------------------------------------------- модуль

  curline = 1
  emit("local __rt, __import = ...")
  emit("local __floor, __tostring, __tonumber, __error = math.floor, tostring, tonumber, error")
  emit("local __exports = {}")
  push_scope(true)
  ctx[#ctx + 1] = { kind = "module" }
  hoist(ast.body)
  block(ast.body)
  for _, name in ipairs(exports) do
    emit("__exports[" .. U.quote(name) .. "] = " .. mangle(name))
  end
  emit("return __exports")

  return table.concat(out, "\n") .. "\n", lmap, warnings
end

return M
