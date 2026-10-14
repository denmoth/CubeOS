-- Cubic: проверка типов (строгий режим).
-- Проверяются только участки под #!strict и блоки strict:. Остальное (loose) считается типом any.
local U = ...

local M = {}

---------------------------------------------------------------- типы

local ANY = { k = "any" }
local NUM = { k = "num" }
local STR = { k = "str" }
local BOOL = { k = "bool" }
local NIL = { k = "nil" }
local FN_ANY = { k = "fn", params = {}, rest = ANY, ret = ANY, loose = true }

local function mk_list(e) return { k = "list", elem = e } end
local function mk_dict(key, val) return { k = "dict", key = key, val = val } end
local function mk_rec(fields) return { k = "rec", fields = fields } end
local function mk_inst(cls) return { k = "inst", cls = cls } end
local function mk_classobj(cls) return { k = "classobj", cls = cls } end
local function mk_fn(params, ret, rest) return { k = "fn", params = params, ret = ret or ANY, rest = rest } end

local same
function same(a, b)
  if a == b then return true end
  if a.k ~= b.k then return false end
  local k = a.k
  if k == "list" then
    return same(a.elem, b.elem)
  elseif k == "dict" then
    return same(a.key, b.key) and same(a.val, b.val)
  elseif k == "rec" then
    for n, t in pairs(a.fields) do
      if not b.fields[n] or not same(t, b.fields[n]) then return false end
    end
    for n in pairs(b.fields) do
      if not a.fields[n] then return false end
    end
    return true
  elseif k == "inst" or k == "classobj" then
    return a.cls == b.cls
  elseif k == "union" then
    if #a.items ~= #b.items then return false end
    for _, x in ipairs(a.items) do
      local found = false
      for _, y in ipairs(b.items) do
        if same(x, y) then found = true break end
      end
      if not found then return false end
    end
    return true
  elseif k == "fn" or k == "ns" then
    return false
  end
  return true
end

local function union(items)
  local flat = {}
  local function add(t)
    if t.k == "union" then
      for _, x in ipairs(t.items) do add(x) end
      return
    end
    for _, y in ipairs(flat) do
      if same(y, t) then return end
    end
    flat[#flat + 1] = t
  end
  for _, t in ipairs(items) do
    if t.k == "any" then return ANY end
    add(t)
  end
  if #flat == 0 then return ANY end
  if #flat == 1 then return flat[1] end
  return { k = "union", items = flat }
end

local function has_nil(t)
  if t.k == "nil" then return true end
  if t.k == "union" then
    for _, x in ipairs(t.items) do
      if x.k == "nil" then return true end
    end
  end
  return false
end

local function strip_nil(t)
  if t.k == "nil" then return ANY end
  if t.k == "union" then
    local keep = {}
    for _, x in ipairs(t.items) do
      if x.k ~= "nil" then keep[#keep + 1] = x end
    end
    return union(keep)
  end
  return t
end

local tostr
function tostr(t)
  local k = t.k
  if k == "list" then
    return "list[" .. tostr(t.elem) .. "]"
  elseif k == "dict" then
    return "dict[" .. tostr(t.key) .. ", " .. tostr(t.val) .. "]"
  elseif k == "rec" then
    local names = {}
    for n in pairs(t.fields) do names[#names + 1] = n end
    table.sort(names)
    local parts = {}
    for i, n in ipairs(names) do parts[i] = n .. ": " .. tostr(t.fields[n]) end
    return "{" .. table.concat(parts, ", ") .. "}"
  elseif k == "union" then
    if #t.items == 2 and has_nil(t) then
      return tostr(strip_nil(t)) .. "?"
    end
    local parts = {}
    for i, x in ipairs(t.items) do parts[i] = tostr(x) end
    return table.concat(parts, " | ")
  elseif k == "fn" then
    if t.loose then return "fn" end
    local parts = {}
    for i, p in ipairs(t.params) do parts[i] = tostr(p.type) end
    if t.rest then parts[#parts + 1] = "*" .. tostr(t.rest) end
    return "fn(" .. table.concat(parts, ", ") .. ") -> " .. tostr(t.ret)
  elseif k == "inst" then
    return t.cls.name
  elseif k == "classobj" then
    return "class " .. t.cls.name
  elseif k == "ns" then
    return "namespace " .. t.name
  end
  return k
end

local function is_subclass(c, target)
  while c do
    if c == target then return true end
    c = c.base
  end
  return false
end

local assignable
function assignable(from, to)
  if from == to then return true end
  local fk, tk = from.k, to.k
  if fk == "any" or tk == "any" then return true end
  if fk == "union" then
    for _, m in ipairs(from.items) do
      if not assignable(m, to) then return false end
    end
    return true
  end
  if tk == "union" then
    for _, m in ipairs(to.items) do
      if assignable(from, m) then return true end
    end
    return false
  end
  if fk ~= tk then
    if fk == "rec" and tk == "dict" then
      if not assignable(STR, to.key) then return false end
      for _, ft in pairs(from.fields) do
        if not assignable(ft, to.val) then return false end
      end
      return true
    end
    if fk == "classobj" and tk == "fn" then return true end
    return false
  end
  if fk == "list" then
    return assignable(from.elem, to.elem)
  elseif fk == "dict" then
    return assignable(from.key, to.key) and assignable(from.val, to.val)
  elseif fk == "rec" then
    for n, ft in pairs(to.fields) do
      local f = from.fields[n]
      if f == nil then
        if not has_nil(ft) then return false end
      elseif not assignable(f, ft) then
        return false
      end
    end
    return true
  elseif fk == "inst" then
    return is_subclass(from.cls, to.cls)
  elseif fk == "classobj" then
    return is_subclass(from.cls, to.cls)
  elseif fk == "fn" then
    if to.loose or from.loose then return true end
    for i = 1, #to.params do
      local fp = from.params[i]
      if fp then
        if not assignable(to.params[i].type, fp.type) then return false end
      elseif not from.rest then
        return false
      end
    end
    return assignable(from.ret, to.ret)
  end
  return true
end

local KIND_OF_TYPEOF = {
  number = { num = true },
  string = { str = true },
  boolean = { bool = true },
  ["nil"] = { ["nil"] = true },
  table = { list = true, dict = true, rec = true, inst = true },
  ["function"] = { fn = true, classobj = true },
}

local function filter_kinds(t, kinds, keep)
  local items = t.k == "union" and t.items or { t }
  local out = {}
  for _, x in ipairs(items) do
    local match = kinds[x.k] == true
    if x.k == "any" then
      out[#out + 1] = x
    elseif match == keep then
      out[#out + 1] = x
    end
  end
  if #out == 0 then return ANY end
  return union(out)
end

---------------------------------------------------------------- классы

local function new_class(name, base, loose)
  return { name = name, base = base, fields = {}, methods = {}, statics = {}, loose = loose or false }
end

local function find_member(cls, name)
  local c = cls
  while c do
    if c.fields[name] then return c.fields[name], "field" end
    if c.statics[name] then return c.statics[name], "static" end
    if c.methods[name] then return c.methods[name], "method" end
    c = c.base
  end
  return nil
end

local function class_open(cls)
  local c = cls
  while c do
    if c.open then return true end
    c = c.base
  end
  return false
end

local function class_loose(cls)
  local c = cls
  while c do
    if c.loose then return true end
    c = c.base
  end
  return false
end

---------------------------------------------------------------- окружение

function M.new_env()
  local env = { vars = {}, types = {}, periph = {} }
  local err_cls = new_class("Error")
  err_cls.fields.message = STR
  err_cls.methods.init = mk_fn({ { name = "message", type = ANY, optional = true } }, ANY)
  env.vars.Error = mk_classobj(err_cls)
  env.types.Error = mk_inst(err_cls)
  -- встроенные функции Cubic
  env.vars.len = mk_fn({ { name = "x", type = ANY } }, NUM)
  env.vars.str = mk_fn({ { name = "x", type = ANY } }, STR)
  env.vars.num = mk_fn({ { name = "x", type = ANY } }, union({ NUM, NIL }))
  env.vars.copy = mk_fn({ { name = "x", type = ANY } }, ANY)
  env.vars.deepcopy = mk_fn({ { name = "x", type = ANY } }, ANY)
  env.vars.isinstance = mk_fn({ { name = "x", type = ANY }, { name = "cls", type = ANY } }, BOOL)
  return env
end

---------------------------------------------------------------- для редакторов

M.tostr_type = function(t) return tostr(t) end

-- Список членов типа: { {name, kind = "field"|"method"|"static"|"function"|"variable"|"class", type = "текст", fn = тип-функции} }
-- accessor: "." | ":"; для ":" возвращаются только методы
function M.members_of(t, genv, accessor)
  local out, seen = {}, {}
  local function add(name, kind, ty)
    if seen[name] or name:sub(1, 2) == "__" then return end
    seen[name] = true
    out[#out + 1] = { name = name, kind = kind, type = tostr(ty), fn = ty.k == "fn" and ty or nil }
  end
  local function from_class(cls, instance)
    local c = cls
    while c do
      for n, ty in pairs(c.methods) do add(n, "method", ty) end
      if accessor ~= ":" or not instance then
        for n, ty in pairs(c.statics) do add(n, "static", ty) end
      end
      if instance then
        for n, ty in pairs(c.fields) do
          add(n, ty.k == "fn" and "method" or "field", ty)
        end
      end
      c = c.base
    end
  end
  local function walk(ty)
    local k = ty.k
    if k == "inst" then
      from_class(ty.cls, true)
    elseif k == "classobj" then
      from_class(ty.cls, false)
    elseif k == "rec" then
      for n, ft in pairs(ty.fields) do add(n, ft.k == "fn" and "method" or "field", ft) end
    elseif k == "ns" then
      for n, ft in pairs(ty.members) do
        local kind = ft.k == "fn" and "function" or (ft.k == "classobj" and "class" or "variable")
        add(n, kind, ft)
      end
    elseif k == "str" then
      local sns = genv.vars.string
      if sns and sns.members then
        for n, ft in pairs(sns.members) do add(n, "method", ft) end
      end
    elseif k == "union" then
      for _, item in ipairs(ty.items) do
        if item.k ~= "nil" then walk(item) end
      end
    end
  end
  walk(t)
  if accessor == ":" then
    local keep = {}
    for _, m in ipairs(out) do
      if m.kind == "method" or m.kind == "function" then keep[#keep + 1] = m end
    end
    out = keep
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

---------------------------------------------------------------- проверка

local TERMINATORS = U.set({ "Return", "Raise", "Break", "Continue" })

local function terminates(body)
  local last = body[#body]
  return last ~= nil and TERMINATORS[last.tag] == true
end

-- помечает каждую инструкцию флагом strict с учётом директив и блоков strict:/loose:
local function annotate(body, directives, inherited)
  local function mode_at(line)
    local mode = "loose"
    for _, d in ipairs(directives) do
      if d.line <= line then mode = d.mode end
    end
    return mode == "strict"
  end
  local function walk(stmts, override)
    for _, s in ipairs(stmts) do
      if override ~= nil then s.strict = override else s.strict = mode_at(s.line or 1) end
      local tag = s.tag
      if tag == "ModeBlock" then
        walk(s.body, s.mode == "strict")
      elseif tag == "If" then
        walk(s.body, override)
        for _, e in ipairs(s.elifs) do walk(e.body, override) end
        if s.orelse then walk(s.orelse, override) end
      elseif tag == "While" or tag == "ForRange" or tag == "ForIn" or tag == "With" or tag == "FuncDef" or tag == "ClassDef" then
        walk(s.body, override)
      elseif tag == "Try" then
        walk(s.body, override)
        for _, h in ipairs(s.handlers) do walk(h.body, override) end
        if s.finally then walk(s.finally, override) end
      elseif tag == "Match" then
        for _, c in ipairs(s.cases) do walk(c.body, override) end
      end
    end
  end
  walk(body, inherited)
end

local function any_strict(body)
  local found = false
  local function walk(stmts)
    for _, s in ipairs(stmts) do
      if s.strict then found = true end
      if found then return end
      local tag = s.tag
      if tag == "ModeBlock" or tag == "While" or tag == "ForRange" or tag == "ForIn" or tag == "With" or tag == "FuncDef" or tag == "ClassDef" then
        walk(s.body)
      elseif tag == "If" then
        walk(s.body)
        for _, e in ipairs(s.elifs) do walk(e.body) end
        if s.orelse then walk(s.orelse) end
      elseif tag == "Try" then
        walk(s.body)
        for _, h in ipairs(s.handlers) do walk(h.body) end
        if s.finally then walk(s.finally) end
      elseif tag == "Match" then
        for _, c in ipairs(s.cases) do walk(c.body) end
      end
    end
  end
  walk(body)
  return found
end

local function collect_names(stmts, add)
  for _, s in ipairs(stmts) do
    local tag = s.tag
    if tag == "Assign" then
      for _, t in ipairs(s.targets) do
        if t.tag == "Name" or t.tag == "Starred" then add(t.name) end
      end
    elseif tag == "FuncDef" or tag == "ClassDef" or tag == "Import" or tag == "AnnAssign" then
      add(s.name)
    elseif tag == "FromImport" then
      for _, n in ipairs(s.names) do add(n.alias) end
    elseif tag == "If" then
      collect_names(s.body, add)
      for _, e in ipairs(s.elifs) do collect_names(e.body, add) end
      if s.orelse then collect_names(s.orelse, add) end
    elseif tag == "While" or tag == "ForRange" or tag == "ForIn" or tag == "With" or tag == "ModeBlock" then
      collect_names(s.body, add)
    elseif tag == "Try" then
      collect_names(s.body, add)
      for _, h in ipairs(s.handlers) do collect_names(h.body, add) end
      if s.finally then collect_names(s.finally, add) end
    elseif tag == "Match" then
      local function pnames(p)
        local pt = p.tag
        if pt == "PCapture" then add(p.name)
        elseif pt == "POr" then for _, a in ipairs(p.alts) do pnames(a) end
        elseif pt == "PList" then
          for _, it in ipairs(p.items) do pnames(it) end
          if p.star_name then add(p.star_name) end
        elseif pt == "PDict" then for _, e in ipairs(p.entries) do pnames(e.pat) end
        elseif pt == "PClass" then
          for _, a in ipairs(p.args) do pnames(a) end
          for _, kw in ipairs(p.kwargs) do pnames(kw.pat) end
        end
      end
      for _, c in ipairs(s.cases) do
        pnames(c.pattern)
        collect_names(c.body, add)
      end
    end
  end
end

-- genv: окружение из M.new_env(). hdr: true для файлов .cuh
function M.needs_check(ast, opts)
  if opts and opts.strict then return true end
  annotate(ast.body, ast.directives or {}, nil)
  return any_strict(ast.body)
end

function M.check(ast, file, genv, hdr, opts)
  local errors = {}
  local strict_now = hdr and true or false
  local scope = nil
  local types = setmetatable({}, { __index = genv.types })
  local narrow = { {} }
  local deferred = {}
  local cur_ret, cur_cls = nil, nil
  local ret_collect = nil

  local function err(line, msg)
    if strict_now then errors[#errors + 1] = { line = line or 0, msg = msg } end
  end

  ---------------------------------------------------------------- области

  local function push_scope(kind)
    scope = { parent = scope, vars = {}, kind = kind }
    return scope
  end

  local function pop_scope()
    scope = scope.parent
  end

  local function lookup_var(name)
    local s = scope
    while s do
      local v = s.vars[name]
      if v then return v end
      s = s.parent
    end
    return nil
  end

  local function declare(name, ty, annotated, pending)
    local rec = { type = ty, annotated = annotated or false, pending = pending or false }
    scope.vars[name] = rec
    return rec
  end

  local function push_frame() narrow[#narrow + 1] = {} end
  local function pop_frame() narrow[#narrow] = nil end

  local function narrowed(name, rec)
    for k = #narrow, 1, -1 do
      local t = narrow[k][name]
      if t then return t end
    end
    return rec.type or ANY
  end

  local function clear_narrow(name)
    for k = 1, #narrow do narrow[k][name] = nil end
  end

  local function apply_facts(res)
    if not res then return end
    local top = narrow[#narrow]
    for name, t in pairs(res) do top[name] = t end
  end

  ---------------------------------------------------------------- разрешение типов

  local resolve_type
  function resolve_type(tn)
    local tag = tn.tag
    if tag == "TName" then
      local n = tn.name
      if n == "num" then return NUM
      elseif n == "str" then return STR
      elseif n == "bool" then return BOOL
      elseif n == "nil" then return NIL
      elseif n == "any" then return ANY
      elseif n == "list" then return mk_list(ANY)
      elseif n == "dict" then return mk_dict(ANY, ANY)
      elseif n == "fn" then return FN_ANY end
      local t = types[n]
      if t then return t end
      err(tn.line, "unknown type '" .. n .. "'")
      return ANY
    elseif tag == "TGen" then
      if tn.name == "list" then
        if #tn.args ~= 1 then err(tn.line, "list needs one type argument: list[T]") return mk_list(ANY) end
        return mk_list(resolve_type(tn.args[1]))
      end
      if #tn.args ~= 2 then err(tn.line, "dict needs two type arguments: dict[K, V]") return mk_dict(ANY, ANY) end
      return mk_dict(resolve_type(tn.args[1]), resolve_type(tn.args[2]))
    elseif tag == "TOpt" then
      return union({ resolve_type(tn.inner), NIL })
    elseif tag == "TUnion" then
      local items = {}
      for k, it in ipairs(tn.items) do items[k] = resolve_type(it) end
      return union(items)
    elseif tag == "TFn" then
      local params = {}
      for k, p in ipairs(tn.params) do params[k] = { name = "arg" .. k, type = resolve_type(p) } end
      return mk_fn(params, tn.ret and resolve_type(tn.ret) or ANY, tn.rest and resolve_type(tn.rest) or nil)
    elseif tag == "TRec" then
      local fields = {}
      for _, f in ipairs(tn.fields) do fields[f.name] = resolve_type(f.type) end
      return mk_rec(fields)
    end
    return ANY
  end

  local function fn_from_def(def, is_method)
    local params = {}
    for i, p in ipairs(def.params) do
      if not (is_method and i == 1 and p.name == "self") then
        params[#params + 1] = {
          name = p.name,
          type = p.type and resolve_type(p.type) or ANY,
          optional = p.default ~= nil or p.optional == true,
        }
      end
    end
    local rest
    if def.vararg then rest = def.vararg_type and resolve_type(def.vararg_type) or ANY end
    local ret = def.ret and resolve_type(def.ret) or ANY
    return mk_fn(params, ret, rest)
  end

  ---------------------------------------------------------------- выражения

  local X = {}
  local infer, check_block, check_stmt, facts

  local function expr_label(node)
    if node.tag == "Name" then return node.name end
    if node.tag == "Attr" then return expr_label(node.obj) .. "." .. node.name end
    if node.tag == "Method" then return expr_label(node.obj) .. ":" .. node.name end
    return "function"
  end

  function infer(node, expected)
    local h = X[node.tag]
    if not h then return ANY end
    return h(node, expected)
  end

  local function expect_assignable(from, to, line, what)
    if not assignable(from, to) then
      err(line, (what or "type mismatch") .. ": expected " .. tostr(to) .. ", got " .. tostr(from))
      return false
    end
    return true
  end

  function X.Number() return NUM end
  function X.String() return STR end
  function X.Bool() return BOOL end
  function X.Nil() return NIL end
  function X.LuaExpr() return ANY end
  function X.Paren(n, expected) return infer(n.e, expected) end

  function X.FString(n)
    for _, p in ipairs(n.parts) do
      if p.kind == "expr" then infer(p.node) end
    end
    return STR
  end

  function X.Name(n)
    local rec = lookup_var(n.name)
    if rec then return narrowed(n.name, rec) end
    local g = genv.vars[n.name]
    if g then return g end
    if n.name == "super" and cur_cls and cur_cls.base then return mk_classobj(cur_cls.base) end
    err(n.line, "unknown name '" .. n.name .. "' (declare it in a .cuh header or move this code to a loose section)")
    return ANY
  end

  local function with_self(ft, cls)
    local params = { { name = "self", type = mk_inst(cls) } }
    for _, p in ipairs(ft.params) do params[#params + 1] = p end
    local c = mk_fn(params, ft.ret, ft.rest)
    c.loose = ft.loose
    return c
  end

  local function member_of(ot, name, line)
    local k = ot.k
    if k == "any" then return ANY end
    if k == "inst" then
      if class_loose(ot.cls) then return ANY end
      local t = find_member(ot.cls, name)
      if t then return t end
      if class_open(ot.cls) then return ANY end
      err(line, "class '" .. ot.cls.name .. "' has no member '" .. name .. "'")
      return ANY
    elseif k == "classobj" then
      if class_loose(ot.cls) then return ANY end
      local t, kind = find_member(ot.cls, name)
      if t then
        if kind == "method" and t.k == "fn" then return with_self(t, ot.cls) end
        return t
      end
      err(line, "class '" .. ot.cls.name .. "' has no member '" .. name .. "'")
      return ANY
    elseif k == "rec" then
      local f = ot.fields[name]
      if f then return f end
      err(line, "record " .. tostr(ot) .. " has no field '" .. name .. "'")
      return ANY
    elseif k == "dict" then
      return ot.val
    elseif k == "ns" then
      local m = ot.members[name]
      if m then return m end
      if ot.open then return ANY end
      err(line, "namespace '" .. ot.name .. "' has no member '" .. name .. "'")
      return ANY
    elseif k == "union" then
      if has_nil(ot) then
        err(line, "value of type '" .. tostr(ot) .. "' may be nil; check it before using '." .. name .. "'")
      end
      local res = {}
      for _, m in ipairs(ot.items) do
        if m.k ~= "nil" then res[#res + 1] = member_of(m, name, line) end
      end
      return union(res)
    end
    err(line, "cannot access '." .. name .. "' on a value of type " .. tostr(ot))
    return ANY
  end

  function X.Attr(n)
    local ot = infer(n.obj)
    if n.opt then
      local inner = strip_nil(ot)
      if inner.k == "any" then return ANY end
      return union({ member_of(inner, n.name, n.line), NIL })
    end
    return member_of(ot, n.name, n.line)
  end

  function X.Index(n)
    local ot = infer(n.obj)
    local it = infer(n.idx)
    local k = ot.k
    if k == "any" then return ANY end
    if k == "list" then
      expect_assignable(it, NUM, n.line, "list index")
      return ot.elem
    elseif k == "dict" then
      expect_assignable(it, ot.key, n.line, "dict key")
      return ot.val
    elseif k == "rec" then
      if n.idx.tag == "String" then
        local f = ot.fields[n.idx.v]
        if f then return f end
        err(n.line, "record " .. tostr(ot) .. " has no field '" .. n.idx.v .. "'")
        return ANY
      end
      return ANY
    elseif k == "str" then
      err(n.line, "a str cannot be indexed with []; use a slice s[i:j] or string methods")
      return ANY
    elseif k == "union" then
      if has_nil(ot) then
        err(n.line, "value of type '" .. tostr(ot) .. "' may be nil; check it before indexing")
      end
      return ANY
    elseif k == "ns" or k == "inst" then
      return ANY
    end
    err(n.line, "cannot index a value of type " .. tostr(ot))
    return ANY
  end

  function X.Slice(n)
    local ot = infer(n.obj)
    if n.lo then expect_assignable(infer(n.lo), NUM, n.line, "slice bound") end
    if n.hi then expect_assignable(infer(n.hi), NUM, n.line, "slice bound") end
    if n.step then expect_assignable(infer(n.step), NUM, n.line, "slice step") end
    local k = ot.k
    if k == "list" or k == "str" or k == "any" then return ot end
    if k == "union" then
      if has_nil(ot) then err(n.line, "value of type '" .. tostr(ot) .. "' may be nil; check it before slicing") end
      return ANY
    end
    err(n.line, "cannot slice a value of type " .. tostr(ot))
    return ANY
  end

  function X.List(n, expected)
    local elem_expected = expected and expected.k == "list" and expected.elem or nil
    if #n.items == 0 then
      if expected and expected.k == "list" then return expected end
      return mk_list(ANY)
    end
    local ts = {}
    for _, it in ipairs(n.items) do
      if it.tag == "Spread" then
        local st = infer(it.e)
        if st.k == "list" then ts[#ts + 1] = st.elem else ts[#ts + 1] = ANY end
      else
        ts[#ts + 1] = infer(it, elem_expected)
      end
    end
    return mk_list(union(ts))
  end

  function X.Dict(n, expected)
    if #n.entries == 0 then
      if expected and (expected.k == "dict" or expected.k == "rec") then return expected end
      return mk_dict(ANY, ANY)
    end
    local fields, vals, keys = {}, {}, {}
    local static = true
    for _, en in ipairs(n.entries) do
      if en.kind == "spread" then
        local st = infer(en.value)
        if st.k == "rec" then
          for name, ft in pairs(st.fields) do fields[name] = ft end
        else
          static = false
          if st.k == "dict" then vals[#vals + 1] = st.val; keys[#keys + 1] = st.key end
        end
      else
        local want = nil
        if expected and expected.k == "rec" and (en.kind == "name" or en.kind == "str") then want = expected.fields[en.key] end
        if expected and expected.k == "dict" then want = expected.val end
        local vt = infer(en.value, want)
        vals[#vals + 1] = vt
        if en.kind == "name" or en.kind == "str" then
          fields[en.key] = vt
          keys[#keys + 1] = STR
        elseif en.kind == "num" then
          static = false
          keys[#keys + 1] = NUM
        else
          static = false
          keys[#keys + 1] = infer(en.key)
        end
      end
    end
    if static then return mk_rec(fields) end
    return mk_dict(union(keys), union(vals))
  end

  local function numeric(t)
    return t.k == "num" or t.k == "any"
  end

  local function textual(t)
    return t.k == "num" or t.k == "str" or t.k == "any"
  end

  function X.Unary(n)
    local t = infer(n.e)
    if n.op == "-" then
      if not numeric(t) then err(n.line, "operator '-' needs a number, got " .. tostr(t)) end
      return NUM
    end
    return BOOL
  end

  local ARITH = U.set({ "+", "-", "*", "/", "//", "%", "**" })
  local ORDER = U.set({ "<", "<=", ">", ">=" })

  function X.Binary(n)
    local op = n.op
    if op == "and" then
      local l = infer(n.l)
      local r = infer(n.r)
      return union({ l, r })
    elseif op == "or" then
      local l = infer(n.l)
      local r = infer(n.r)
      return union({ strip_nil(l), r })
    elseif op == "??" then
      local l = infer(n.l)
      local r = infer(n.r)
      return union({ strip_nil(l), r })
    end
    local l, r = infer(n.l), infer(n.r)
    if ARITH[op] then
      if not numeric(l) or not numeric(r) then
        err(n.line, "operator '" .. op .. "' needs numbers, got " .. tostr(l) .. " and " .. tostr(r))
      end
      return NUM
    elseif op == ".." then
      if not textual(l) or not textual(r) then
        err(n.line, "operator '..' joins strings and numbers, got " .. tostr(l) .. " and " .. tostr(r))
      end
      return STR
    elseif ORDER[op] then
      local ok = (l.k == "num" and r.k == "num") or (l.k == "str" and r.k == "str") or l.k == "any" or r.k == "any"
      if not ok then
        err(n.line, "cannot compare " .. tostr(l) .. " with " .. tostr(r) .. " using '" .. op .. "'")
      end
      return BOOL
    end
    return BOOL
  end

  function X.Ternary(n, expected)
    infer(n.cond)
    return union({ infer(n.a, expected), infer(n.b, expected) })
  end

  function X.Lambda(n, expected)
    push_scope("fn")
    local params = {}
    for i, p in ipairs(n.params) do
      local pt = ANY
      if expected and expected.k == "fn" and expected.params[i] then pt = expected.params[i].type end
      declare(p, pt, true)
      params[i] = { name = p, type = pt }
    end
    local saved_ret = cur_ret
    local rt = infer(n.body)
    cur_ret = saved_ret
    pop_scope()
    return mk_fn(params, rt)
  end

  -- типы переменных цикла: для одной и двух переменных
  local function iter_types(iter)
    if iter.tag == "Range" then
      expect_assignable(infer(iter.lo), NUM, iter.line, "range bound")
      expect_assignable(infer(iter.hi), NUM, iter.line, "range bound")
      if iter.step then expect_assignable(infer(iter.step), NUM, iter.line, "range step") end
      return NUM, ANY
    end
    local t = infer(iter)
    local k = t.k
    if k == "list" then return t.elem, t.elem, NUM end
    if k == "str" then return STR, STR, NUM end
    if k == "dict" then return ANY, t.val, t.key end
    if k == "rec" then return ANY, ANY, STR end
    if k == "union" and has_nil(t) then
      err(iter.line, "value of type '" .. tostr(t) .. "' may be nil; check it before iterating")
    end
    return ANY, ANY, ANY
  end

  local function comp(clauses, body_fn)
    push_scope("block")
    for _, c in ipairs(clauses) do
      if c.kind == "for" then
        local one, two, key = iter_types(c.iter)
        if #c.vars == 1 then
          declare(c.vars[1], one, true)
        else
          declare(c.vars[1], key or ANY, true)
          declare(c.vars[2], two, true)
        end
      else
        infer(c.cond)
      end
    end
    local r = body_fn()
    pop_scope()
    return r
  end

  function X.ListComp(n)
    return comp(n.clauses, function() return mk_list(infer(n.elem)) end)
  end

  function X.DictComp(n)
    return comp(n.clauses, function()
      return mk_dict(infer(n.key), infer(n.value))
    end)
  end

  ---------------------------------------------------------------- вызовы

  local function drop_first(ft)
    local params = {}
    for i = 2, #ft.params do params[#params + 1] = ft.params[i] end
    local c = mk_fn(params, ft.ret, ft.rest)
    c.loose = ft.loose
    return c
  end

  local function apply_fn(ft, n, label)
    local params = ft.params
    if ft.loose then
      for _, a in ipairs(n.args) do infer(a.tag == "Spread" and a.e or a) end
      for _, kw in ipairs(n.kwargs or {}) do infer(kw.value) end
      return ft.ret
    end
    local has_spread = false
    for i, a in ipairs(n.args) do
      if a.tag == "Spread" then
        has_spread = true
        infer(a.e)
      else
        local p = params[i]
        local want = p and p.type or ft.rest
        local at = infer(a, want)
        if p then
          expect_assignable(at, p.type, a.line or n.line, "argument " .. i .. " of '" .. label .. "'")
        elseif ft.rest then
          expect_assignable(at, ft.rest, a.line or n.line, "argument " .. i .. " of '" .. label .. "'")
        else
          err(a.line or n.line, "too many arguments to '" .. label .. "' (takes at most " .. #params .. ")")
        end
      end
    end
    local given = {}
    for i = 1, #n.args do given[i] = true end
    for _, kw in ipairs(n.kwargs or {}) do
      local found
      for i, p in ipairs(params) do
        if p.name == kw.name then found = i break end
      end
      if not found then
        err(kw.line or n.line, "'" .. label .. "' has no parameter named '" .. kw.name .. "'")
        infer(kw.value)
      else
        if given[found] then err(kw.line or n.line, "argument '" .. kw.name .. "' of '" .. label .. "' was given twice") end
        given[found] = true
        expect_assignable(infer(kw.value, params[found].type), params[found].type, kw.line or n.line, "argument '" .. kw.name .. "' of '" .. label .. "'")
      end
    end
    if not has_spread then
      for i, p in ipairs(params) do
        if not given[i] and not p.optional and not has_nil(p.type) and p.type.k ~= "any" then
          err(n.line, "missing argument '" .. p.name .. "' in call to '" .. label .. "'")
          break
        end
      end
    end
    return ft.ret
  end

  local function infer_args(n)
    for _, a in ipairs(n.args) do infer(a.tag == "Spread" and a.e or a) end
    for _, kw in ipairs(n.kwargs or {}) do infer(kw.value) end
  end

  local function call_type(ft, n, label)
    local k = ft.k
    if k == "any" then
      infer_args(n)
      return ANY
    elseif k == "fn" then
      return apply_fn(ft, n, label)
    elseif k == "classobj" then
      local cls = ft.cls
      if class_loose(cls) then
        infer_args(n)
        return mk_inst(cls)
      end
      local init = find_member(cls, "init")
      if init and init.k == "fn" then
        apply_fn(init, n, cls.name)
      else
        if #n.args > 0 or (n.kwargs and #n.kwargs > 0) then
          err(n.line, "class '" .. cls.name .. "' has no init and takes no arguments")
        end
        infer_args(n)
      end
      return mk_inst(cls)
    elseif k == "union" then
      if has_nil(ft) then
        err(n.line, "'" .. label .. "' may be nil; check it before calling")
      end
      infer_args(n)
      return ANY
    end
    err(n.line, "cannot call a value of type " .. tostr(ft))
    infer_args(n)
    return ANY
  end

  -- Снимок видимых имён с типами (для автодополнения в редакторах)
  local function scope_snapshot()
    local out = {}
    local s = scope
    while s do
      for name, rec in pairs(s.vars) do
        if out[name] == nil then out[name] = narrowed(name, rec) end
      end
      s = s.parent
    end
    return out
  end

  function X.Call(n)
    local f = n.fn
    -- служебный вызов редакторского режима: __cubic_probe(выражение) сообщает тип выражения и видимые имена
    if f.tag == "Name" and f.name == "__cubic_probe" and opts and opts.probe then
      local t = n.args[1] and infer(n.args[1]) or ANY
      opts.probe(t, scope_snapshot(), genv)
      return ANY
    end
    if f.tag == "Name" and not lookup_var(f.name) then
      if (f.name == "copy" or f.name == "deepcopy") and #n.args == 1 then
        return infer(n.args[1])
      end
    end
    -- peripheral.find("monitor"): тип по литералу
    if f.tag == "Attr" and f.name == "find" and f.obj.tag == "Name" and f.obj.name == "peripheral"
      and not lookup_var("peripheral") and n.args[1] and n.args[1].tag == "String" and genv.periph then
      local pt = genv.periph[n.args[1].v]
      if pt then
        infer_args(n)
        return union({ pt, NIL })
      end
    end
    local ft = infer(f)
    return call_type(ft, n, expr_label(f))
  end

  function X.Method(n)
    local ot = infer(n.obj)
    local label = expr_label(n)
    local k = ot.k
    if k == "any" then
      infer_args(n)
      return ANY
    end
    local m
    if k == "str" then
      local sns = genv.vars.string
      m = sns and sns.members and sns.members[n.name]
      if not m then
        err(n.line, "str has no method '" .. n.name .. "'")
        infer_args(n)
        return ANY
      end
      if m.k == "fn" then m = drop_first(m) end
    elseif k == "inst" then
      m = member_of(ot, n.name, n.line)
    elseif k == "classobj" or k == "rec" or k == "dict" or k == "ns" or k == "union" then
      m = member_of(ot, n.name, n.line)
      if m.k == "fn" and k ~= "classobj" and k ~= "union" then m = drop_first(m) end
    else
      err(n.line, "cannot call method ':" .. n.name .. "' on a value of type " .. tostr(ot))
      infer_args(n)
      return ANY
    end
    if m.k == "any" then
      infer_args(n)
      return ANY
    end
    return call_type(m, n, label)
  end

  ---------------------------------------------------------------- условия и сужение

  local function var_type_now(name)
    local rec = lookup_var(name)
    if not rec then return nil end
    return narrowed(name, rec)
  end

  local function merge_into(a, b)
    for k, v in pairs(b or {}) do a[k] = v end
    return a
  end

  function facts(c, positive)
    local tag = c.tag
    local res = {}
    if tag == "Name" then
      local t = var_type_now(c.name)
      if t then
        if positive then
          if has_nil(t) then res[c.name] = strip_nil(t) end
        elseif has_nil(t) and strip_nil(t).k ~= "bool" then
          res[c.name] = NIL
        end
      end
    elseif tag == "Paren" then
      return facts(c.e, positive)
    elseif tag == "Unary" and c.op == "not" then
      return facts(c.e, not positive)
    elseif tag == "Binary" then
      local op = c.op
      if op == "and" then
        if positive then merge_into(res, facts(c.l, true)) merge_into(res, facts(c.r, true)) end
      elseif op == "or" then
        if not positive then merge_into(res, facts(c.l, false)) merge_into(res, facts(c.r, false)) end
      elseif op == "==" or op == "!=" or op == "is" or op == "is not" then
        local eq = (op == "==" or op == "is")
        local a, b = c.l, c.r
        if b.tag == "Name" and a.tag == "Nil" then a, b = b, a end
        if a.tag == "Name" and b.tag == "Nil" then
          local t = var_type_now(a.name)
          if t and has_nil(t) then
            if eq == positive then res[a.name] = NIL else res[a.name] = strip_nil(t) end
          end
        elseif a.tag == "Call" and a.fn.tag == "Name" and a.fn.name == "type" and #a.args == 1
          and a.args[1].tag == "Name" and b.tag == "String" then
          local nm = a.args[1].name
          local t = var_type_now(nm)
          local kinds = KIND_OF_TYPEOF[b.v]
          if t and kinds then res[nm] = filter_kinds(t, kinds, eq == positive) end
        end
      end
    elseif tag == "Call" and c.fn.tag == "Name" and c.fn.name == "isinstance" and #c.args == 2
      and c.args[1].tag == "Name" and positive then
      local saved = strict_now
      strict_now = false
      local ct = infer(c.args[2])
      strict_now = saved
      if ct.k == "classobj" then res[c.args[1].name] = mk_inst(ct.cls) end
    end
    return res
  end

  ---------------------------------------------------------------- присваивание

  local function assign_name(name, vt, line)
    local rec = lookup_var(name)
    if not rec then
      declare(name, vt.k == "nil" and ANY or vt, false)
      return
    end
    if rec.type == nil or rec.pending then
      rec.type = (vt.k == "nil") and ANY or vt
      rec.pending = false
    else
      expect_assignable(vt, rec.type, line, "cannot assign to '" .. name .. "'")
    end
    clear_narrow(name)
  end

  local function attr_assign(t, vt, line)
    local ot = infer(t.obj)
    local k = ot.k
    if k == "any" then return end
    if k == "inst" then
      local cls = ot.cls
      if class_loose(cls) then return end
      local mt = find_member(cls, t.name)
      if mt then
        expect_assignable(vt, mt, line, "cannot assign to '." .. t.name .. "'")
      elseif cur_cls and cls == cur_cls and t.obj.tag == "Name" and t.obj.name == "self" then
        cls.fields[t.name] = (vt.k == "nil") and ANY or vt
      else
        err(line, "class '" .. cls.name .. "' has no field '" .. t.name .. "'")
      end
    elseif k == "classobj" then
      if not class_loose(ot.cls) then
        local mt = find_member(ot.cls, t.name)
        if mt then expect_assignable(vt, mt, line, "cannot assign to '." .. t.name .. "'")
        else ot.cls.statics[t.name] = vt end
      end
    elseif k == "rec" then
      local ft = ot.fields[t.name]
      if ft then
        expect_assignable(vt, ft, line, "cannot assign to '." .. t.name .. "'")
      else
        err(line, "record " .. tostr(ot) .. " has no field '" .. t.name .. "'")
      end
    elseif k == "dict" then
      expect_assignable(vt, ot.val, line, "cannot assign to dict value")
    elseif k == "union" and has_nil(ot) then
      err(line, "value of type '" .. tostr(ot) .. "' may be nil; check it before assigning to '." .. t.name .. "'")
    end
  end

  local function index_assign(t, vt, line)
    local ot = infer(t.obj)
    local it = infer(t.idx)
    local k = ot.k
    if k == "list" then
      expect_assignable(it, NUM, line, "list index")
      expect_assignable(vt, ot.elem, line, "cannot assign to list element")
    elseif k == "dict" then
      expect_assignable(it, ot.key, line, "dict key")
      expect_assignable(vt, ot.val, line, "cannot assign to dict value")
    elseif k == "rec" and t.idx.tag == "String" then
      local ft = ot.fields[t.idx.v]
      if ft then expect_assignable(vt, ft, line, "cannot assign to field '" .. t.idx.v .. "'") end
    elseif k == "union" and has_nil(ot) then
      err(line, "value of type '" .. tostr(ot) .. "' may be nil; check it before indexing")
    end
  end

  local function assign_target(t, vt, line)
    if t.tag == "Name" then assign_name(t.name, vt, line)
    elseif t.tag == "Attr" then attr_assign(t, vt, line)
    elseif t.tag == "Index" then index_assign(t, vt, line)
    elseif t.tag == "Starred" then assign_name(t.name, mk_list(ANY), line) end
  end

  local function target_expected(t)
    if t.tag == "Name" then
      local rec = lookup_var(t.name)
      if rec and rec.type and not rec.pending then return rec.type end
    elseif t.tag == "Attr" or t.tag == "Index" then
      local saved = strict_now
      strict_now = false
      local ty = infer(t)
      strict_now = saved
      return ty
    end
    return nil
  end

  ---------------------------------------------------------------- инструкции

  local C = {}

  function check_block(stmts)
    push_scope("block")
    push_frame()
    for _, s in ipairs(stmts) do check_stmt(s) end
    pop_frame()
    pop_scope()
  end

  -- в нестрогом участке: объявляем имена как any, внутрь составных инструкций заходим
  local function loose_stmt(s)
    local tag = s.tag
    local function any_name(name)
      local rec = lookup_var(name)
      if rec then
        if rec.type == nil or rec.pending then rec.type = ANY rec.pending = false end
      else
        declare(name, ANY, false)
      end
    end
    if tag == "Assign" then
      for _, t in ipairs(s.targets) do
        if t.tag == "Name" or t.tag == "Starred" then any_name(t.name) end
      end
    elseif tag == "AnnAssign" or tag == "Import" then
      any_name(s.name)
    elseif tag == "FromImport" then
      for _, n in ipairs(s.names) do any_name(n.alias) end
    elseif tag == "Let" then
      for _, n in ipairs(s.names) do declare(n, ANY, false) end
    elseif tag == "Const" or tag == "Override" then
      declare(s.name, ANY, false)
    elseif tag == "FuncDef" then
      any_name(s.name)
      scope.vars[s.name].type = FN_ANY
      local def_scope = scope
      deferred[#deferred + 1] = function()
        local saved = scope
        scope = def_scope
        push_scope("fn")
        for _, p in ipairs(s.params) do declare(p.name, ANY, true) end
        if s.vararg then declare(s.vararg, mk_list(ANY), true) end
        local names = {}
        collect_names(s.body, function(nm) names[#names + 1] = nm end)
        for _, nm in ipairs(names) do
          if not lookup_var(nm) then declare(nm, ANY, false) end
        end
        local saved_narrow = narrow
        narrow = { {} }
        for _, st in ipairs(s.body) do check_stmt(st) end
        narrow = saved_narrow
        scope = saved
      end
    elseif tag == "ClassDef" then
      any_name(s.name)
      local cls = new_class(s.name, nil, true)
      scope.vars[s.name].type = mk_classobj(cls)
      types[s.name] = mk_inst(cls)
    elseif tag == "If" then
      check_block(s.body)
      for _, e in ipairs(s.elifs) do check_block(e.body) end
      if s.orelse then check_block(s.orelse) end
    elseif tag == "While" or tag == "ForRange" or tag == "ForIn" or tag == "With" then
      push_scope("block")
      if tag == "ForRange" then declare(s.var, NUM, true) end
      if tag == "ForIn" then for _, v in ipairs(s.vars) do declare(v, ANY, true) end end
      if tag == "With" then declare(s.name, ANY, true) end
      check_block(s.body)
      pop_scope()
    elseif tag == "Try" then
      check_block(s.body)
      for _, h in ipairs(s.handlers) do
        push_scope("block")
        if h.name then declare(h.name, ANY, true) end
        check_block(h.body)
        pop_scope()
      end
      if s.finally then check_block(s.finally) end
    elseif tag == "Match" then
      for _, c in ipairs(s.cases) do check_block(c.body) end
    elseif tag == "ModeBlock" then
      check_block(s.body)
    end
  end

  function check_stmt(s)
    strict_now = s.strict and true or false
    if not s.strict then
      loose_stmt(s)
      return
    end
    local h = C[s.tag]
    if h then h(s) end
  end

  function C.Pass() end
  function C.Break() end
  function C.Continue() end
  function C.TypeAlias(s)
    types[s.name] = resolve_type(s.type)
  end

  function C.ExprStmt(s) infer(s.e) end

  function C.LuaBlock() end

  -- type of an imported module from the resolver (opts.module_types), or any
  local function module_type(spec, alias)
    local resolver = opts and opts.module_types
    if not resolver then return nil end
    local info = resolver(spec)
    if not info then return nil end
    -- classes of the module become usable as types: alias.ClassName
    for cname, cty in pairs(info.members) do
      if cty.k == "classobj" then types[alias .. "." .. cname] = mk_inst(cty.cls) end
    end
    return { k = "ns", name = alias, members = info.members, open = info.open }
  end

  function C.Import(s)
    assign_name(s.name, module_type(s.path, s.name) or ANY, s.line)
  end

  function C.FromImport(s)
    local info = opts and opts.module_types and opts.module_types(s.path)
    for _, n in ipairs(s.names) do
      local ty = ANY
      if info then
        local m = info.members[n.name]
        if m then
          ty = m
          if m.k == "classobj" then types[n.alias] = mk_inst(m.cls) end
        elseif not info.open then
          err(n.line or s.line, "module '" .. s.path .. "' has no export '" .. n.name .. "'")
        end
      end
      assign_name(n.alias, ty, s.line)
    end
  end

  function C.AnnAssign(s)
    local ty = resolve_type(s.type)
    local rec = lookup_var(s.name)
    if rec then
      rec.type = ty
      rec.annotated = true
      rec.pending = false
      clear_narrow(s.name)
    else
      declare(s.name, ty, true)
    end
    if s.value then
      expect_assignable(infer(s.value, ty), ty, s.line, "cannot initialize '" .. s.name .. "'")
    end
  end

  function C.Assign(s)
    local targets, values = s.targets, s.values
    local star = false
    for _, t in ipairs(targets) do
      if t.tag == "Starred" then star = true end
    end
    if star or (#targets >= 2 and #values == 1 and values[1].tag ~= "Call" and values[1].tag ~= "Method" and values[1].tag ~= "LuaExpr") then
      local vt = infer(values[1])
      local elem = (vt.k == "list") and vt.elem or ANY
      for _, t in ipairs(targets) do
        if t.tag == "Starred" then assign_target(t, vt.k == "list" and vt or mk_list(ANY), s.line)
        else assign_target(t, elem, s.line) end
      end
      return
    end
    if #values == 1 and #targets > 1 then
      infer(values[1])
      for _, t in ipairs(targets) do assign_target(t, ANY, s.line) end
      return
    end
    for i, t in ipairs(targets) do
      local v = values[i]
      if v then
        local want = target_expected(t)
        assign_target(t, infer(v, want), s.line)
      else
        assign_target(t, NIL, s.line)
      end
    end
  end

  function C.AugAssign(s)
    local tt = infer(s.target)
    local vt = infer(s.value)
    local op = s.op
    if op == ".." then
      if not textual(tt) or not textual(vt) then
        err(s.line, "operator '..=' joins strings and numbers, got " .. tostr(tt) .. " and " .. tostr(vt))
      end
    else
      if not numeric(tt) or not numeric(vt) then
        err(s.line, "operator '" .. op .. "=' needs numbers, got " .. tostr(tt) .. " and " .. tostr(vt))
      end
    end
    if s.target.tag == "Name" then clear_narrow(s.target.name) end
  end

  local function let_like(s, names, kind)
    local ty
    if s.tag == "Let" then
      if s.ltype then ty = resolve_type(s.ltype) end
    else
      if s.ctype then ty = resolve_type(s.ctype) end
    end
    local values = s.values or { s.value }
    if s.star then
      local vt = infer(values[1])
      for i, nm in ipairs(names) do
        if i == s.star then declare(nm, vt.k == "list" and vt or mk_list(ANY), true)
        else declare(nm, vt.k == "list" and vt.elem or ANY, true) end
      end
      return
    end
    local inferred = {}
    for i, v in ipairs(values) do inferred[i] = infer(v, ty) end
    for i, nm in ipairs(names) do
      local it = inferred[i]
      if ty then
        if it then expect_assignable(it, ty, s.line, "cannot initialize '" .. nm .. "'") end
        declare(nm, ty, true)
      elseif it then
        declare(nm, (it.k == "nil") and ANY or it, false)
      else
        declare(nm, ANY, false)
      end
    end
  end

  function C.Let(s) let_like(s, s.names) end
  function C.Const(s) let_like(s, { s.name }) end
  function C.Override(s) let_like(s, { s.name }) end

  function C.Return(s)
    if #s.values == 0 then
      if ret_collect then ret_collect[#ret_collect + 1] = NIL end
      return
    end
    local want = cur_ret
    local first = infer(s.values[1], want and want.k ~= "any" and want or nil)
    if ret_collect then ret_collect[#ret_collect + 1] = (#s.values == 1) and first or ANY end
    for i = 2, #s.values do infer(s.values[i]) end
    if #s.values == 1 and want and want.k ~= "any" then
      expect_assignable(first, want, s.line, "wrong return type")
    end
  end

  function C.Raise(s)
    if s.value then infer(s.value) end
  end

  local function apply_neg_to_frame(cond)
    apply_facts(facts(cond, false))
  end

  function C.If(s)
    infer(s.cond)
    push_frame()
    apply_facts(facts(s.cond, true))
    check_block(s.body)
    pop_frame()
    local negs = facts(s.cond, false)
    for _, e in ipairs(s.elifs) do
      push_frame()
      apply_facts(negs)
      strict_now = true
      infer(e.cond)
      local pos = facts(e.cond, true)
      push_frame()
      apply_facts(pos)
      check_block(e.body)
      pop_frame()
      pop_frame()
      merge_into(negs, facts(e.cond, false))
    end
    if s.orelse then
      push_frame()
      apply_facts(negs)
      check_block(s.orelse)
      pop_frame()
    elseif #s.elifs == 0 and terminates(s.body) then
      apply_facts(negs)
    end
  end

  function C.While(s)
    infer(s.cond)
    push_frame()
    apply_facts(facts(s.cond, true))
    check_block(s.body)
    pop_frame()
  end

  function C.ForRange(s)
    infer(s.range.lo)
    infer(s.range.hi)
    if s.range.step then infer(s.range.step) end
    push_scope("block")
    declare(s.var, NUM, true)
    check_block(s.body)
    pop_scope()
  end

  function C.ForIn(s)
    local one, two, key = iter_types(s.iter)
    push_scope("block")
    if #s.vars == 1 then
      declare(s.vars[1], one, true)
    else
      declare(s.vars[1], key or ANY, true)
      declare(s.vars[2], two, true)
    end
    check_block(s.body)
    pop_scope()
  end

  function C.With(s)
    local t = infer(s.expr)
    push_scope("block")
    declare(s.name, t, true)
    check_block(s.body)
    pop_scope()
  end

  function C.Try(s)
    check_block(s.body)
    for _, h in ipairs(s.handlers) do
      push_scope("block")
      local ht = ANY
      if h.type then
        local ct = infer(h.type)
        if ct.k == "classobj" then ht = mk_inst(ct.cls) end
      else
        ht = mk_inst(genv.vars.Error.cls)
      end
      if h.name then declare(h.name, ht, true) end
      check_block(h.body)
      pop_scope()
    end
    if s.finally then check_block(s.finally) end
  end

  function C.ModeBlock(s)
    check_block(s.body)
  end

  function C.Match(s)
    infer(s.subject)
    for _, c in ipairs(s.cases) do
      push_scope("block")
      local names = {}
      collect_names({ { tag = "Match", cases = { { pattern = c.pattern, body = {} } } } }, function(nm) names[#names + 1] = nm end)
      for _, nm in ipairs(names) do
        local rec = lookup_var(nm)
        if rec then
          if rec.type == nil or rec.pending then rec.type = ANY rec.pending = false end
        else
          declare(nm, ANY, false)
        end
      end
      if c.guard then infer(c.guard) end
      check_block(c.body)
      pop_scope()
    end
  end

  -- функции и классы

  local function check_function_body(def, ft, cls, def_scope)
    local saved = { scope, narrow, cur_ret, cur_cls, ret_collect }
    scope = def_scope
    push_scope("fn")
    narrow = { {} }
    cur_ret = ft.ret
    cur_cls = cls
    ret_collect = {}
    local start = 1
    if cls and def.params[1] and def.params[1].name == "self" then
      declare("self", mk_inst(cls), true)
      start = 2
    end
    for i = start, #def.params do
      local p = def.params[i]
      local pt = p.type and resolve_type(p.type) or ANY
      declare(p.name, pt, true)
    end
    if def.vararg then declare(def.vararg, mk_list(def.vararg_type and resolve_type(def.vararg_type) or ANY), true) end
    local names = {}
    collect_names(def.body, function(nm) names[#names + 1] = nm end)
    for _, nm in ipairs(names) do
      if not scope.vars[nm] and not lookup_var(nm) then declare(nm, nil, false, true) end
    end
    for _, s in ipairs(def.body) do check_stmt(s) end
    if def.ret == nil then
      ft.inferred = (#ret_collect > 0) and union(ret_collect) or ANY
    end
    scope, narrow, cur_ret, cur_cls, ret_collect = saved[1], saved[2], saved[3], saved[4], saved[5]
  end

  function C.FuncDef(s)
    local ft = fn_from_def(s, false)
    local rec = lookup_var(s.name)
    if rec then
      rec.type = ft
      rec.pending = false
    else
      declare(s.name, ft, true)
    end
    local def_scope = scope
    deferred[#deferred + 1] = function()
      strict_now = true
      check_function_body(s, ft, nil, def_scope)
    end
  end

  -- заранее находит поля, которые методы создают через self.name = ...
  local function prescan_fields(def, cls)
    local ptypes = {}
    for _, p in ipairs(def.params) do
      if p.type then ptypes[p.name] = p.type end
    end
    local function rhs_type(v)
      if not v then return ANY end
      local tag = v.tag
      if tag == "Number" then return NUM
      elseif tag == "String" or tag == "FString" then return STR
      elseif tag == "Bool" then return BOOL
      elseif tag == "Name" and ptypes[v.name] then return resolve_type(ptypes[v.name]) end
      return ANY
    end
    local function walk(stmts)
      for _, st in ipairs(stmts) do
        local tag = st.tag
        if tag == "Assign" then
          for k, tg in ipairs(st.targets) do
            if tg.tag == "Attr" and not tg.opt and tg.obj.tag == "Name" and tg.obj.name == "self"
              and cls.fields[tg.name] == nil and not find_member(cls, tg.name) then
              cls.fields[tg.name] = rhs_type(st.values[k])
            end
          end
        elseif tag == "If" then
          walk(st.body)
          for _, e in ipairs(st.elifs) do walk(e.body) end
          if st.orelse then walk(st.orelse) end
        elseif tag == "While" or tag == "ForRange" or tag == "ForIn" or tag == "With" or tag == "ModeBlock" then
          walk(st.body)
        elseif tag == "Try" then
          walk(st.body)
          for _, h in ipairs(st.handlers) do walk(h.body) end
          if st.finally then walk(st.finally) end
        end
      end
    end
    walk(def.body)
  end

  function C.ClassDef(s)
    local base
    if s.base then
      local bt = infer(s.base)
      if bt.k == "classobj" then base = bt.cls
      elseif bt.k ~= "any" then err(s.line, "base of class '" .. s.name .. "' must be a class, got " .. tostr(bt)) end
    end
    local cls = new_class(s.name, base, false)
    local rec = lookup_var(s.name)
    if rec then
      rec.type = mk_classobj(cls)
      rec.pending = false
    else
      declare(s.name, mk_classobj(cls), true)
    end
    types[s.name] = mk_inst(cls)
    local def_scope = scope
    local methods = {}
    for _, m in ipairs(s.body) do
      strict_now = s.strict and true or false
      if m.tag == "AnnAssign" then
        local ty = resolve_type(m.type)
        cls.fields[m.name] = ty
        if m.value then expect_assignable(infer(m.value, ty), ty, m.line, "cannot initialize '" .. m.name .. "'") end
      elseif m.tag == "Assign" and #m.targets == 1 and m.targets[1].tag == "Name" and #m.values == 1 then
        local vt = infer(m.values[1])
        cls.statics[m.targets[1].name] = (vt.k == "nil") and ANY or vt
      elseif m.tag == "FuncDef" then
        local ft = fn_from_def(m, true)
        cls.methods[m.name] = ft
        methods[#methods + 1] = { def = m, ft = ft }
        prescan_fields(m, cls)
      end
    end
    table.sort(methods, function(a, b)
      local ai, bi = a.def.name == "init", b.def.name == "init"
      if ai ~= bi then return ai end
      return a.def.line < b.def.line
    end)
    for _, mt in ipairs(methods) do
      deferred[#deferred + 1] = function()
        strict_now = true
        check_function_body(mt.def, mt.ft, cls, def_scope)
      end
    end
  end

  ---------------------------------------------------------------- заголовки .cuh

  local function load_header_body(stmts, target_vars)
    -- первый проход: оболочки классов и псевдонимы типов
    for _, s in ipairs(stmts) do
      if s.tag == "ClassDef" then
        local existing = target_vars[s.name]
        if existing and existing.k == "classobj" then
          -- redeclaring a class in a later header extends it
          s._cls = existing.cls
          if s.open then existing.cls.open = true end
        else
          local cls = new_class(s.name, nil, false)
          cls.open = s.open == true
          types[s.name] = mk_inst(cls)
          genv.types[s.name] = types[s.name]
          target_vars[s.name] = mk_classobj(cls)
          s._cls = cls
        end
      end
    end
    for _, s in ipairs(stmts) do
      if s.tag == "TypeAlias" then
        types[s.name] = resolve_type(s.type)
        genv.types[s.name] = types[s.name]
      end
    end
    for _, s in ipairs(stmts) do
      local tag = s.tag
      if tag == "FuncDef" then
        target_vars[s.name] = fn_from_def(s, false)
      elseif tag == "AnnAssign" then
        target_vars[s.name] = resolve_type(s.type)
      elseif tag == "ClassDef" then
        local cls = s._cls
        if s.base then
          local bt = s.base.tag == "Name" and genv.vars[s.base.name]
          if bt and bt.k == "classobj" then cls.base = bt.cls end
        end
        for _, m in ipairs(s.body) do
          if m.tag == "AnnAssign" then cls.fields[m.name] = resolve_type(m.type)
          elseif m.tag == "FuncDef" then cls.methods[m.name] = fn_from_def(m, true) end
        end
      elseif tag == "Namespace" then
        local existing = target_vars[s.name]
        local reuse = existing and existing.k == "ns"
        local members = reuse and existing.members or {}
        load_header_body(s.body, members)
        if s.name == "peripheral_types" then
          for pname, pty in pairs(members) do genv.periph[pname] = pty end
        elseif reuse then
          if s.open then existing.open = true end
        else
          target_vars[s.name] = { k = "ns", name = s.name, members = members, open = s.open }
        end
      end
    end
  end

  if hdr then
    push_scope("fn")
    load_header_body(ast.body, genv.vars)
    if #errors > 0 then
      local e = errors[1]
      U.fail(file, e.line, 1, "header error: " .. e.msg)
    end
    return
  end

  ---------------------------------------------------------------- запуск

  local directives = ast.directives or {}
  if opts and opts.strict then directives = { { line = 0, mode = "strict" } } end
  annotate(ast.body, directives, nil)
  if not any_strict(ast.body) then return end

  push_scope("fn")
  local names = {}
  collect_names(ast.body, function(nm) names[#names + 1] = nm end)
  for _, nm in ipairs(names) do
    if not genv.vars[nm] or true then declare(nm, nil, false, true) end
  end
  for _, s in ipairs(ast.body) do check_stmt(s) end
  local i = 1
  while i <= #deferred do
    deferred[i]()
    i = i + 1
  end

  if opts and opts.exports_mode then
    return M.build_exports(ast, scope, genv, lookup_var)
  end

  if opts and opts.collect then
    for _, e in ipairs(errors) do opts.collect[#opts.collect + 1] = e end
    return
  end

  if #errors > 0 then
    table.sort(errors, function(a, b) return a.line < b.line end)
    local parts = {}
    for k, e in ipairs(errors) do
      if k > 20 then
        parts[#parts + 1] = "... and " .. (#errors - 20) .. " more errors"
        break
      end
      parts[#parts + 1] = (k == 1) and e.msg or (file .. ":" .. e.line .. ": " .. e.msg)
    end
    U.fail(file, errors[1].line, 1, table.concat(parts, "\n"))
  end
end

-- Builds .cuh header text for the exports of a checked module (types inferred where there are no annotations).
function M.build_exports(ast, scope, genv, lookup_var)
  local names, seen = {}, {}
  local function add(n)
    if not seen[n] then
      seen[n] = true
      names[#names + 1] = n
    end
  end
  for _, s in ipairs(ast.body) do
    if s.exported then
      local tag = s.tag
      if tag == "FuncDef" or tag == "ClassDef" or tag == "Import" or tag == "AnnAssign" or tag == "Const" then
        add(s.name)
      elseif tag == "Let" then
        for _, n in ipairs(s.names) do add(n) end
      elseif tag == "Assign" then
        for _, t in ipairs(s.targets) do
          if t.tag == "Name" then add(t.name) end
        end
      end
    end
  end

  local classes = {}
  local function var_type(n)
    local rec = lookup_var(n)
    return rec and rec.type or ANY
  end
  for _, n in ipairs(names) do
    local ty = var_type(n)
    if ty.k == "classobj" then classes[ty.cls] = true end
  end

  local function known_class(cls)
    if classes[cls] then return true end
    local g = genv.types[cls.name]
    return g ~= nil and g.cls == cls
  end

  local ser
  local function ident(s)
    return type(s) == "string" and s:match("^[%a_][%w_]*$") ~= nil
  end

  function ser(t)
    local k = t.k
    if k == "num" or k == "str" or k == "bool" or k == "nil" or k == "any" then return k end
    if k == "list" then return "list[" .. ser(t.elem) .. "]" end
    if k == "dict" then return "dict[" .. ser(t.key) .. ", " .. ser(t.val) .. "]" end
    if k == "rec" then
      local keys = {}
      for n in pairs(t.fields) do
        if not ident(n) then return "any" end
        keys[#keys + 1] = n
      end
      table.sort(keys)
      local parts = {}
      for i, n in ipairs(keys) do parts[i] = n .. ": " .. ser(t.fields[n]) end
      return "{" .. table.concat(parts, ", ") .. "}"
    end
    if k == "union" then
      local function wrap(x)
        local s = ser(x)
        if x.k == "union" or x.k == "fn" then s = "(" .. s .. ")" end
        return s
      end
      if #t.items == 2 and has_nil(t) then return wrap(strip_nil(t)) .. "?" end
      local parts = {}
      for i, x in ipairs(t.items) do parts[i] = wrap(x) end
      return table.concat(parts, " | ")
    end
    if k == "fn" then
      if t.loose then return "fn" end
      local parts = {}
      for i, p in ipairs(t.params) do parts[i] = ser(p.type) end
      if t.rest then parts[#parts + 1] = "*" .. ser(t.rest) end
      local ret = t.ret
      if t.inferred and ret.k == "any" then ret = t.inferred end
      return "fn(" .. table.concat(parts, ", ") .. ") -> " .. ser(ret)
    end
    if k == "inst" then
      if known_class(t.cls) then return t.cls.name end
      return "any"
    end
    return "any"
  end

  local function ser_params(ft, with_self)
    local parts = {}
    if with_self then parts[1] = "self" end
    for _, p in ipairs(ft.params) do
      local item = (ident(p.name) and p.name or "arg") .. ": " .. ser(p.type)
      if p.optional then item = item .. " = ..." end
      parts[#parts + 1] = item
    end
    if ft.rest then parts[#parts + 1] = "*rest: " .. ser(ft.rest) end
    return table.concat(parts, ", ")
  end

  local function ser_ret(ft)
    local ret = ft.ret
    if ft.inferred and ret.k == "any" then ret = ft.inferred end
    return " -> " .. ser(ret)
  end

  local function sorted_keys(tbl)
    local keys = {}
    for n in pairs(tbl) do keys[#keys + 1] = n end
    table.sort(keys)
    return keys
  end

  local out = {}
  for _, n in ipairs(names) do
    local ty = var_type(n)
    if ty.k == "classobj" then
      local cls = ty.cls
      local head = "class " .. cls.name
      if cls.base and known_class(cls.base) then head = head .. "(" .. cls.base.name .. ")" end
      out[#out + 1] = head .. ":"
      local members = 0
      for _, f in ipairs(sorted_keys(cls.fields)) do
        if ident(f) then
          out[#out + 1] = "    " .. f .. ": " .. ser(cls.fields[f])
          members = members + 1
        end
      end
      for _, f in ipairs(sorted_keys(cls.statics)) do
        if ident(f) and cls.fields[f] == nil then
          out[#out + 1] = "    " .. f .. ": " .. ser(cls.statics[f])
          members = members + 1
        end
      end
      for _, f in ipairs(sorted_keys(cls.methods)) do
        local m = cls.methods[f]
        if ident(f) then
          out[#out + 1] = "    def " .. f .. "(" .. ser_params(m, true) .. ")" .. ser_ret(m)
          members = members + 1
        end
      end
      if members == 0 then out[#out + 1] = "    pass" end
    end
  end
  for _, n in ipairs(names) do
    local ty = var_type(n)
    if ty.k == "fn" and not ty.loose then
      out[#out + 1] = "def " .. n .. "(" .. ser_params(ty, false) .. ")" .. ser_ret(ty)
    elseif ty.k ~= "classobj" then
      out[#out + 1] = n .. ": " .. ser(ty)
    end
  end
  return table.concat(out, "\n") .. "\n"
end

return M
