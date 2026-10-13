-- Cubic: лексер с токенами INDENT/DEDENT
-- Токен: { t = тип, v = значение, line, col, s = начало, e = конец, sp = был пробел перед }
-- Для операторов и ключевых слов t совпадает с текстом ("+", "if", ...),
-- для остальных: "name", "number", "string", "fstring", "newline", "indent", "dedent", "luablock", "eof".
local U = ...

local M = {}

M.KEYWORDS = U.set({
  "and", "or", "not", "if", "elif", "else", "while", "for", "in", "def", "return", "break",
  "continue", "pass", "class", "import", "from", "as", "export", "try", "except", "finally",
  "raise", "lua", "let", "const", "override", "is", "true", "false", "nil", "with",
})

local OPS3 = U.set({ "**=", "//=", "..=" })
local OPS2 = U.set({ "==", "!=", "<=", ">=", "=>", "??", "?.", "+=", "-=", "*=", "/=", "%=", "**", "//", "..", "->" })
local OPS1 = U.set({ "+", "-", "*", "/", "%", "(", ")", "[", "]", "{", "}", ",", ":", ".", "=", "<", ">", "@", "$", "|", "?" })

local SIMPLE_ESC = { n = "\n", t = "\t", r = "\r", a = "\a", b = "\b", f = "\f", v = "\v", ["0"] = "\0",
  ["\\"] = "\\", ['"'] = '"', ["'"] = "'" }

-- Раскодирует escape-последовательности. raw: текст между кавычками.
local function decode(raw, file, line, col)
  if not raw:find("\\", 1, true) then return raw end
  local out, i, n = {}, 1, #raw
  while i <= n do
    local c = raw:sub(i, i)
    if c ~= "\\" then
      out[#out + 1] = c
      i = i + 1
    else
      local d = raw:sub(i + 1, i + 1)
      if d == "" then
        U.fail(file, line, col, "string ends with a lone backslash")
      elseif d == "x" then
        local hex = raw:match("^%x%x", i + 2)
        if not hex then U.fail(file, line, col, "invalid \\x escape (need two hex digits)") end
        out[#out + 1] = string.char(tonumber(hex, 16))
        i = i + 4
      elseif d == "u" then
        local hex = raw:match("^{(%x+)}", i + 2)
        if not hex then U.fail(file, line, col, "invalid \\u escape (use \\u{XXXX})") end
        out[#out + 1] = U.utf8(tonumber(hex, 16))
        i = i + 4 + #hex
      elseif d:match("%d") then
        -- десятичный код как в Lua: \0, \12, \255
        local digits = raw:match("^%d%d?%d?", i + 1)
        local code = tonumber(digits)
        if code > 255 then U.fail(file, line, col, "decimal escape too large: \\" .. digits) end
        out[#out + 1] = string.char(code)
        i = i + 1 + #digits
      elseif d == "\n" then
        i = i + 2 -- продолжение строки
      elseif SIMPLE_ESC[d] then
        out[#out + 1] = SIMPLE_ESC[d]
        i = i + 2
      else
        U.fail(file, line, col, "unknown escape sequence \\" .. d)
      end
    end
  end
  return table.concat(out)
end

-- Разбирает содержимое f-строки на части: { {kind="str", v=...}, {kind="expr", src=..., line=...} }
local function split_fstring(raw, file, line, col)
  local parts, buf = {}, {}
  local i, n = 1, #raw
  local cur_line = line

  local function flush()
    if #buf > 0 then
      parts[#parts + 1] = { kind = "str", v = decode(table.concat(buf), file, cur_line, col) }
      buf = {}
    end
  end

  while i <= n do
    local c = raw:sub(i, i)
    if c == "{" then
      if raw:sub(i + 1, i + 1) == "{" then
        buf[#buf + 1] = "{"
        i = i + 2
      else
        flush()
        local depth, j = 1, i + 1
        local quote = nil
        while j <= n do
          local d = raw:sub(j, j)
          if quote then
            if d == quote then quote = nil end
          elseif d == '"' or d == "'" then
            quote = d
          elseif d == "{" or d == "(" or d == "[" then
            depth = depth + 1
          elseif d == "}" or d == ")" or d == "]" then
            depth = depth - 1
            if depth == 0 then break end
          end
          j = j + 1
        end
        if depth ~= 0 then U.fail(file, cur_line, col, "unterminated { in f-string") end
        local src = raw:sub(i + 1, j - 1)
        if src:find("\\", 1, true) then U.fail(file, cur_line, col, "backslash is not allowed inside f-string expressions") end
        -- спецификация формата: первый ':' вне скобок и кавычек
        local spec
        do
          local d, q = 0, nil
          for k = 1, #src do
            local ch = src:sub(k, k)
            if q then
              if ch == q then q = nil end
            elseif ch == '"' or ch == "'" then
              q = ch
            elseif ch == "(" or ch == "[" or ch == "{" then
              d = d + 1
            elseif ch == ")" or ch == "]" or ch == "}" then
              d = d - 1
            elseif ch == ":" and d == 0 then
              spec = src:sub(k + 1)
              src = src:sub(1, k - 1)
              break
            end
          end
        end
        if src:match("^%s*$") then U.fail(file, cur_line, col, "empty expression in f-string") end
        parts[#parts + 1] = { kind = "expr", src = src, line = cur_line, spec = spec }
        for _ in src:gmatch("\n") do cur_line = cur_line + 1 end
        i = j + 1
      end
    elseif c == "}" then
      if raw:sub(i + 1, i + 1) == "}" then
        buf[#buf + 1] = "}"
        i = i + 2
      else
        U.fail(file, cur_line, col, "single } in f-string (use }} for a literal brace)")
      end
    else
      if c == "\n" then cur_line = cur_line + 1 end
      buf[#buf + 1] = c
      i = i + 1
    end
  end
  flush()
  return parts
end

function M.tokenize(src, file, opts)
  opts = opts or {}
  src = src:gsub("^\239\187\191", ""):gsub("\r\n?", "\n")
  local len = #src
  local toks = {}
  local comments = {}
  toks.comments = comments
  local indents = { 0 }
  local pos, line, ls = 1, opts.first_line or 1, 1
  local depth = 0
  local expr_mode = opts.expr
  local bol = not expr_mode
  local sp = false

  local function fail(msg, l, c) U.fail(file, l or line, c or (pos - ls + 1), msg) end

  local function push(t, v, s, e, l, c)
    toks[#toks + 1] = { t = t, v = v, line = l or line, col = c or (s - ls + 1), s = s, e = e, sp = sp }
    sp = false
  end

  -- Строка: pos указывает на открывающую кавычку. prefix: nil | "f" | "r"; start: начало токена
  local function lex_string(prefix, start)
    local q = src:sub(pos, pos)
    local sline, scol = line, start - ls + 1
    local triple = src:sub(pos, pos + 2) == q .. q .. q
    local qlen = triple and 3 or 1
    local i = pos + qlen
    local content_start = i
    local closed = false
    while i <= len do
      local d = src:sub(i, i)
      if d == "\\" then
        i = i + 2
      elseif d == q and (not triple or src:sub(i, i + 2) == q .. q .. q) then
        closed = true
        break
      elseif d == "\n" and not triple then
        break
      else
        i = i + 1
      end
    end
    if not closed then U.fail(file, sline, scol, "unterminated string") end
    local raw = src:sub(content_start, i - 1)
    local endpos = i + qlen - 1
    if prefix == "f" then
      push("fstring", split_fstring(raw, file, sline, scol), start, endpos, sline, scol)
    elseif prefix == "r" then
      push("string", raw, start, endpos, sline, scol)
    else
      push("string", decode(raw, file, sline, scol), start, endpos, sline, scol)
    end
    local lastnl = nil
    for nlpos in raw:gmatch("()\n") do
      line = line + 1
      lastnl = content_start + nlpos - 1
    end
    if lastnl then ls = lastnl + 1 end
    pos = endpos + 1
  end

  while pos <= len do
    if bol then
      local _, e = src:find("^ *", pos)
      local ind = e - pos + 1
      local p = e + 1
      local c = src:sub(p, p)
      if c == "\t" then
        fail("tabs are not allowed for indentation (use spaces)", line, p - ls + 1)
      end
      if c == "" then
        pos = p
      elseif c == "\n" then
        pos = p + 1
        line = line + 1
        ls = pos
      elseif c == "#" then
        local nl = src:find("\n", p, true)
        comments[#comments + 1] = { line = line, text = src:sub(p + 1, (nl or (len + 1)) - 1) }
        if nl then
          pos = nl + 1
          line = line + 1
          ls = pos
        else
          pos = len + 1
        end
      else
        local top = indents[#indents]
        if ind > top then
          indents[#indents + 1] = ind
          push("indent", ind, p, p, line, 1)
        elseif ind < top then
          while ind < indents[#indents] do
            indents[#indents] = nil
            push("dedent", nil, p, p, line, 1)
          end
          if ind ~= indents[#indents] then
            fail("unindent does not match any outer indentation level", line, 1)
          end
        end
        pos = p
        bol = false
        sp = true

        -- блок lua:
        local hs, he = src:find("^lua *: *", pos)
        if hs then
          local rest = src:sub(he + 1, he + 1)
          if rest == "\n" or rest == "" or rest == "#" then
            local header_line = line
            local nl = src:find("\n", pos, true)
            local q = nl and nl + 1 or len + 1
            local cur = line + 1
            local lines, block_indent, last_content = {}, nil, 0
            while q <= len do
              local lend = src:find("\n", q, true) or (len + 1)
              local text = src:sub(q, lend - 1)
              if text:match("^ *$") then
                lines[#lines + 1] = ""
              else
                local lead = #text:match("^ *")
                if lead <= ind then break end
                if not block_indent then block_indent = lead end
                lines[#lines + 1] = text:sub(math.min(lead, block_indent) + 1)
                last_content = #lines
              end
              q = lend + 1
              cur = cur + 1
            end
            if not block_indent then fail("empty lua: block", header_line, 1) end
            while #lines > last_content do lines[#lines] = nil end
            push("luablock", table.concat(lines, "\n"), pos, pos, header_line + 1, 1)
            push("newline", nil, pos, pos, header_line, 1)
            pos = q
            line = cur
            ls = q
            bol = true
          end
        end
      end
    else
      local c = src:sub(pos, pos)
      if c == " " or c == "\t" then
        pos = pos + 1
        sp = true
      elseif c == "\n" then
        if depth > 0 or expr_mode then
          pos = pos + 1
          line = line + 1
          ls = pos
          sp = true
        else
          push("newline", nil, pos, pos)
          pos = pos + 1
          line = line + 1
          ls = pos
          bol = true
        end
      elseif c == "#" then
        local nl = src:find("\n", pos, true)
        comments[#comments + 1] = { line = line, text = src:sub(pos + 1, (nl or (len + 1)) - 1) }
        pos = nl or (len + 1)
        sp = true
      elseif c == "\\" then
        if src:sub(pos + 1, pos + 1) == "\n" then
          pos = pos + 2
          line = line + 1
          ls = pos
          sp = true
        else
          fail("unexpected character after line continuation backslash")
        end
      elseif c == '"' or c == "'" then
        lex_string(nil, pos)
      elseif c:match("%d") or (c == "." and src:sub(pos + 1, pos + 1):match("%d")) then
        local s, e = pos, pos
        local hs_, he_ = src:find("^0[xX]%x[%x_]*", pos)
        if hs_ then
          e = he_
        else
          if c ~= "." then
            local _, e1 = src:find("^%d[%d_]*", pos)
            e = e1
          else
            e = pos - 1
          end
          local fs_, fe = src:find("^%.%d[%d_]*", e + 1)
          if fs_ then e = fe end
          local es, ee = src:find("^[eE][+-]?%d+", e + 1)
          if es then e = ee end
        end
        local text = src:sub(s, e):gsub("_", "")
        if src:sub(e + 1, e + 1):match("[%a_]") then
          fail("invalid number literal")
        end
        push("number", text, s, e)
        pos = e + 1
      elseif c:match("[%a_]") then
        local s, e = src:find("^[%a_][%w_]*", pos)
        local word = src:sub(s, e)
        local nextc = src:sub(e + 1, e + 1)
        if (word == "f" or word == "r") and (nextc == '"' or nextc == "'") then
          pos = e + 1
          lex_string(word, s)
        else
          if M.KEYWORDS[word] then
            push(word, word, s, e)
          else
            push("name", word, s, e)
          end
          pos = e + 1
        end
      else
        local s3 = src:sub(pos, pos + 2)
        local s2 = src:sub(pos, pos + 1)
        local op
        if OPS3[s3] then
          op = s3
        elseif OPS2[s2] then
          op = s2
        elseif OPS1[c] then
          op = c
        end
        if not op then
          fail("unexpected character '" .. c .. "'")
        end
        if op == "(" or op == "[" or op == "{" then
          depth = depth + 1
        elseif op == ")" or op == "]" or op == "}" then
          depth = depth - 1
          if depth < 0 then fail("unmatched '" .. op .. "'") end
        end
        push(op, op, pos, pos + #op - 1)
        pos = pos + #op
      end
    end
  end

  if depth > 0 then
    U.fail(file, line, 1, "unexpected end of file: unclosed bracket")
  end
  if not expr_mode then
    local last = toks[#toks]
    if last and last.t ~= "newline" then
      push("newline", nil, len + 1, len + 1, line, len + 1 - ls + 1)
    end
    while #indents > 1 do
      indents[#indents] = nil
      push("dedent", nil, len + 1, len + 1, line, 1)
    end
  end
  push("eof", nil, len + 1, len + 1, line, len + 1 - ls + 1)
  return toks
end

return M
