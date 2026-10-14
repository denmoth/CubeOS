-- Cubic: данные для редакторов и IDE.
-- Всё, что компилятор и так знает о коде, отдаётся наружу без перекомпиляции в Lua:
--   language()                             словарь языка (ключевые слова, встроенные имена, сниппеты)
--   textmate()                             грамматика TextMate (VS Code, Sublime, GitHub) из того же словаря
--   highlight(src)                         токены для подсветки; терпит ошибки, комментарии включены
--   symbols(src)                           структура файла: функции, классы, методы, импорты, переменные
--   diagnostics(src, file, opts)           ошибки и предупреждения с координатами
--   complete(src, line, col, opts)         подсказки на Tab: имена, члены по типу, модули, ключевые слова, сниппеты
--   signature(src, line, col, opts)        параметры вызова функции под курсором
--   hover(src, line, col, opts)            тип и описание имени под курсором
-- Строки и столбцы считаются с единицы, столбец это номер байта в строке (UTF-8: байты, не символы).
-- Результаты состоят из обычных таблиц, их можно превратить в JSON без доработок.
local ctx = ...
local U, lexer, parser, checker, B, codegen = ctx.U, ctx.lexer, ctx.parser, ctx.checker, ctx.B, ctx.codegen
local modtypes, type_env = ctx.modtypes, ctx.type_env

local T = {}

---------------------------------------------------------------- словарь языка

local KEYWORD_GROUPS = {
  control = { "if", "elif", "else", "while", "for", "in", "return", "break", "continue", "pass", "try", "except", "finally", "raise", "with" },
  declaration = { "def", "class", "import", "from", "as", "export", "let", "const", "override", "lua" },
  operator = { "and", "or", "not", "is" },
}
local CONSTANTS = { "true", "false", "nil" }
local SOFT_KEYWORDS = { "match", "case", "strict", "loose" }
local CUBIC_BUILTINS = { "copy", "deepcopy", "len", "str", "num", "isinstance", "Error", "range", "super" }

local KEYWORD_GROUP_OF = {}
for group, list in pairs(KEYWORD_GROUPS) do
  for _, k in ipairs(list) do KEYWORD_GROUP_OF[k] = group end
end
local CONSTANT_SET = U.set(CONSTANTS)
local CUBIC_BUILTIN_SET = U.set(CUBIC_BUILTINS)

local function sorted_keys(set)
  local out = {}
  for k in pairs(set) do out[#out + 1] = k end
  table.sort(out)
  return out
end

local function lua_core_names()
  local out = {}
  for name in pairs(B.PROTECTED) do
    if not CUBIC_BUILTIN_SET[name] then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

local SNIPPETS = {
  { prefix = "def", label = "def", doc = "Функция", body = "def ${1:name}(${2}):\n    ${0:pass}" },
  { prefix = "class", label = "class", doc = "Класс с конструктором init", body = "class ${1:Name}:\n    def init(self${2}):\n        ${0:pass}" },
  { prefix = "if", label = "if", doc = "Условие", body = "if ${1:condition}:\n    ${0:pass}" },
  { prefix = "ifelse", label = "if / else", doc = "Условие с else", body = "if ${1:condition}:\n    ${2:pass}\nelse:\n    ${0:pass}" },
  { prefix = "for", label = "for in", doc = "Цикл по списку", body = "for ${1:item} in ${2:items}:\n    ${0:pass}" },
  { prefix = "forr", label = "for range", doc = "Цикл по интервалу (границы включены)", body = "for ${1:i} in range[${2:1}, ${3:n}]:\n    ${0:pass}" },
  { prefix = "while", label = "while", doc = "Цикл while", body = "while ${1:condition}:\n    ${0:pass}" },
  { prefix = "try", label = "try / except", doc = "Обработка ошибок", body = "try:\n    ${1:pass}\nexcept Error as ${2:e}:\n    ${0:pass}" },
  { prefix = "with", label = "with", doc = "Автозакрытие ресурса", body = "with ${1:resource} as ${2:name}:\n    ${0:pass}" },
  { prefix = "match", label = "match / case", doc = "Сопоставление с образцом", body = "match ${1:value}:\n    case ${2:pattern}:\n        ${0:pass}" },
  { prefix = "lua", label = "lua:", doc = "Вставка на чистом Lua", body = "lua:\n    ${0}" },
  { prefix = "import", label = "import", doc = "Подключить модуль", body = "import ${0:module}" },
  { prefix = "from", label = "from import", doc = "Подключить имена из модуля", body = "from ${1:module} import ${0:name}" },
  { prefix = "lambda", label = "lambda", doc = "Короткая функция", body = "(${1:x}) => ${0:x}" },
  { prefix = "strict", label = "#!strict", doc = "Включить строгую проверку типов", body = "#!strict" },
}

function T.language()
  local cc = {}
  for name in pairs(B.SHADOW_WARN) do cc[#cc + 1] = name end
  table.sort(cc)
  return {
    name = "Cubic",
    version = ctx.version,
    extensions = { ".cub", ".cuh" },
    comment = "#",
    keywords = KEYWORD_GROUPS,
    constants = CONSTANTS,
    soft_keywords = SOFT_KEYWORDS,
    cubic_builtins = CUBIC_BUILTINS,
    lua_builtins = lua_core_names(),
    cc_globals = cc,
    operators = { "+", "-", "*", "/", "%", "**", "//", "..", "==", "!=", "<", ">", "<=", ">=", "=", "+=", "-=", "*=", "/=", "%=", "**=", "//=", "..=", "=>", "->", "??", "?.", "|", "?", "@", "$" },
    brackets = { { "(", ")" }, { "[", "]" }, { "{", "}" } },
    string_prefixes = { "f", "r" },
    string_quotes = { "\"", "'", "\"\"\"", "'''" },
    escapes = { "\\n", "\\t", "\\r", "\\a", "\\b", "\\f", "\\v", "\\0", "\\\\", "\\\"", "\\'", "\\xHH", "\\u{H...}", "\\DDD" },
    directives = { "#!strict", "#!loose" },
    indent = { size = 4, increase_after = ":", spaces_only = true },
    token_kinds = { "keyword", "constant", "string", "escape", "number", "comment", "directive", "operator", "punct",
      "name", "variable", "parameter", "function", "method", "class", "property", "decorator", "namespace",
      "type", "builtin", "api", "self", "luacode", "error" },
    snippets = SNIPPETS,
  }
end

---------------------------------------------------------------- грамматика TextMate

local function alternation(list)
  local parts = {}
  for i, w in ipairs(list) do parts[i] = w end
  return table.concat(parts, "|")
end

function T.textmate()
  local lang = T.language()
  local ctl, decl, op = lang.keywords.control, lang.keywords.declaration, lang.keywords.operator
  local builtin_names = {}
  for _, n in ipairs(lang.cubic_builtins) do builtin_names[#builtin_names + 1] = n end
  for _, n in ipairs(lang.lua_builtins) do builtin_names[#builtin_names + 1] = n end
  return {
    name = "Cubic",
    scopeName = "source.cubic",
    fileTypes = { "cub", "cuh" },
    patterns = {
      { include = "#directive" }, { include = "#comment" }, { include = "#luablock" }, { include = "#fstring" },
      { include = "#string" }, { include = "#number" }, { include = "#decorator" }, { include = "#definition" },
      { include = "#keyword" }, { include = "#constant" }, { include = "#builtin" }, { include = "#api" },
      { include = "#call" }, { include = "#operator" },
    },
    repository = {
      directive = { match = "^\\s*#!(strict|loose)\\b.*$", name = "meta.preprocessor.cubic" },
      comment = { match = "#.*$", name = "comment.line.number-sign.cubic" },
      luablock = {
        begin = "^(\\s*)(lua)\\s*(:)\\s*(#.*)?$",
        ["end"] = "^(?!\\1\\s+\\S|\\s*$)",
        beginCaptures = { ["2"] = { name = "keyword.other.cubic" }, ["4"] = { name = "comment.line.number-sign.cubic" } },
        patterns = { { include = "source.lua" } },
        name = "meta.embedded.block.lua",
      },
      string = {
        patterns = {
          { begin = "[rR]?\"\"\"", ["end"] = "\"\"\"", name = "string.quoted.triple.cubic", patterns = { { include = "#escape" } } },
          { begin = "[rR]?'''", ["end"] = "'''", name = "string.quoted.triple.cubic", patterns = { { include = "#escape" } } },
          { begin = "[rR]?\"", ["end"] = "\"|$", name = "string.quoted.double.cubic", patterns = { { include = "#escape" } } },
          { begin = "[rR]?'", ["end"] = "'|$", name = "string.quoted.single.cubic", patterns = { { include = "#escape" } } },
        },
      },
      fstring = {
        patterns = {
          { begin = "f\"\"\"", ["end"] = "\"\"\"", name = "string.quoted.triple.cubic", patterns = { { include = "#escape" }, { include = "#interp" } } },
          { begin = "f\"", ["end"] = "\"|$", name = "string.quoted.double.cubic", patterns = { { include = "#escape" }, { include = "#interp" } } },
          { begin = "f'", ["end"] = "'|$", name = "string.quoted.single.cubic", patterns = { { include = "#escape" }, { include = "#interp" } } },
        },
      },
      interp = {
        begin = "(?<!\\{)\\{(?!\\{)",
        ["end"] = "\\}",
        name = "meta.interpolation.cubic",
        patterns = { { include = "$self" } },
      },
      escape = { match = "\\\\(x[0-9a-fA-F]{2}|u\\{[0-9a-fA-F]+\\}|[0-9]{1,3}|.)", name = "constant.character.escape.cubic" },
      number = { match = "\\b(0[xX][0-9a-fA-F_]+|[0-9][0-9_]*(\\.[0-9_]+)?([eE][+-]?[0-9]+)?)\\b", name = "constant.numeric.cubic" },
      decorator = { match = "^\\s*(@)([A-Za-z_][\\w.]*)", captures = { ["1"] = { name = "punctuation.decorator.cubic" }, ["2"] = { name = "entity.name.function.decorator.cubic" } } },
      definition = {
        patterns = {
          { match = "\\b(def)\\s+([A-Za-z_]\\w*)", captures = { ["1"] = { name = "keyword.declaration.cubic" }, ["2"] = { name = "entity.name.function.cubic" } } },
          { match = "\\b(class)\\s+([A-Za-z_]\\w*)", captures = { ["1"] = { name = "keyword.declaration.cubic" }, ["2"] = { name = "entity.name.class.cubic" } } },
        },
      },
      keyword = {
        patterns = {
          { match = "\\b(" .. alternation(ctl) .. ")\\b", name = "keyword.control.cubic" },
          { match = "\\b(" .. alternation(decl) .. ")\\b", name = "keyword.declaration.cubic" },
          { match = "\\b(" .. alternation(op) .. ")\\b", name = "keyword.operator.word.cubic" },
          { match = "^\\s*(match|case)\\b(?=.*:\\s*$)", captures = { ["1"] = { name = "keyword.control.cubic" } } },
          { match = "^\\s*(strict|loose)(?=\\s*:\\s*$)", name = "keyword.other.cubic" },
        },
      },
      constant = { match = "\\b(" .. alternation(lang.constants) .. ")\\b", name = "constant.language.cubic" },
      builtin = { match = "\\b(" .. alternation(builtin_names) .. ")\\b", name = "support.function.builtin.cubic" },
      api = { match = "\\b(" .. alternation(lang.cc_globals) .. ")\\b", name = "support.class.cc.cubic" },
      call = { match = "\\b([A-Za-z_]\\w*)(?=\\s*\\()", name = "entity.name.function.call.cubic" },
      operator = { match = "=>|->|\\?\\?|\\?\\.|\\.\\.=?|\\*\\*=?|//=?|[+\\-*/%<>=!]=?|[|?@$]", name = "keyword.operator.cubic" },
    },
  }
end

---------------------------------------------------------------- подсветка

local OPS3 = U.set({ "**=", "//=", "..=" })
local OPS2 = U.set({ "==", "!=", "<=", ">=", "=>", "??", "?.", "+=", "-=", "*=", "/=", "%=", "**", "//", "..", "->" })
local OPS1 = U.set({ "+", "-", "*", "/", "%", "(", ")", "[", "]", "{", "}", ",", ":", ".", "=", "<", ">", "@", "$", "|", "?" })
local PUNCT = U.set({ "(", ")", "[", "]", "{", "}", ",", ":", "." })

local function split_lines(src)
  local lines = {}
  for l in (src .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
  if #lines > 1 and lines[#lines] == "" then lines[#lines] = nil end
  return lines
end

-- Сырые токены, без разбора контекста. Никогда не бросает ошибку.
local function scan(src)
  src = src:gsub("\r\n?", "\n")
  local len = #src
  local starts = { 1 }
  for p in src:gmatch("()\n") do starts[#starts + 1] = p + 1 end

  local function line_of(pos)
    local lo, hi = 1, #starts
    while lo < hi do
      local mid = math.floor((lo + hi + 1) / 2)
      if starts[mid] <= pos then lo = mid else hi = mid - 1 end
    end
    return lo
  end

  -- строки блоков lua:
  local lua_lines = {}
  local embedded = {}
  local lines = split_lines(src)
  do
    local l = 1
    while l <= #lines do
      local lead, rest = lines[l]:match("^( *)lua *:(.*)$")
      if lead and (rest:match("^ *$") or rest:match("^ *#")) then
        local first, last
        local k = l + 1
        while k <= #lines do
          local text = lines[k]
          if text:match("^ *$") then
            -- пустая строка может принадлежать блоку
          else
            if #text:match("^ *") <= #lead then break end
            first = first or k
            last = k
          end
          k = k + 1
        end
        if first then
          for x = l + 1, last do lua_lines[x] = true end
          embedded[#embedded + 1] = { lang = "lua", from_line = first, to_line = last }
        end
        l = (last or l) + 1
      else
        l = l + 1
      end
    end
  end

  local toks = {}
  local function emit(kind, s, e, extra)
    local l = line_of(s)
    local pos = s
    while pos <= e do
      local nl = src:find("\n", pos, true)
      local seg_end = (nl and nl <= e) and nl - 1 or e
      if seg_end >= pos then
        local t = { kind = kind, line = l, col = pos - starts[l] + 1, len = seg_end - pos + 1, s = pos, e = seg_end, text = src:sub(pos, seg_end) }
        if extra then for k, v in pairs(extra) do t[k] = v end end
        toks[#toks + 1] = t
      end
      if not nl or nl > e then break end
      pos = nl + 1
      l = l + 1
    end
  end

  local scan_range

  local function scan_string(i, prefix_start, prefix)
    local q = src:sub(i, i)
    local triple = src:sub(i, i + 2) == q:rep(3)
    local ql = triple and 3 or 1
    local j = i + ql
    local piece = prefix_start
    local closed = false
    local function flush(upto)
      if upto >= piece then emit("string", piece, upto) end
    end
    while j <= len do
      local d = src:sub(j, j)
      if d == "\\" then
        if prefix == "r" then
          j = j + 2
        else
          flush(j - 1)
          local nxt = src:sub(j + 1, j + 1)
          local esc_end = j + 1
          if nxt == "x" then
            esc_end = j + 3
          elseif nxt == "u" and src:sub(j + 2, j + 2) == "{" then
            esc_end = src:find("}", j + 3, true) or (j + 2)
          elseif nxt:match("%d") then
            local _, e = src:find("^%d%d?%d?", j + 1)
            esc_end = e
          end
          if esc_end > len then esc_end = len end
          emit("escape", j, esc_end)
          piece = esc_end + 1
          j = esc_end + 1
        end
      elseif prefix == "f" and d == "{" then
        if src:sub(j + 1, j + 1) == "{" then
          j = j + 2
        else
          local k, depth = j + 1, 1
          while k <= len do
            local ch = src:sub(k, k)
            if ch == "{" then
              depth = depth + 1
            elseif ch == "}" then
              depth = depth - 1
              if depth == 0 then break end
            elseif ch == "\n" and not triple then
              break
            elseif ch == q and not triple then
              break
            end
            k = k + 1
          end
          if k <= len and src:sub(k, k) == "}" and depth == 0 then
            flush(j - 1)
            emit("punct", j, j, { interp = true })
            -- формат после верхнеуровневого ':'
            local inner_end, spec_at = k - 1, nil
            local nest = 0
            for p = j + 1, k - 1 do
              local ch = src:sub(p, p)
              if ch == "(" or ch == "[" or ch == "{" then
                nest = nest + 1
              elseif ch == ")" or ch == "]" or ch == "}" then
                nest = nest - 1
              elseif ch == ":" and nest == 0 then
                spec_at = p
                break
              end
            end
            if spec_at then inner_end = spec_at - 1 end
            scan_range(j + 1, inner_end)
            if spec_at then emit("string", spec_at, k - 1, { spec = true }) end
            emit("punct", k, k, { interp = true })
            piece = k + 1
            j = k + 1
          else
            j = j + 1
          end
        end
      elseif d == q and (not triple or src:sub(j, j + 2) == q:rep(3)) then
        closed = true
        flush(j + ql - 1)
        j = j + ql
        piece = j
        break
      elseif d == "\n" and not triple then
        break
      else
        j = j + 1
      end
    end
    if not closed then
      flush(math.min(j - 1, len))
      if #toks > 0 and toks[#toks].kind == "string" then toks[#toks].open = true end
    end
    return j
  end

  function scan_range(i, stop)
    while i <= stop do
      local c = src:sub(i, i)
      if c == "\n" then
        local nextline = line_of(i) + 1
        i = i + 1
        if lua_lines[nextline] then
          local ls = starts[nextline]
          local le = (starts[nextline + 1] or (len + 2)) - 2
          local text = src:sub(ls, le)
          local lead = #text:match("^ *")
          if lead < #text then emit("luacode", ls + lead, le) end
          i = le + 1
          if i == len + 1 then break end
        end
      elseif c == " " or c == "\t" or c == "\r" then
        i = i + 1
      elseif c == "#" then
        local e = (src:find("\n", i, true) or (len + 1)) - 1
        if e > stop then e = stop end
        local ls = starts[line_of(i)]
        local text = src:sub(i, e)
        if i - ls == #src:sub(ls, i - 1):match("^ *") and text:match("^#!%s*(%a+)%s*$") then
          emit("directive", i, e)
        else
          emit("comment", i, e)
        end
        i = e + 1
      elseif c == '"' or c == "'" then
        i = scan_string(i, i, nil)
      elseif c:match("[%a_]") then
        local s, e = src:find("^[%a_][%w_]*", i)
        local word = src:sub(s, e)
        local nextc = src:sub(e + 1, e + 1)
        if (word == "f" or word == "r") and (nextc == '"' or nextc == "'") then
          i = scan_string(e + 1, s, word)
        else
          if KEYWORD_GROUP_OF[word] then
            emit("keyword", s, e, { group = KEYWORD_GROUP_OF[word] })
          elseif CONSTANT_SET[word] then
            emit("constant", s, e)
          else
            emit("name", s, e)
          end
          i = e + 1
        end
      elseif c:match("%d") or (c == "." and src:sub(i + 1, i + 1):match("%d")) then
        local s, e = i, i
        local hs, he = src:find("^0[xX]%x[%x_]*", i)
        if hs then
          e = he
        else
          if c ~= "." then
            local _, e1 = src:find("^%d[%d_]*", i)
            e = e1
          else
            e = i - 1
          end
          local fs_, fe = src:find("^%.%d[%d_]*", e + 1)
          if fs_ then e = fe end
          local es, ee = src:find("^[eE][+-]?%d+", e + 1)
          if es then e = ee end
        end
        emit("number", s, e)
        i = e + 1
      else
        local s3, s2 = src:sub(i, i + 2), src:sub(i, i + 1)
        local op
        if OPS3[s3] then op = s3 elseif OPS2[s2] then op = s2 elseif OPS1[c] then op = c end
        if op then
          emit(PUNCT[op] and "punct" or "operator", i, i + #op - 1)
          i = i + #op
        else
          emit("error", i, i)
          i = i + 1
        end
      end
    end
  end

  scan_range(1, len)
  return toks, embedded, lines
end

local function is_sig(t)
  local k = t.kind
  return k ~= "comment" and k ~= "directive" and k ~= "luacode"
end

-- Уточняет смысл имён по соседним токенам
local function refine(toks, src)
  local sig = {}
  for _, t in ipairs(toks) do
    if is_sig(t) and not (t.kind == "string") and not (t.kind == "escape") then sig[#sig + 1] = t end
  end
  local n = #sig

  local function first_on_line(k)
    return k == 1 or sig[k - 1].line ~= sig[k].line
  end

  -- конец строки (последний значимый токен строки)
  local function last_on_line(k)
    return k == n or sig[k + 1].line ~= sig[k].line
  end

  local function adjacent(a, b)
    return a.e + 1 == b.s
  end

  local stack = {}
  local import_state = nil -- nil | "mod" | "names"
  local import_from = false
  local params_end = nil

  -- параметры def: от '(' до парной ')'
  local function mark_params(k)
    local depth = 0
    local j = k
    local in_type = false
    local type_depth = 0
    while j <= n do
      local t = sig[j]
      if t.text == "(" or t.text == "[" or t.text == "{" then
        depth = depth + 1
      elseif t.text == ")" or t.text == "]" or t.text == "}" then
        depth = depth - 1
        if depth == 0 then return j end
        if in_type and depth < type_depth then in_type = false end
      elseif depth == 1 and t.text == "," then
        in_type = false
      elseif depth == 1 and t.text == "=" then
        in_type = false
      elseif depth == 1 and t.text == ":" then
        in_type = true
        type_depth = 1
      elseif t.kind == "name" or t.kind == "variable" or t.kind == "builtin" or t.kind == "api" or t.kind == "class" or t.kind == "function" or t.kind == "self" then
        local prev = sig[j - 1]
        if in_type then
          t.kind = "type"
        elseif depth == 1 and prev and (prev.text == "(" or prev.text == "," or prev.text == "*" or prev.text == "**") then
          t.kind = "parameter"
          t.decl = true
        end
      end
      j = j + 1
    end
    return n
  end

  for k = 1, n do
    local t = sig[k]
    local prev, nx = sig[k - 1], sig[k + 1]
    local text = t.text

    if t.kind == "punct" or t.kind == "operator" then
      if text == "(" or text == "[" or text == "{" then
        stack[#stack + 1] = text
      elseif text == ")" or text == "]" or text == "}" then
        stack[#stack] = nil
      end
    end

    if t.kind == "keyword" then
      if text == "import" then
        if import_state == "mod" and import_from then
          import_state = "names"
        else
          import_state = "mod"
          import_from = false
        end
      elseif text == "from" and first_on_line(k) or (text == "from" and prev and prev.text == "export") then
        import_state = "mod"
        import_from = true
      elseif text == "as" then
        t.alias_next = true
      end
      if text == "def" and nx and nx.kind == "name" then
        nx.kind = "function"
        nx.decl = true
        local open = sig[k + 2]
        if open and open.text == "(" then
          -- отмечаем параметры позже, когда счётчик скобок будет в порядке: сейчас отдельным проходом
          t.params_from = k + 2
        end
        -- '->' тип
      elseif text == "class" and nx and nx.kind == "name" then
        nx.kind = "class"
        nx.decl = true
      end
    elseif t.kind == "name" then
      local pk = prev
      if pk and pk.kind == "keyword" and pk.alias_next then
        t.kind = "namespace"
        t.decl = true
      elseif import_state then
        if import_state == "mod" then t.kind = "namespace" else t.kind = "variable"; t.decl = true end
      elseif pk and (pk.text == "." or pk.text == "?.") and pk.kind ~= "number" then
        t.kind = (nx and nx.text == "(") and "method" or "property"
      elseif pk and pk.text == ":" and adjacent(pk, t) and sig[k - 2] and adjacent(sig[k - 2], pk)
        and (sig[k - 2].kind == "name" or sig[k - 2].kind == "variable" or sig[k - 2].kind == "self"
          or sig[k - 2].text == ")" or sig[k - 2].text == "]" or sig[k - 2].kind == "property"
          or sig[k - 2].kind == "parameter" or sig[k - 2].kind == "builtin" or sig[k - 2].kind == "api")
        and nx and nx.text == "(" then
        t.kind = "method"
      elseif pk and pk.text == "@" and (first_on_line(k - 1)) then
        t.kind = "decorator"
      elseif pk and pk.text == "$" then
        t.kind = "namespace"
      elseif stack[#stack] == "{" and nx and nx.text == ":" and pk and (pk.text == "{" or pk.text == ",") then
        t.kind = "property"
      elseif stack[#stack] == "(" and nx and nx.text == "=" and pk and (pk.text == "(" or pk.text == ",") then
        t.kind = "parameter"
      elseif text == "self" then
        t.kind = "self"
      elseif text == "range" and nx and (nx.text == "[" or nx.text == "(") then
        t.kind = "builtin"
      elseif CUBIC_BUILTIN_SET[text] or (B.PROTECTED[text] and not (nx and nx.text == "=")) then
        t.kind = "builtin"
      elseif B.SHADOW_WARN[text] then
        t.kind = "api"
      elseif (text == "match" or text == "case") and first_on_line(k) and sig[#sig] and nx and nx.kind ~= "operator" and nx.text ~= "=" and nx.text ~= "." then
        -- последний значимый токен строки должен быть ':'
        local j = k
        while j < n and sig[j + 1].line == t.line do j = j + 1 end
        if sig[j].text == ":" then t.kind = "keyword"; t.group = "control" end
      elseif (text == "strict" or text == "loose") and first_on_line(k) and nx and nx.text == ":" and last_on_line(k + 1) then
        t.kind = "keyword"
        t.group = "declaration"
      elseif nx and nx.text == "(" then
        t.kind = text:match("^[A-Z]") and "class" or "function"
        t.call = true
      elseif text:match("^[A-Z][A-Z0-9_]*$") and #text > 1 then
        t.kind = "variable"
        t.mod = "constant"
      elseif text:match("^[A-Z]") then
        t.kind = "class"
      else
        t.kind = "variable"
      end
    end

    if t.kind == "punct" or t.kind == "operator" then
      if (text == "," or text == "." or text == "?.") and import_state then
        -- в import точки разделяют части пути
      end
      if text == "@" and first_on_line(k) then t.kind = "decorator" end
    end

    if last_on_line(k) then
      if import_state and not (sig[k].text == "," or sig[k].text == "(" ) then
        if not (stack[#stack] == "(") then import_state = nil end
      end
    end
  end

  -- параметры def отдельным проходом, чтобы не мешать счёту скобок
  for k = 1, n do
    if sig[k].params_from then
      mark_params(sig[k].params_from)
    end
  end
  -- возвращаемый тип: после '->' до ':'
  for k = 1, n do
    if sig[k].text == "->" then
      local j = k + 1
      local depth = 0
      while j <= n do
        local t = sig[j]
        if t.text == "(" or t.text == "[" or t.text == "{" then depth = depth + 1
        elseif t.text == ")" or t.text == "]" or t.text == "}" then depth = depth - 1
        elseif t.text == ":" and depth == 0 then break end
        if t.kind == "variable" or t.kind == "class" or t.kind == "name" or t.kind == "builtin" then t.kind = "type" end
        j = j + 1
      end
    end
  end
  return sig
end

-- Результат подсветки: список { kind, line, col, len, text, decl?, group?, mod?, open? }, плюс встроенные области
function T.highlight(src)
  local toks, embedded, lines = scan(src)
  refine(toks, src)
  local out = {}
  for _, t in ipairs(toks) do
    local item = { kind = t.kind, line = t.line, col = t.col, len = t.len, text = t.text }
    if t.decl then item.decl = true end
    if t.group then item.group = t.group end
    if t.mod then item.mod = t.mod end
    if t.open then item.open = true end
    if t.call then item.call = true end
    if t.interp then item.interp = true end
    out[#out + 1] = item
  end
  return out, embedded
end

---------------------------------------------------------------- символы

local function slice_tokens(sig, a, b, src)
  if a > b then return "" end
  return src:sub(sig[a].s, sig[b].e)
end

-- Структура файла. Работает по токенам, поэтому терпит ошибки в остальном коде.
function T.symbols(src)
  local toks, _, lines = scan(src)
  src = src:gsub("\r\n?", "\n")
  local sig = refine(toks, src)
  local n = #sig

  -- комментарии-описания над строкой
  local comment_by_line = {}
  local code_lines = {}
  for _, t in ipairs(toks) do
    if t.kind == "comment" then
      comment_by_line[t.line] = t.text
    elseif is_sig(t) then
      code_lines[t.line] = true
    end
  end
  local function doc_above(line)
    local out = {}
    local l = line - 1
    while l >= 1 and comment_by_line[l] and not code_lines[l] do
      out[#out + 1] = (comment_by_line[l]:gsub("^#%s?", ""))
      l = l - 1
    end
    if #out == 0 then return nil end
    local rev = {}
    for i = #out, 1, -1 do rev[#rev + 1] = out[i] end
    return table.concat(rev, "\n")
  end

  -- разбиение на инструкции
  local stmts = {}
  do
    local depth = 0
    local cur
    for k = 1, n do
      local t = sig[k]
      if not cur or (depth <= 0 and t.line ~= sig[k - 1].line and sig[k - 1].text ~= "\\") then
        cur = { from = k, line = t.line, indent = t.col - 1 }
        stmts[#stmts + 1] = cur
        depth = 0
      end
      cur.to = k
      if t.text == "(" or t.text == "[" or t.text == "{" then depth = depth + 1
      elseif t.text == ")" or t.text == "]" or t.text == "}" then depth = depth - 1 end
    end
  end

  local symbols = {}
  local container_stack = {}

  local function params_of(open, close)
    local params = {}
    local depth = 0
    local cur
    local j = open + 1
    local part_from
    local function finish(upto)
      if not part_from or upto < part_from then return end
      local kind = "param"
      local p = part_from
      if sig[p].text == "*" then kind = "rest"; p = p + 1
      elseif sig[p].text == "**" then kind = "kwrest"; p = p + 1 end
      if sig[p] and sig[p].kind == "parameter" then
        local entry = { name = sig[p].text, kind = kind }
        local q = p + 1
        if sig[q] and sig[q].text == ":" then
          local e = q + 1
          while e <= upto and sig[e].text ~= "=" do e = e + 1 end
          entry.type = slice_tokens(sig, q + 1, e - 1, src)
          q = e
        end
        if sig[q] and sig[q].text == "=" then
          entry.default = slice_tokens(sig, q + 1, upto, src)
          entry.optional = true
        end
        params[#params + 1] = entry
      end
    end
    while j < close do
      local t = sig[j]
      if t.text == "(" or t.text == "[" or t.text == "{" then depth = depth + 1
      elseif t.text == ")" or t.text == "]" or t.text == "}" then depth = depth - 1 end
      if depth == 0 and t.text == "," then
        finish(j - 1)
        part_from = nil
      elseif not part_from then
        part_from = j
      end
      j = j + 1
    end
    finish(close - 1)
    return params
  end

  for si, st in ipairs(stmts) do
    while #container_stack > 0 and st.indent <= container_stack[#container_stack].indent do
      container_stack[#container_stack] = nil
    end
    local container = container_stack[#container_stack]
    local k = st.from
    local exported = false
    if sig[k].text == "export" then exported = true; k = k + 1 end
    local head = sig[k]
    if head then
      if head.text == "def" and sig[k + 1] and sig[k + 1].decl then
        local name_tok = sig[k + 1]
        local open = k + 2
        local close = open
        local params = {}
        if sig[open] and sig[open].text == "(" then
          local depth = 0
          close = open
          while close <= st.to do
            if sig[close].text == "(" then depth = depth + 1
            elseif sig[close].text == ")" then depth = depth - 1; if depth == 0 then break end end
            close = close + 1
          end
          params = params_of(open, close)
        end
        local ret
        if sig[close + 1] and sig[close + 1].text == "->" then
          local e = close + 2
          while e <= st.to and sig[e].text ~= ":" do e = e + 1 end
          if e > st.to or sig[e].text == ":" then ret = slice_tokens(sig, close + 2, e - 1, src) end
        end
        local pieces = {}
        for i, p in ipairs(params) do
          local s = (p.kind == "rest" and "*" or (p.kind == "kwrest" and "**" or "")) .. p.name
          if p.type then s = s .. ": " .. p.type end
          if p.default then s = s .. " = " .. p.default end
          pieces[i] = s
        end
        local sym = {
          name = name_tok.text, kind = (container and container.kind == "class") and "method" or "function",
          line = name_tok.line, col = name_tok.col, len = name_tok.len, exported = exported, indent = st.indent,
          params = params, returns = ret, doc = doc_above(st.line),
          detail = name_tok.text .. "(" .. table.concat(pieces, ", ") .. ")" .. (ret and (" -> " .. ret) or ""),
          container = container and container.name or nil, stmt = si,
        }
        symbols[#symbols + 1] = sym
        container_stack[#container_stack + 1] = { indent = st.indent, kind = "function", name = sym.name }
      elseif head.text == "class" and sig[k + 1] and sig[k + 1].decl then
        local name_tok = sig[k + 1]
        local base
        if sig[k + 2] and sig[k + 2].text == "(" then
          local e = k + 3
          while e <= st.to and sig[e].text ~= ")" do e = e + 1 end
          base = slice_tokens(sig, k + 3, e - 1, src)
        end
        local sym = {
          name = name_tok.text, kind = "class", line = name_tok.line, col = name_tok.col, len = name_tok.len,
          exported = exported, indent = st.indent, base = base, doc = doc_above(st.line),
          detail = "class " .. name_tok.text .. (base and ("(" .. base .. ")") or ""),
          container = container and container.name or nil, stmt = si,
        }
        symbols[#symbols + 1] = sym
        container_stack[#container_stack + 1] = { indent = st.indent, kind = "class", name = sym.name }
      elseif head.text == "import" then
        local parts = {}
        local j = k + 1
        while j <= st.to and sig[j].text ~= "as" do
          parts[#parts + 1] = sig[j].text
          j = j + 1
        end
        local path = table.concat(parts)
        local alias
        if sig[j] and sig[j].text == "as" and sig[j + 1] then alias = sig[j + 1].text end
        local name = alias or path:match("([^%.%/]+)$") or path
        symbols[#symbols + 1] = { name = name, kind = "import", line = head.line, col = head.col, len = head.len,
          module = path, exported = exported, indent = st.indent, detail = "import " .. path .. (alias and (" as " .. alias) or ""), stmt = si }
      elseif head.text == "from" then
        local parts = {}
        local j = k + 1
        while j <= st.to and sig[j].text ~= "import" do
          parts[#parts + 1] = sig[j].text
          j = j + 1
        end
        local module = table.concat(parts)
        local names = {}
        j = j + 1
        while j <= st.to do
          local t = sig[j]
          if t.kind == "variable" or t.kind == "namespace" or t.kind == "name" then
            if sig[j - 1].text == "as" then
              names[#names].alias = t.text
            elseif t.text ~= "as" then
              names[#names + 1] = { name = t.text }
            end
          end
          j = j + 1
        end
        for _, nm in ipairs(names) do
          symbols[#symbols + 1] = { name = nm.alias or nm.name, kind = "import", line = head.line, col = head.col, len = head.len,
            module = module, imported = nm.name, exported = exported, indent = st.indent,
            detail = "from " .. module .. " import " .. nm.name, stmt = si }
        end
      elseif (head.text == "let" or head.text == "const" or head.text == "override") and sig[k + 1] and sig[k + 1].kind ~= "keyword" then
        local nm = sig[k + 1]
        if not container or container.kind == "class" then
          symbols[#symbols + 1] = { name = nm.text, kind = (head.text == "const") and "constant" or "variable", line = nm.line, col = nm.col,
            len = nm.len, exported = exported, indent = st.indent, container = container and container.name or nil,
            doc = doc_above(st.line), detail = head.text .. " " .. nm.text, stmt = si }
        end
      elseif (head.kind == "variable" or head.kind == "class" or head.kind == "name") and sig[k + 1]
        and (sig[k + 1].text == "=" or sig[k + 1].text == ":") and (not container or container.kind == "class") then
        local is_assign = sig[k + 1].text == "="
        if not is_assign then
          -- аннотация name: type = ...
          for j = k + 2, st.to do if sig[j].text == "=" then is_assign = true break end end
        end
        if is_assign then
          symbols[#symbols + 1] = { name = head.text, kind = (head.mod == "constant") and "constant" or "variable", line = head.line, col = head.col,
            len = head.len, exported = exported, indent = st.indent, container = container and container.name or nil,
            doc = doc_above(st.line), detail = head.text, stmt = si }
        end
      elseif head.kind == "self" and sig[k + 1] and sig[k + 1].text == "." and sig[k + 2] and sig[k + 3] and sig[k + 3].text == "="
        and container and container.kind == "function" then
        local nm = sig[k + 2]
        local cls = container_stack[#container_stack - 1]
        if cls and cls.kind == "class" then
          local dup = false
          for _, s in ipairs(symbols) do
            if s.kind == "field" and s.container == cls.name and s.name == nm.text then dup = true end
          end
          if not dup then
            symbols[#symbols + 1] = { name = nm.text, kind = "field", line = nm.line, col = nm.col, len = nm.len,
              indent = st.indent, container = cls.name, detail = "self." .. nm.text, stmt = si }
          end
        end
      end
    end
  end

  -- конец области каждого символа
  for _, sym in ipairs(symbols) do
    if sym.kind == "function" or sym.kind == "method" or sym.kind == "class" then
      local last = stmts[sym.stmt].to
      local j = sym.stmt + 1
      while stmts[j] and stmts[j].indent > sym.indent do
        last = stmts[j].to
        j = j + 1
      end
      sym.end_line = sig[last].line
    else
      sym.end_line = sym.line
    end
    sym.stmt = nil
    sym.indent = nil
  end
  return symbols
end

---------------------------------------------------------------- проверка кода

local function run_checker(ast, file, opts, extra)
  local env = type_env(opts)
  local copts = setmetatable(extra, { __index = opts })
  if opts.loader then
    copts.module_types = modtypes.make_resolver(file, copts, env, {})
  end
  return pcall(checker.check, ast, file, env, false, copts)
end

local function line_span(lines, line)
  local text = lines[line] or ""
  local lead = #text:match("^ *")
  return lead + 1, #text + 1
end

-- Ошибки и предупреждения: { {severity = "error"|"warning", line, col, end_col, message} }
function T.diagnostics(src, file, opts)
  file = file or "?"
  opts = opts or {}
  local lines = split_lines((src:gsub("\r\n?", "\n")))
  local out = {}
  local function add(sev, line, col, end_col, msg)
    out[#out + 1] = { severity = sev, line = line, col = col, end_col = end_col, message = msg }
  end
  local ok, ast = pcall(parser.parse, src, file)
  if not ok then
    if type(ast) == "table" and ast.cubic then
      local c0, c1 = line_span(lines, ast.line or 1)
      local col = ast.col or c0
      add("error", ast.line or 1, col, math.max(c1, col + 1), ast.msg)
    else
      add("error", 1, 1, 2, "internal parser error: " .. tostring(ast))
    end
    return out
  end
  if checker.needs_check(ast, opts) then
    local collected = {}
    local cok, cerr = run_checker(ast, file, opts, { collect = collected })
    if not cok then
      if type(cerr) == "table" and cerr.cubic then
        local c0, c1 = line_span(lines, cerr.line or 1)
        add("error", cerr.line or 1, cerr.col or c0, c1, cerr.msg)
      else
        add("error", 1, 1, 2, "internal checker error: " .. tostring(cerr))
      end
    end
    for _, e in ipairs(collected) do
      local c0, c1 = line_span(lines, e.line)
      add("error", e.line, c0, c1, e.msg)
    end
  end
  local gok, _, _, warnings = pcall(codegen.generate, ast, file, { version = ctx.version, banner = false })
  if gok and warnings then
    for _, w in ipairs(warnings) do
      local line, msg = w:match("^.-:(%d+): warning: (.*)$")
      if line then
        line = tonumber(line)
        local c0, c1 = line_span(lines, line)
        add("warning", line, c0, c1, msg)
      end
    end
  end
  table.sort(out, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return a.col < b.col
  end)
  return out
end

---------------------------------------------------------------- зондирование типов

-- Выполняет проверку урезанной копии файла со служебным вызовом __cubic_probe(выражение) и возвращает
-- { type = тип, vars = видимые имена, genv = окружение } либо nil, ошибка
local HEADER_START = U.set({ "if", "elif", "else", "while", "for", "def", "class", "try", "except", "finally", "with", "lua" })

local function probe(lines, after_line, indent, expr, file, opts)
  local keep = {}
  for i = 1, math.min(after_line, #lines) do keep[i] = lines[i] end
  keep[#keep + 1] = string.rep(" ", indent) .. "__cubic_probe(" .. expr .. ")"
  local src = table.concat(keep, "\n") .. "\n"
  local pok, ast = pcall(parser.parse, src, file)
  if not pok then
    return nil, (type(ast) == "table" and ast.msg) or tostring(ast)
  end
  local result
  local extra = {
    strict = true,
    collect = {},
    probe = function(t, vars, genv) result = { type = t, vars = vars, genv = genv } end,
  }
  run_checker(ast, file, opts, extra)
  if not result then return nil, "no type information at this position" end
  return result
end

-- Выражение-цепочка, оканчивающаяся перед позицией pos (индекс последнего символа цепочки)
local function chain_before(text, last)
  local i = last
  while i >= 1 do
    local c = text:sub(i, i)
    if c:match("[%w_]") then
      i = i - 1
    elseif c == "." or c == ":" then
      if i > 1 and text:sub(i - 1, i - 1) == "?" then i = i - 1 end
      i = i - 1
    elseif c == ")" or c == "]" or c == "}" then
      local open = ({ [")"] = "(", ["]"] = "[", ["}"] = "{" })[c]
      local depth = 0
      local j = i
      while j >= 1 do
        local d = text:sub(j, j)
        if d == c then depth = depth + 1
        elseif d == open then
          depth = depth - 1
          if depth == 0 then break end
        end
        j = j - 1
      end
      if j < 1 then return nil end
      i = j - 1
    elseif c == '"' or c == "'" then
      local j = text:sub(1, i - 1):find(c .. "[^" .. c .. "]*$")
      if not j then return nil end
      i = j - 1
    else
      break
    end
  end
  local chain = text:sub(i + 1, last)
  chain = chain:gsub("^[%.:]+", "")
  return chain, i + 1
end

local function indent_of(line)
  return #(line:match("^ *") or "")
end

local function first_word(line)
  return line:match("^%s*([%a_][%w_]*)")
end

local FN_KIND = { fn = "function", classobj = "class", ns = "module" }

local function kind_of_type(t)
  return FN_KIND[t.k] or "variable"
end

local function fn_snippet(name, fn, skip_first)
  if not fn or fn.loose then return nil end
  local parts = {}
  local idx = 0
  for i, p in ipairs(fn.params) do
    if not (skip_first and i == 1) and not p.optional then
      idx = idx + 1
      parts[#parts + 1] = "${" .. idx .. ":" .. p.name .. "}"
    end
  end
  return name .. "(" .. table.concat(parts, ", ") .. ")"
end

local function fn_params(fn, skip_first)
  local out = {}
  for i, p in ipairs(fn.params) do
    if not (skip_first and i == 1) then
      out[#out + 1] = { name = p.name, type = checker.tostr_type(p.type), optional = p.optional or false }
    end
  end
  if fn.rest then out[#out + 1] = { name = "...", type = checker.tostr_type(fn.rest), optional = true, rest = true } end
  return out
end

local function fn_label(name, fn, skip_first)
  local pieces = {}
  for i, p in ipairs(fn.params) do
    if not (skip_first and i == 1) then
      pieces[#pieces + 1] = p.name .. ": " .. checker.tostr_type(p.type) .. (p.optional and " = ..." or "")
    end
  end
  if fn.rest then pieces[#pieces + 1] = "*" .. checker.tostr_type(fn.rest) end
  return name .. "(" .. table.concat(pieces, ", ") .. ") -> " .. checker.tostr_type(fn.ret)
end

---------------------------------------------------------------- автодополнение

local function token_at(tokens, line, col)
  for _, t in ipairs(tokens) do
    if t.line == line and t.col < col and col <= t.col + t.len then return t end
  end
  return nil
end

local function starts_with(s, prefix)
  return prefix == "" or s:sub(1, #prefix):lower() == prefix:lower()
end

local EXPR_KEYWORDS = { "and", "or", "not", "is", "in", "if", "else", "for", "lua" }

-- Автодополнение. Возвращает { context, prefix, replace = {line, col, end_col}, items = { {label, kind, detail, insert, snippet, doc, sort} } }
function T.complete(src, line, col, opts)
  opts = opts or {}
  local file = opts.file or "?"
  src = src:gsub("\r\n?", "\n")
  local lines = split_lines(src)
  local cur = lines[line] or ""
  local prefix = cur:sub(1, col - 1)
  local result = { context = "none", prefix = "", replace = { line = line, col = col, end_col = col }, items = {} }

  local tokens = T.highlight(src)
  local inside = token_at(tokens, line, col)
  if inside then
    local k = inside.kind
    if (k == "comment" or k == "luacode" or k == "directive") or ((k == "string" or k == "escape") and (inside.open or col < inside.col + inside.len)) then
      result.context = (k == "luacode") and "lua" or "string"
      return result
    end
  end

  local function finish(items, ctxname, word)
    result.context = ctxname
    result.prefix = word or ""
    result.replace = { line = line, col = col - #(word or ""), end_col = col }
    local kept = {}
    for _, it in ipairs(items) do
      if starts_with(it.label, word or "") then kept[#kept + 1] = it end
    end
    table.sort(kept, function(a, b)
      if (a.sort or 5) ~= (b.sort or 5) then return (a.sort or 5) < (b.sort or 5) end
      return a.label < b.label
    end)
    result.items = kept
    return result
  end

  -- import / from
  local import_word = prefix:match("^%s*import%s+([%w_%./$]*)$") or prefix:match("^%s*export%s+import%s+([%w_%./$]*)$")
  local from_word = prefix:match("^%s*from%s+([%w_%./$]*)$")
  local mod_word = import_word or from_word
  if mod_word then
    local items = {}
    local names = opts.modules
    if not names and opts.loader and opts.loader.list then names = opts.loader.list() end
    for _, m in ipairs(names or {}) do
      items[#items + 1] = { label = m, kind = "module", sort = 1 }
    end
    return finish(items, "import", mod_word)
  end

  -- from X import <имя>
  local from_mod, from_names_word = prefix:match("^%s*from%s+([%w_%./$]+)%s+import%s+.-([%w_]*)$")
  if from_mod then
    local probe_line = "import " .. from_mod .. " as __cubic_m"
    local copy = {}
    for i = 1, line - 1 do copy[i] = lines[i] end
    copy[#copy + 1] = probe_line
    local res = probe(copy, #copy, 0, "__cubic_m", file, opts)
    local items = {}
    if res then
      for _, m in ipairs(checker.members_of(res.type, res.genv, ".")) do
        items[#items + 1] = { label = m.name, kind = m.kind, detail = m.type, sort = 1 }
      end
    end
    return finish(items, "import_names", from_names_word)
  end

  -- член: выражение . имя или выражение : имя
  local before_word, word = prefix:match("^(.-)([%w_]*)$")
  local acc = before_word:sub(-1)
  local optional_acc = false
  if acc == "." and before_word:sub(-2, -2) == "?" then optional_acc = true end
  if acc == "." or acc == ":" then
    local head = first_word(cur)
    local block_colon = acc == ":" and HEADER_START[head or ""] and word == ""
    local chain = (not block_colon) and chain_before(before_word, #before_word - 1 - (optional_acc and 1 or 0)) or nil
    if chain and chain ~= "" and chain:match("^[%a_%)%]]") or (chain and chain:match("^[%(%[\"']")) then
      local indent = indent_of(cur)
      local res, perr = probe(lines, line - 1, indent, chain, file, opts)
      local items = {}
      if res then
        for _, m in ipairs(checker.members_of(res.type, res.genv, acc)) do
          local skip_first = (acc == ":" and res.type.k ~= "inst" and res.type.k ~= "classobj")
          local it = { label = m.name, kind = m.kind, detail = m.type, sort = 1 }
          if m.fn then
            it.snippet = fn_snippet(m.name, m.fn, skip_first)
            it.detail = fn_label(m.name, m.fn, skip_first)
          end
          items[#items + 1] = it
        end
      else
        result.error = perr
      end
      -- запасной вариант: поля self.x из структуры файла
      if #items == 0 and chain == "self" then
        for _, s in ipairs(T.symbols(src)) do
          if s.container and (s.kind == "field" or s.kind == "method") then
            items[#items + 1] = { label = s.name, kind = s.kind, detail = s.detail, sort = 2 }
          end
        end
      end
      return finish(items, "member", word)
    end
    if acc == "." and chain == nil then
      return result
    end
  end

  -- после def/class имя новое, подсказывать нечего
  if before_word:match("%f[%w_]def%s+$") or before_word:match("%f[%w_]class%s+$") then
    return result
  end

  -- имена
  local items = {}
  local seen = {}
  local function add(it)
    if not seen[it.label] then
      seen[it.label] = true
      items[#items + 1] = it
    end
  end

  local res = probe(lines, line - 1, indent_of(cur), "nil", file, opts)
  if res then
    for name, ty in pairs(res.vars) do
      if name:sub(1, 2) ~= "__" then
        local it = { label = name, kind = kind_of_type(ty), detail = checker.tostr_type(ty), sort = 1 }
        if ty.k == "fn" then it.snippet = fn_snippet(name, ty, false) end
        add(it)
      end
    end
    local globals = res.genv.vars
    for name, ty in pairs(globals) do
      if name:sub(1, 2) ~= "__" then
        local it = { label = name, kind = kind_of_type(ty), detail = checker.tostr_type(ty), sort = 3 }
        if ty.k == "fn" then it.snippet = fn_snippet(name, ty, false) end
        add(it)
      end
    end
  else
    -- запасной вариант: символы файла
    for _, s in ipairs(T.symbols(src)) do
      if not s.container then add({ label = s.name, kind = s.kind, detail = s.detail, sort = 1 }) end
    end
    local ok, env = pcall(type_env, opts)
    if ok then
      for name, ty in pairs(env.vars) do add({ label = name, kind = kind_of_type(ty), detail = checker.tostr_type(ty), sort = 3 }) end
    end
  end
  for _, name in ipairs(CUBIC_BUILTINS) do add({ label = name, kind = "function", detail = "builtin", sort = 3 }) end
  for _, name in ipairs(lua_core_names()) do add({ label = name, kind = "function", detail = "Lua", sort = 4 }) end
  local stmt_start = before_word:match("^%s*$") ~= nil
  if stmt_start then
    for group, list in pairs(KEYWORD_GROUPS) do
      for _, k in ipairs(list) do add({ label = k, kind = "keyword", sort = 6 }) end
    end
    for _, k in ipairs(CONSTANTS) do add({ label = k, kind = "constant", sort = 6 }) end
    for _, sn in ipairs(SNIPPETS) do
      items[#items + 1] = { label = sn.prefix, kind = "snippet", detail = sn.label, doc = sn.doc, snippet = sn.body, sort = 7 }
    end
  else
    for _, k in ipairs(EXPR_KEYWORDS) do add({ label = k, kind = "keyword", sort = 6 }) end
    for _, k in ipairs(CONSTANTS) do add({ label = k, kind = "constant", sort = 6 }) end
  end
  return finish(items, "name", word)
end

---------------------------------------------------------------- подсказка параметров

-- Для вызова под курсором: { signatures = { {label, params = {{name, type, optional}}} }, active = номер аргумента (с 1) }
function T.signature(src, line, col, opts)
  opts = opts or {}
  local file = opts.file or "?"
  src = src:gsub("\r\n?", "\n")
  local lines = split_lines(src)
  local tokens = T.highlight(src)
  -- ищем незакрытую '(' перед курсором
  local stack = {}
  for _, t in ipairs(tokens) do
    if t.line > line or (t.line == line and t.col >= col) then break end
    if t.kind == "punct" then
      if t.text == "(" or t.text == "[" or t.text == "{" then
        stack[#stack + 1] = { t = t, commas = 0, name_arg = nil }
      elseif t.text == ")" or t.text == "]" or t.text == "}" then
        stack[#stack] = nil
      elseif t.text == "," and #stack > 0 then
        stack[#stack].commas = stack[#stack].commas + 1
      end
    end
  end
  local top = stack[#stack]
  if not top or top.t.text ~= "(" then return nil end
  local open = top.t
  local text = lines[open.line] or ""
  local chain, chain_start = chain_before(text, open.col - 1)
  if not chain or chain == "" then return nil end
  local acc = chain:match("[%.:]([%w_]*)$") and chain:match("([%.:])[%w_]*$") or nil
  local obj_expr, member = chain, nil
  if acc then
    obj_expr, member = chain:match("^(.*)[%.:]([%w_]*)$")
  end
  local res = probe(lines, open.line - 1, indent_of(text), obj_expr, file, opts)
  if not res then return nil end
  local label, params
  local t = res.type
  if member then
    local found
    for _, m in ipairs(checker.members_of(t, res.genv, ".")) do
      if m.name == member then found = m break end
    end
    if not found or not found.fn then return nil end
    local skip = (acc == ":" and t.k ~= "inst" and t.k ~= "classobj")
    label = fn_label(member, found.fn, skip)
    params = fn_params(found.fn, skip)
  elseif t.k == "fn" then
    label = fn_label(chain, t, false)
    params = fn_params(t, false)
  elseif t.k == "classobj" then
    local members = checker.members_of(t, res.genv, ".")
    local init
    for _, m in ipairs(members) do if m.name == "init" then init = m end end
    if init and init.fn then
      label = fn_label(chain, init.fn, false)
      params = fn_params(init.fn, false)
    else
      label = chain .. "()"
      params = {}
    end
  else
    return nil
  end
  -- в Lua-вызове obj:method(...) первая позиция это self
  return { signatures = { { label = label, params = params } }, active = top.commas + 1 }
end

---------------------------------------------------------------- подсказка по наведению

local function stmt_end(tokens, line)
  local depth = 0
  local end_line = line
  for _, t in ipairs(tokens) do
    if t.kind == "punct" or t.kind == "operator" then
      if t.line < line then
        if t.text == "(" or t.text == "[" or t.text == "{" then depth = depth + 1
        elseif t.text == ")" or t.text == "]" or t.text == "}" then depth = depth - 1 end
      end
    end
    if t.line >= line and t.kind ~= "comment" and t.kind ~= "directive" then
      if t.line > end_line and depth <= 0 then break end
      if t.text == "(" or t.text == "[" or t.text == "{" then depth = depth + 1
      elseif t.text == ")" or t.text == "]" or t.text == "}" then depth = depth - 1 end
      if t.line > end_line then end_line = t.line end
    end
  end
  return end_line
end

-- Тип и описание под курсором: { text = "...", range = {line, col, end_col}, type = "...", doc = "..." } или nil
function T.hover(src, line, col, opts)
  opts = opts or {}
  local file = opts.file or "?"
  src = src:gsub("\r\n?", "\n")
  local lines = split_lines(src)
  local tokens = T.highlight(src)
  local tok
  for _, t in ipairs(tokens) do
    if t.line == line and t.col <= col and col < t.col + t.len then tok = t break end
  end
  if not tok then return nil end
  local range = { line = line, col = tok.col, end_col = tok.col + tok.len }
  local k = tok.kind
  if k == "keyword" or k == "constant" then
    return { text = tok.text, kind = k, range = range }
  end
  if k == "number" then return { text = "num", type = "num", range = range } end
  if k ~= "variable" and k ~= "function" and k ~= "method" and k ~= "property" and k ~= "class" and k ~= "builtin"
    and k ~= "api" and k ~= "self" and k ~= "parameter" and k ~= "namespace" and k ~= "type" then
    return nil
  end
  local text = lines[line] or ""
  local chain = chain_before(text:sub(1, tok.col + tok.len - 1), tok.col + tok.len - 1)
  if not chain or chain == "" then return nil end
  local end_line = stmt_end(tokens, line)
  local last_text = lines[end_line] or ""
  local indent = indent_of(text)
  if last_text:match(":%s*$") or last_text:match(":%s*#.*$") then indent = indent_of(lines[line]) + 4 end
  local res = probe(lines, end_line, indent, chain, file, opts)
  local out = { range = range, kind = k }
  if res then
    out.type = checker.tostr_type(res.type)
    out.text = tok.text .. ": " .. out.type
  else
    out.text = tok.text
  end
  for _, s in ipairs(T.symbols(src)) do
    if s.name == tok.text and (s.kind == "function" or s.kind == "method" or s.kind == "class") then
      out.signature = s.detail
      out.doc = s.doc
      if not res then out.text = s.detail end
      break
    end
  end
  return out
end

return T
