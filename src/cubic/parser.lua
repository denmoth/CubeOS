-- Cubic: парсер (рекурсивный спуск) -> AST
local U, lexer = ...

local M = {}

local KEYWORDS = lexer.KEYWORDS

local AUG_OPS = { ["+="] = "+", ["-="] = "-", ["*="] = "*", ["/="] = "/", ["//="] = "//", ["%="] = "%", ["**="] = "**", ["..="] = ".." }
local CMP_OPS = U.set({ "==", "!=", "<", "<=", ">", ">=" })

local function make(toks, file, src)
  local i = 1
  local P = {}

  local function peek(k)
    return toks[i + (k or 0)] or toks[#toks]
  end

  local function next_tok()
    local t = toks[i]
    if t.t ~= "eof" then i = i + 1 end
    return t
  end

  local function describe(tok)
    local t = tok.t
    if t == "newline" then return "end of line"
    elseif t == "indent" then return "unexpected indent"
    elseif t == "dedent" then return "end of block"
    elseif t == "eof" then return "end of file"
    elseif t == "name" then return "'" .. tok.v .. "'"
    elseif t == "number" then return "number " .. tok.v
    elseif t == "string" or t == "fstring" then return "string"
    elseif t == "luablock" then return "lua: block"
    else return "'" .. t .. "'" end
  end

  local function fail(tok, msg)
    U.fail(file, tok.line, tok.col, msg)
  end

  local function expect(t, what)
    local tok = peek()
    if tok.t ~= t then
      fail(tok, "expected " .. (what or ("'" .. t .. "'")) .. ", got " .. describe(tok))
    end
    return next_tok()
  end

  local function accept(t)
    if peek().t == t then return next_tok() end
    return nil
  end

  local function expect_name(what)
    local tok = peek()
    if tok.t ~= "name" then
      fail(tok, "expected " .. (what or "a name") .. ", got " .. describe(tok))
    end
    return next_tok()
  end

  local function is_name_like(tok)
    return tok.t == "name" or KEYWORDS[tok.t] ~= nil
  end

  local parse_expr, parse_block_stmts, parse_statement, parse_suite, parse_simple

  ---------------------------------------------------------------- выражения

  local function parse_exprlist()
    local list = { parse_expr() }
    while accept(",") do
      list[#list + 1] = parse_expr()
    end
    return list
  end

  local function parse_args()
    -- '(' уже прочитана
    local args = {}
    while peek().t ~= ")" do
      local tok = peek()
      if tok.t == "name" and peek(1).t == "=" then
        fail(tok, "keyword arguments are not supported yet")
      end
      if tok.t == "*" then
        fail(tok, "argument unpacking (*args) is not supported yet")
      end
      args[#args + 1] = parse_expr()
      if not accept(",") then break end
    end
    expect(")", "')' to close the argument list")
    return args
  end

  local function is_paren_lambda()
    -- peek() это '('; ищем парную ')' и проверяем '=>'
    local depth, j = 0, i
    while true do
      local t = toks[j]
      if not t or t.t == "eof" then return false end
      if t.t == "(" then depth = depth + 1
      elseif t.t == ")" then
        depth = depth - 1
        if depth == 0 then
          return toks[j + 1] and toks[j + 1].t == "=>"
        end
      end
      j = j + 1
    end
  end

  local function parse_lambda_params()
    local params = {}
    expect("(")
    while peek().t ~= ")" do
      params[#params + 1] = expect_name("a parameter name").v
      if not accept(",") then break end
    end
    expect(")")
    return params
  end

  local function parse_fstring(tok)
    local parts = {}
    for _, part in ipairs(tok.v) do
      if part.kind == "str" then
        parts[#parts + 1] = { kind = "str", v = part.v }
      else
        local sub = lexer.tokenize(part.src, file, { expr = true, first_line = part.line })
        local Q = make(sub, file, part.src)
        local node = Q.parse_expr()
        Q.expect_eof()
        parts[#parts + 1] = { kind = "expr", node = node }
      end
    end
    return { tag = "FString", parts = parts, line = tok.line }
  end

  local function parse_list(tok)
    local items = {}
    while peek().t ~= "]" do
      items[#items + 1] = parse_expr()
      if not accept(",") then break end
    end
    expect("]", "']' to close the list")
    return { tag = "List", items = items, line = tok.line }
  end

  local function parse_dict(tok)
    local entries = {}
    while peek().t ~= "}" do
      local k = peek()
      local entry
      if k.t == "[" then
        next_tok()
        local ke = parse_expr()
        expect("]")
        expect(":")
        entry = { kind = "expr", key = ke, value = parse_expr() }
      elseif is_name_like(k) and peek(1).t == ":" and k.t ~= "true" and k.t ~= "false" and k.t ~= "nil" then
        next_tok()
        next_tok()
        entry = { kind = "name", key = k.v, value = parse_expr() }
      elseif k.t == "string" and peek(1).t == ":" then
        next_tok()
        next_tok()
        entry = { kind = "str", key = k.v, value = parse_expr() }
      elseif k.t == "number" and peek(1).t == ":" then
        next_tok()
        next_tok()
        entry = { kind = "num", key = k.v, value = parse_expr() }
      else
        fail(k, "dict keys must be a name, a string/number literal or [expression]")
      end
      entries[#entries + 1] = entry
      if not accept(",") then break end
    end
    expect("}", "'}' to close the dict")
    return { tag = "Dict", entries = entries, line = tok.line }
  end

  local function parse_primary()
    local tok = peek()
    local t = tok.t
    if t == "number" then
      next_tok()
      return { tag = "Number", v = tok.v, line = tok.line }
    elseif t == "string" then
      next_tok()
      return { tag = "String", v = tok.v, line = tok.line }
    elseif t == "fstring" then
      next_tok()
      return parse_fstring(tok)
    elseif t == "true" or t == "false" then
      next_tok()
      return { tag = "Bool", v = (t == "true"), line = tok.line }
    elseif t == "nil" then
      next_tok()
      return { tag = "Nil", line = tok.line }
    elseif t == "name" then
      if peek(1).t == "=>" then
        next_tok()
        next_tok()
        local body = parse_expr()
        return { tag = "Lambda", params = { tok.v }, body = body, line = tok.line }
      end
      next_tok()
      return { tag = "Name", name = tok.v, line = tok.line }
    elseif t == "(" then
      if is_paren_lambda() then
        local params = parse_lambda_params()
        expect("=>")
        local body = parse_expr()
        return { tag = "Lambda", params = params, body = body, line = tok.line }
      end
      next_tok()
      local e = parse_expr()
      expect(")", "')'")
      return { tag = "Paren", e = e, line = tok.line }
    elseif t == "[" then
      next_tok()
      return parse_list(tok)
    elseif t == "{" then
      next_tok()
      return parse_dict(tok)
    elseif t == "lua" then
      next_tok()
      expect("(", "'(' after lua")
      local s = peek()
      if s.t ~= "string" then fail(s, "lua(...) needs a string literal with Lua code") end
      next_tok()
      expect(")")
      return { tag = "LuaExpr", code = s.v, line = tok.line }
    end
    fail(tok, "unexpected " .. describe(tok))
  end

  local function parse_postfix()
    local e = parse_primary()
    while true do
      local tok = peek()
      local t = tok.t
      if t == "(" then
        next_tok()
        e = { tag = "Call", fn = e, args = parse_args(), line = tok.line }
      elseif t == "[" then
        next_tok()
        local idx = parse_expr()
        if peek().t == ":" then
          fail(peek(), "slices are not supported yet")
        end
        expect("]", "']'")
        e = { tag = "Index", obj = e, idx = idx, line = tok.line }
      elseif t == "." then
        next_tok()
        local n = peek()
        if not is_name_like(n) then fail(n, "expected an attribute name after '.'") end
        next_tok()
        e = { tag = "Attr", obj = e, name = n.v, line = tok.line }
      elseif t == "?." then
        next_tok()
        local n = peek()
        if not is_name_like(n) then fail(n, "expected an attribute name after '?.'") end
        next_tok()
        e = { tag = "Attr", obj = e, name = n.v, opt = true, line = tok.line }
      elseif t == ":" and not tok.sp and is_name_like(peek(1)) and not peek(1).sp and peek(2).t == "(" then
        next_tok()
        local n = next_tok()
        next_tok() -- (
        e = { tag = "Method", obj = e, name = n.v, args = parse_args(), line = tok.line }
      else
        break
      end
    end
    return e
  end

  local parse_unary

  local function parse_pow()
    local base = parse_postfix()
    if peek().t == "**" then
      local tok = next_tok()
      local exp = parse_unary()
      return { tag = "Binary", op = "**", l = base, r = exp, line = tok.line }
    end
    return base
  end

  function parse_unary()
    local tok = peek()
    if tok.t == "-" then
      next_tok()
      return { tag = "Unary", op = "-", e = parse_unary(), line = tok.line }
    end
    return parse_pow()
  end

  local function parse_mul()
    local l = parse_unary()
    while true do
      local t = peek().t
      if t == "*" or t == "/" or t == "//" or t == "%" then
        local tok = next_tok()
        l = { tag = "Binary", op = t, l = l, r = parse_unary(), line = tok.line }
      else
        return l
      end
    end
  end

  local function parse_add()
    local l = parse_mul()
    while true do
      local t = peek().t
      if t == "+" or t == "-" then
        local tok = next_tok()
        l = { tag = "Binary", op = t, l = l, r = parse_mul(), line = tok.line }
      else
        return l
      end
    end
  end

  local function parse_concat()
    local l = parse_add()
    if peek().t == ".." then
      local tok = next_tok()
      return { tag = "Binary", op = "..", l = l, r = parse_concat(), line = tok.line }
    end
    return l
  end

  local function cmp_op()
    local tok = peek()
    local t = tok.t
    if CMP_OPS[t] then
      next_tok()
      return t
    elseif t == "in" then
      next_tok()
      return "in"
    elseif t == "not" and peek(1).t == "in" then
      next_tok()
      next_tok()
      return "not in"
    elseif t == "is" then
      next_tok()
      if accept("not") then return "is not" end
      return "is"
    end
    return nil
  end

  local function parse_comparison()
    local l = parse_concat()
    local tok = peek()
    local op = cmp_op()
    if not op then return l end
    local r = parse_concat()
    local node = { tag = "Binary", op = op, l = l, r = r, line = tok.line }
    local extra = peek()
    if CMP_OPS[extra.t] or extra.t == "in" or extra.t == "is" or (extra.t == "not" and peek(1).t == "in") then
      fail(extra, "chained comparisons are not supported; use 'and' to combine them")
    end
    return node
  end

  local function parse_not()
    local tok = peek()
    if tok.t == "not" then
      next_tok()
      return { tag = "Unary", op = "not", e = parse_not(), line = tok.line }
    end
    return parse_comparison()
  end

  local function parse_and()
    local l = parse_not()
    while peek().t == "and" do
      local tok = next_tok()
      l = { tag = "Binary", op = "and", l = l, r = parse_not(), line = tok.line }
    end
    return l
  end

  local function parse_or()
    local l = parse_and()
    while peek().t == "or" do
      local tok = next_tok()
      l = { tag = "Binary", op = "or", l = l, r = parse_and(), line = tok.line }
    end
    return l
  end

  local function parse_coalesce()
    local l = parse_or()
    while peek().t == "??" do
      local tok = next_tok()
      l = { tag = "Binary", op = "??", l = l, r = parse_or(), line = tok.line }
    end
    return l
  end

  function parse_expr()
    local e = parse_coalesce()
    if peek().t == "if" then
      local tok = next_tok()
      local cond = parse_coalesce()
      expect("else", "'else' in a conditional expression")
      local other = parse_expr()
      return { tag = "Ternary", cond = cond, a = e, b = other, line = tok.line }
    end
    return e
  end

  P.parse_expr = parse_expr

  function P.expect_eof()
    local tok = peek()
    if tok.t ~= "eof" then fail(tok, "unexpected " .. describe(tok) .. " in expression") end
  end

  ---------------------------------------------------------------- инструкции

  local function check_target(e)
    local tag = e.tag
    if tag == "Name" or tag == "Index" then return end
    if tag == "Attr" and not e.opt then return end
    U.fail(file, e.line, 1, "cannot assign to this expression")
  end

  local function parse_params()
    expect("(")
    local params, vararg = {}, nil
    while peek().t ~= ")" do
      if peek().t == "*" then
        next_tok()
        vararg = expect_name("a name after '*'").v
        if peek().t == "," then fail(peek(), "the *vararg parameter must be last") end
        break
      end
      local n = expect_name("a parameter name")
      local p = { name = n.v, line = n.line }
      if peek().t == ":" then
        fail(peek(), "type annotations are not supported yet")
      end
      if accept("=") then p.default = parse_expr() end
      params[#params + 1] = p
      if not accept(",") then break end
    end
    expect(")", "')' to close the parameters")
    if peek().t == "->" then fail(peek(), "return type annotations are not supported yet") end
    return params, vararg
  end

  local function parse_def(exported)
    local tok = expect("def")
    local n = expect_name("a function name")
    local params, vararg = parse_params()
    local body = parse_suite()
    return { tag = "FuncDef", name = n.v, params = params, vararg = vararg, body = body, exported = exported, line = tok.line }
  end

  local function parse_class(exported)
    local tok = expect("class")
    local n = expect_name("a class name")
    local base
    if accept("(") then
      base = parse_expr()
      expect(")")
    end
    local body = parse_suite()
    return { tag = "ClassDef", name = n.v, base = base, body = body, exported = exported, line = tok.line }
  end

  local function parse_if()
    local tok = expect("if")
    local cond = parse_expr()
    local body = parse_suite()
    local node = { tag = "If", cond = cond, body = body, elifs = {}, line = tok.line }
    while peek().t == "elif" do
      local et = next_tok()
      local c = parse_expr()
      node.elifs[#node.elifs + 1] = { cond = c, body = parse_suite(), line = et.line }
    end
    if accept("else") then
      node.orelse = parse_suite()
    end
    return node
  end

  local function parse_while()
    local tok = expect("while")
    local cond = parse_expr()
    return { tag = "While", cond = cond, body = parse_suite(), line = tok.line }
  end

  local function parse_range(tok)
    -- peek() это имя range, дальше '[' или '('
    next_tok()
    local open = next_tok().t -- "[" или "("
    local lo = parse_expr()
    if peek().t ~= "," then
      fail(peek(), "range needs two bounds, e.g. range[1, 5] or range[0, n)")
    end
    next_tok()
    local hi = parse_expr()
    local close = peek()
    if close.t ~= "]" and close.t ~= ")" then
      fail(close, "expected ']' or ')' to close the range, got " .. describe(close))
    end
    next_tok()
    local step
    if peek().t == "name" and peek().v == "step" then
      next_tok()
      step = parse_expr()
    end
    return { tag = "Range", lo = lo, hi = hi, lo_incl = (open == "["), hi_incl = (close.t == "]"), step = step, line = tok.line }
  end

  local function parse_for()
    local tok = expect("for")
    local vars = { expect_name("a loop variable").v }
    if accept(",") then vars[2] = expect_name("a loop variable").v end
    expect("in")
    local node
    local itok = peek()
    if itok.t == "name" and itok.v == "range" and (peek(1).t == "[" or peek(1).t == "(") then
      local r = parse_range(itok)
      if #vars ~= 1 then fail(itok, "a range loop has exactly one variable") end
      node = { tag = "ForRange", var = vars[1], range = r, line = tok.line }
    else
      node = { tag = "ForIn", vars = vars, iter = parse_expr(), line = tok.line }
    end
    node.body = parse_suite()
    return node
  end

  local function parse_try()
    local tok = expect("try")
    local node = { tag = "Try", body = parse_suite(), handlers = {}, line = tok.line }
    while peek().t == "except" do
      local et = next_tok()
      local h = { line = et.line }
      if peek().t ~= ":" and peek().t ~= "as" then
        h.type = parse_expr()
      end
      if accept("as") then
        h.name = expect_name("a variable name").v
      end
      h.body = parse_suite()
      node.handlers[#node.handlers + 1] = h
    end
    if accept("finally") then
      node.finally = parse_suite()
    end
    if #node.handlers == 0 and not node.finally then
      fail(peek(), "try needs at least one except or a finally block")
    end
    for k, h in ipairs(node.handlers) do
      if not h.type and k < #node.handlers then
        U.fail(file, h.line, 1, "a bare 'except:' must be the last handler")
      end
    end
    return node
  end

  local function parse_path_text()
    local first = peek()
    local last = nil
    while true do
      local t = peek()
      local ok = t.t == "name" or t.t == "." or t.t == ".." or t.t == "/" or t.t == "$" or t.t == "-" or t.t == "number"
        or (KEYWORDS[t.t] and t.t ~= "as" and t.t ~= "import")
      if not ok then break end
      if last and (t.sp or last.e + 1 ~= t.s) then break end
      last = next_tok()
    end
    if not last then fail(first, "expected a module path after import") end
    local text = src:sub(first.s, last.e)
    local kind
    if text:match("^%.%.?/") or text:match("^/") or text:match("^%$") then
      kind = "path"
    elseif text:match("^[%a_][%w_%.]*$") and not text:find("%.%.") and not text:find("%.$") then
      kind = "module"
    else
      fail(first, "invalid import path '" .. text .. "'")
    end
    return text, kind, first
  end

  local function default_binding(text, kind, tok)
    local base
    if kind == "module" then
      base = text:match("([^%.]+)$")
    else
      base = text:match("([^/]+)$") or ""
      base = base:gsub("%.lua$", ""):gsub("%.cub$", "")
    end
    if not base:match("^[%a_][%w_]*$") or KEYWORDS[base] then
      fail(tok, "cannot derive a variable name from '" .. text .. "', use: import ... as <name>")
    end
    return base
  end

  local function parse_import(exported)
    local tok = expect("import")
    local text, kind, first = parse_path_text()
    local name
    if accept("as") then
      name = expect_name("a name after 'as'").v
    else
      name = default_binding(text, kind, first)
    end
    return { tag = "Import", path = text, kind = kind, name = name, exported = exported, line = tok.line }
  end

  local function parse_from()
    local tok = expect("from")
    local text, kind = parse_path_text()
    expect("import")
    local names = {}
    repeat
      local n = expect_name("a name to import")
      local alias = n.v
      if accept("as") then alias = expect_name("a name after 'as'").v end
      names[#names + 1] = { name = n.v, alias = alias, line = n.line }
    until not accept(",")
    return { tag = "FromImport", path = text, kind = kind, names = names, line = tok.line }
  end

  function parse_simple(exported)
    local tok = peek()
    local t = tok.t
    if t == "return" then
      next_tok()
      local values = {}
      if peek().t ~= "newline" and peek().t ~= "eof" then values = parse_exprlist() end
      return { tag = "Return", values = values, line = tok.line }
    elseif t == "break" then
      next_tok()
      return { tag = "Break", line = tok.line }
    elseif t == "continue" then
      next_tok()
      return { tag = "Continue", line = tok.line }
    elseif t == "pass" then
      next_tok()
      return { tag = "Pass", line = tok.line }
    elseif t == "raise" then
      next_tok()
      local e
      if peek().t ~= "newline" and peek().t ~= "eof" then e = parse_expr() end
      return { tag = "Raise", value = e, line = tok.line }
    elseif t == "import" then
      return parse_import(exported)
    elseif t == "from" then
      return parse_from()
    elseif t == "luablock" then
      next_tok()
      return { tag = "LuaBlock", code = tok.v, line = tok.line }
    elseif t == "let" then
      next_tok()
      local names = { expect_name("a variable name").v }
      while accept(",") do names[#names + 1] = expect_name("a variable name").v end
      local values = {}
      if accept("=") then values = parse_exprlist() end
      return { tag = "Let", names = names, values = values, exported = exported, line = tok.line }
    elseif t == "const" or t == "override" then
      next_tok()
      local n = expect_name("a name")
      expect("=")
      return { tag = (t == "const") and "Const" or "Override", name = n.v, value = parse_expr(), exported = exported, line = tok.line }
    end

    local first = parse_expr()
    local nt = peek().t
    if nt == "," or nt == "=" then
      local targets = { first }
      while accept(",") do targets[#targets + 1] = parse_expr() end
      expect("=", "'=' in assignment")
      for _, tg in ipairs(targets) do check_target(tg) end
      local values = parse_exprlist()
      if peek().t == "=" then fail(peek(), "chained assignment is not supported") end
      return { tag = "Assign", targets = targets, values = values, exported = exported, line = tok.line }
    elseif AUG_OPS[nt] then
      local optok = next_tok()
      check_target(first)
      local value = parse_expr()
      return { tag = "AugAssign", target = first, op = AUG_OPS[nt], value = value, line = optok.line }
    end
    return { tag = "ExprStmt", e = first, line = tok.line }
  end

  local function end_simple()
    local tok = peek()
    if tok.t == "newline" then
      next_tok()
    elseif tok.t ~= "eof" and tok.t ~= "dedent" then
      fail(tok, "unexpected " .. describe(tok) .. " (expected end of line)")
    end
  end

  function parse_statement()
    local tok = peek()
    local t = tok.t
    if t == "if" then return parse_if()
    elseif t == "while" then return parse_while()
    elseif t == "for" then return parse_for()
    elseif t == "def" then return parse_def(false)
    elseif t == "class" then return parse_class(false)
    elseif t == "try" then return parse_try()
    elseif t == "export" then
      next_tok()
      local k = peek().t
      if k == "def" then return parse_def(true) end
      if k == "class" then return parse_class(true) end
      if k == "import" or k == "let" or k == "const" or k == "name" then
        local s = parse_simple(true)
        if s.tag ~= "Assign" and s.tag ~= "Let" and s.tag ~= "Const" and s.tag ~= "Import" then
          fail(tok, "only definitions and assignments can be exported")
        end
        end_simple()
        return s
      end
      fail(tok, "export must be followed by def, class, import, let, const or an assignment")
    elseif t == "indent" then
      fail(tok, "unexpected indent")
    elseif t == "elif" or t == "else" or t == "except" or t == "finally" then
      fail(tok, "'" .. t .. "' without a matching statement")
    end
    local s = parse_simple(false)
    end_simple()
    return s
  end

  function parse_suite()
    expect(":", "':' before the block")
    if peek().t == "newline" then
      next_tok()
      if peek().t ~= "indent" then
        fail(peek(), "expected an indented block")
      end
      next_tok()
      local body = {}
      while peek().t ~= "dedent" and peek().t ~= "eof" do
        body[#body + 1] = parse_statement()
      end
      if peek().t == "dedent" then next_tok() end
      return body
    end
    local s = parse_simple(false)
    end_simple()
    return { s }
  end

  function P.parse_program()
    local body = {}
    while peek().t ~= "eof" do
      body[#body + 1] = parse_statement()
    end
    return { tag = "Module", body = body, line = 1 }
  end

  return P
end

function M.parse(src, file)
  src = src:gsub("^\239\187\191", ""):gsub("\r\n?", "\n")
  local toks = lexer.tokenize(src, file)
  local P = make(toks, file, src)
  return P.parse_program()
end

return M
