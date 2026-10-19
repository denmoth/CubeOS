"""Крошечный читатель JSON5 для инструментов Cobble.

Поддерживает: комментарии // и /* */, запятую в конце, ключи без кавычек,
строки в двойных и одинарных кавычках, числа (в т.ч. hex), true/false/null.
Не поддерживает: Infinity/NaN, перенос строки через обратную косую в конце строки.
"""
import json
import re

_IDENT = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")
_NUM = re.compile(r"[+-]?(0[xX][0-9a-fA-F]+|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)")
_ESC = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v", "0": "\0"}


class Json5Error(ValueError):
    pass


class _P:
    def __init__(self, s):
        self.s = s
        self.i = 0

    def err(self, msg):
        line = self.s.count("\n", 0, self.i) + 1
        raise Json5Error("строка %d: %s" % (line, msg))

    def peek(self):
        return self.s[self.i:self.i + 1]

    def ws(self):
        s, n = self.s, len(self.s)
        while self.i < n:
            c = s[self.i]
            if c in " \t\r\n﻿":
                self.i += 1
            elif s.startswith("//", self.i):
                j = s.find("\n", self.i)
                self.i = n if j < 0 else j + 1
            elif s.startswith("/*", self.i):
                j = s.find("*/", self.i + 2)
                if j < 0:
                    self.err("не закрыт комментарий /*")
                self.i = j + 2
            else:
                break

    def value(self):
        self.ws()
        if self.i >= len(self.s):
            self.err("неожиданный конец файла")
        c = self.s[self.i]
        if c == "{":
            return self.obj()
        if c == "[":
            return self.arr()
        if c in "\"'":
            return self.string()
        m = _NUM.match(self.s, self.i)
        if m:
            self.i = m.end()
            t = m.group(0)
            if "x" in t.lower():
                return int(t, 16)
            return float(t) if re.search(r"[.eE]", t) else int(t)
        m = _IDENT.match(self.s, self.i)
        if m and m.group(0) in ("true", "false", "null"):
            self.i = m.end()
            return {"true": True, "false": False, "null": None}[m.group(0)]
        self.err("неожиданный символ %r" % c)

    def string(self):
        q = self.s[self.i]
        self.i += 1
        out = []
        s = self.s
        while True:
            if self.i >= len(s):
                self.err("не закрыта строка")
            c = s[self.i]
            if c == q:
                self.i += 1
                return "".join(out)
            if c == "\\":
                self.i += 1
                e = s[self.i:self.i + 1]
                if e == "u":
                    out.append(chr(int(s[self.i + 1:self.i + 5], 16)))
                    self.i += 5
                    continue
                out.append(_ESC.get(e, e))
                self.i += 1
                continue
            out.append(c)
            self.i += 1

    def key(self):
        self.ws()
        c = self.peek()
        if c and c in "\"'":
            return self.string()
        m = _IDENT.match(self.s, self.i)
        if not m:
            self.err("ожидался ключ")
        self.i = m.end()
        return m.group(0)

    def obj(self):
        self.i += 1
        res = {}
        while True:
            self.ws()
            if self.peek() == "}":
                self.i += 1
                return res
            k = self.key()
            self.ws()
            if self.peek() != ":":
                self.err("ожидалось ':' после ключа %r" % k)
            self.i += 1
            res[k] = self.value()
            self.ws()
            c = self.peek()
            if c == ",":
                self.i += 1
            elif c != "}":
                self.err("ожидалось ',' или '}'")

    def arr(self):
        self.i += 1
        res = []
        while True:
            self.ws()
            if self.peek() == "]":
                self.i += 1
                return res
            res.append(self.value())
            self.ws()
            c = self.peek()
            if c == ",":
                self.i += 1
            elif c != "]":
                self.err("ожидалось ',' или ']'")


def loads(text):
    p = _P(text)
    v = p.value()
    p.ws()
    if p.i != len(text):
        p.err("лишний текст после значения")
    return v


def load(path):
    with open(path, "r", encoding="utf-8") as f:
        try:
            return loads(f.read())
        except Json5Error as e:
            raise Json5Error("%s: %s" % (path, e))


def dumps(value):
    """Детерминированный вывод: ключи отсортированы, отступ 2 (это валидный JSON, а значит и JSON5)."""
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
