-- Проверки данных для редакторов: подсветка, символы, диагностика, подсказки.
-- Called by tests/run.lua as: chunk(cubic, ROOT, record)
local cubic, ROOT, record = ...
local T = cubic.tooling

local function ok(name, cond, detail)
  record("tooling: " .. name, cond and true or false, tostring(detail or ""))
end

local function find(tokens, line, col)
  for _, t in ipairs(tokens) do
    if t.line == line and t.col == col then return t end
  end
  return nil
end

local function kinds(tokens, line)
  local out = {}
  for _, t in ipairs(tokens) do
    if t.line == line then out[#out + 1] = t.col .. ":" .. t.text .. "=" .. t.kind end
  end
  return table.concat(out, " ")
end

local function labels(items)
  local set = {}
  for _, it in ipairs(items) do set[it.label] = it end
  return set
end

local function kind_at(tokens, line, col)
  local t = find(tokens, line, col)
  return t and t.kind or "none"
end

-- язык и грамматика
local lang = T.language()
ok("language has keywords", lang.keywords.control[1] ~= nil and lang.extensions[1] == ".cub")
local tm = T.textmate()
ok("textmate grammar", tm.scopeName == "source.cubic" and tm.repository.keyword ~= nil)

-- подсветка
local src = table.concat({
  "#!strict",
  "# comment",
  "import std.str as s",
  "export def greet(name: str, n = 2) -> str:",
  "    msg = f\"hi {name:>5}\\n\"",
  "    return len(msg) + 0x1F",
  "class Box(Base):",
  "    def init(self):",
  "        self.v = nil",
  "        self:go()",
  "x = {a: 1}",
  "term.write(x.a)",
  "lua:",
  "    print(1)",
  "y = 2",
}, "\n")
local toks, embedded = T.highlight(src)
ok("directive", kind_at(toks, 1, 1) == "directive")
ok("comment", kind_at(toks, 2, 1) == "comment")
ok("import path", kind_at(toks, 3, 8) == "namespace", kinds(toks, 3))
ok("import alias", kind_at(toks, 3, 19) == "namespace", kinds(toks, 3))
ok("def name", kind_at(toks, 4, 12) == "function", kinds(toks, 4))
ok("param name", kind_at(toks, 4, 18) == "parameter", kinds(toks, 4))
ok("param type", kind_at(toks, 4, 24) == "type", kinds(toks, 4))
ok("return type", kind_at(toks, 4, 39) == "type", kinds(toks, 4))
ok("fstring interpolation", kind_at(toks, 5, 17) == "variable", kinds(toks, 5))
ok("format spec", kind_at(toks, 5, 21) == "string", kinds(toks, 5))
ok("escape", kind_at(toks, 5, 25) == "escape", kinds(toks, 5))
ok("builtin", kind_at(toks, 6, 12) == "builtin", kinds(toks, 6))
ok("hex number", kind_at(toks, 6, 23) == "number", kinds(toks, 6))
ok("class name", kind_at(toks, 7, 7) == "class", kinds(toks, 7))
ok("self", kind_at(toks, 9, 9) == "self", kinds(toks, 9))
ok("property", kind_at(toks, 9, 14) == "property", kinds(toks, 9))
ok("colon method", kind_at(toks, 10, 14) == "method", kinds(toks, 10))
ok("dict key", kind_at(toks, 11, 6) == "property", kinds(toks, 11))
ok("cc api", kind_at(toks, 12, 1) == "api", kinds(toks, 12))
ok("lua block code", kind_at(toks, 14, 5) == "luacode")
ok("after lua block", kind_at(toks, 15, 1) == "variable", kinds(toks, 15))
ok("embedded region", embedded[1] ~= nil and embedded[1].from_line == 14 and embedded[1].to_line == 14)

-- подсветка терпит ошибки
local bad = T.highlight("x = \"open\ny = $ ` 3")
ok("tolerates errors", #bad > 4)
local trip = T.highlight("s = \"\"\"a\nb\"\"\"\nz = 1")
ok("multiline string split", kind_at(trip, 1, 5) == "string" and kind_at(trip, 2, 1) == "string" and kind_at(trip, 3, 1) == "variable")

-- символы
local syms = T.symbols(table.concat({
  "import std.str as s",
  "from std.list import map, filter as f",
  "LIMIT = 10",
  "# складывает числа",
  "export def add(a: num, b: num = 1) -> num:",
  "    return a + b",
  "class Box(Base):",
  "    size = 3",
  "    def init(self, v):",
  "        self.v = v",
  "    def get(self):",
  "        return self.v",
  "def later():",
  "    pass",
}, "\n"))
local by = {}
for _, s in ipairs(syms) do by[(s.container and (s.container .. ".") or "") .. s.name] = s end
ok("sym import", by["s"] ~= nil and by["s"].kind == "import" and by["s"].module == "std.str")
ok("sym from import", by["map"] ~= nil and by["f"] ~= nil and by["f"].imported == "filter")
ok("sym constant", by["LIMIT"] ~= nil and by["LIMIT"].kind == "constant")
ok("sym function", by["add"] ~= nil and by["add"].kind == "function" and by["add"].exported and #by["add"].params == 2)
ok("sym detail", by["add"] ~= nil and by["add"].detail == "add(a: num, b: num = 1) -> num", by["add"] and by["add"].detail)
ok("sym doc", by["add"] ~= nil and by["add"].doc == "складывает числа", by["add"] and by["add"].doc)
ok("sym class", by["Box"] ~= nil and by["Box"].kind == "class" and by["Box"].base == "Base" and by["Box"].end_line == 12, by["Box"] and by["Box"].end_line)
ok("sym method", by["Box.get"] ~= nil and by["Box.get"].kind == "method")
ok("sym class field", by["Box.size"] ~= nil and by["Box.size"].kind == "variable")
ok("sym self field", by["Box.v"] ~= nil and by["Box.v"].kind == "field")
ok("sym function end", by["later"] ~= nil and by["later"].end_line == 14)

-- диагностика
local d1 = T.diagnostics("x = (1 +\n", "t.cub", {})
ok("syntax error", #d1 == 1 and d1[1].severity == "error" and d1[1].line >= 1, #d1)
local d2 = T.diagnostics("#!strict\nx: num = \"a\"\ny: str = 5\n", "t.cub", {})
ok("type errors collected", #d2 == 2 and d2[1].line == 2 and d2[2].line == 3, #d2)
local d3 = T.diagnostics("def f():\n    term = 1\n    return term\n", "t.cub", {})
ok("warning", #d3 == 1 and d3[1].severity == "warning", #d3)
ok("clean file", #T.diagnostics("x = 1\n", "t.cub", {}) == 0)

-- автодополнение
local code = table.concat({
  "class Box:",
  "    def init(self):",
  "        self.size = 3",
  "    def grow(self, by: num) -> num:",
  "        return self.size + by",
  "b = Box()",
  "m: str = \"abc\"",
  "total = 5",
  "",
}, "\n")
local function complete_with(extra, opts)
  return T.complete(code .. extra, 9, #extra + 1, opts or {})
end
local c1 = complete_with("b.")
ok("member context", c1.context == "member" and labels(c1.items).grow ~= nil and labels(c1.items).size ~= nil, c1.error)
ok("member detail", labels(c1.items).grow ~= nil and labels(c1.items).grow.detail == "grow(by: num) -> num", labels(c1.items).grow and labels(c1.items).grow.detail)
ok("member snippet", labels(c1.items).grow ~= nil and labels(c1.items).grow.snippet == "grow(${1:by})")
local c2 = complete_with("b:gr")
ok("colon method filtered", c2.context == "member" and #c2.items == 1 and c2.items[1].label == "grow" and c2.prefix == "gr", #c2.items)
ok("replace range", c2.replace.col == 3 and c2.replace.end_col == 5, c2.replace.col)
local c3 = complete_with("m:")
ok("string methods", #c3.items > 0, #c3.items)
local c4 = complete_with("to")
ok("name context", c4.context == "name" and labels(c4.items).total ~= nil and labels(c4.items).total.detail == "num", c4.error)
local c5 = complete_with("te")
ok("cc global", labels(c5.items).term ~= nil)
local c6 = complete_with("fo")
ok("keyword and snippet", labels(c6.items)["for"] ~= nil and labels(c6.items)["forr"] ~= nil)
local c7 = complete_with("x = \"b.")
ok("no completion in string", c7.context == "string" and #c7.items == 0)
local c8 = complete_with("# b.")
ok("no completion in comment", #c8.items == 0)
local c9 = complete_with("term.")
ok("namespace members", labels(c9.items).write ~= nil and labels(c9.items).setCursorPos ~= nil, #c9.items)

-- подсказка параметров
local sig = T.signature(code .. "b:grow(", 9, 9, {})
ok("signature", sig ~= nil and sig.signatures[1].label == "grow(by: num) -> num" and sig.active == 1, sig and sig.signatures[1].label)
local sig2 = T.signature(code .. "term.setCursorPos(1, ", 9, 22, {})
ok("signature second arg", sig2 ~= nil and sig2.active == 2 and sig2.signatures[1].params[2].name == "y", sig2 and sig2.active)
ok("no signature outside call", T.signature(code .. "b = 1", 9, 5, {}) == nil)

-- hover
local h1 = T.hover(code .. "q = total\n", 9, 6, {})
ok("hover type", h1 ~= nil and h1.type == "num", h1 and h1.text)
local h2 = T.hover(code .. "b.grow(1)\n", 9, 3, {})
ok("hover method", h2 ~= nil and h2.type ~= nil and h2.type:find("fn", 1, true) ~= nil, h2 and h2.text)

-- модули
local loader = cubic.new_loader({ roots = { ROOT .. "/lib" } })
local c11 = T.complete("import ba", 1, 10, { loader = loader })
ok("import completion", c11.context == "import" and labels(c11.items).base64 ~= nil and labels(c11.items)["std.str"] == nil, #c11.items)
local c12 = T.complete("import std.", 1, 12, { loader = loader })
ok("dotted import completion", labels(c12.items)["std.str"] ~= nil, #c12.items)
local c13 = T.complete("from base64 import ", 1, 20, { loader = loader, base_dir = ROOT })
ok("from import names", labels(c13.items).encode ~= nil and labels(c13.items).decode ~= nil, c13.context .. " " .. #c13.items)
