"""Readers for the two data sources. Both are parsed as plain data, never executed.

* QuestieDB (Forever): Lua table literals inside `[[return { ... }]]` long strings.
* CMaNGOS classic-db: a MySQL dump with extended INSERT statements.
"""
import re


# ---------------------------------------------------------------------------
# Lua table literal parser (just the subset QuestieDB's data files use)
# ---------------------------------------------------------------------------

class LuaParser:
    _num = re.compile(r"-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?)")
    _name = re.compile(r"[A-Za-z_][A-Za-z_0-9]*")
    _ws = re.compile(r"(?:\s+|--\[\[.*?\]\]|--[^\n]*)+", re.S)

    def __init__(self, text):
        self.s = text
        self.i = 0

    def ws(self):
        m = self._ws.match(self.s, self.i)
        if m:
            self.i = m.end()

    def value(self):
        self.ws()
        c = self.s[self.i]
        if c == "{":
            return self.table()
        if c in "'\"":
            return self.string(c)
        if c == "[" and self.s.startswith("[[", self.i):
            end = self.s.index("]]", self.i + 2)
            v = self.s[self.i + 2:end]
            self.i = end + 2
            return v
        m = self._num.match(self.s, self.i)
        if m:
            self.i = m.end()
            t = m.group(0)
            if t.lower().startswith(("0x", "-0x")):
                return int(t, 16)
            f = float(t)
            return int(f) if f.is_integer() and "." not in t and "e" not in t.lower() else f
        m = self._name.match(self.s, self.i)
        if m:
            self.i = m.end()
            word = m.group(0)
            if word == "nil":
                return None
            if word == "true":
                return True
            if word == "false":
                return False
            raise ValueError("unexpected name %r at %d" % (word, self.i))
        raise ValueError("unexpected %r at %d" % (c, self.i))

    def string(self, q):
        out = []
        i = self.i + 1
        s = self.s
        while True:
            c = s[i]
            if c == q:
                break
            if c == "\\":
                n = s[i + 1]
                if n.isdigit():
                    m = re.match(r"\d{1,3}", s[i + 1:])
                    out.append(chr(int(m.group(0))))
                    i += 1 + len(m.group(0))
                    continue
                out.append({"n": "\n", "t": "\t", "r": "\r"}.get(n, n))
                i += 2
                continue
            out.append(c)
            i += 1
        self.i = i + 1
        return "".join(out)

    def table(self):
        """Returns a dict {key: value}; array items get keys 1..n."""
        self.i += 1
        result = {}
        n = 0
        while True:
            self.ws()
            c = self.s[self.i]
            if c == "}":
                self.i += 1
                return result
            if c == "[" and not self.s.startswith("[[", self.i):
                self.i += 1
                key = self.value()
                self.ws()
                assert self.s[self.i] == "]", self.i
                self.i += 1
                self.ws()
                assert self.s[self.i] == "=", self.i
                self.i += 1
                result[key] = self.value()
            else:
                m = self._name.match(self.s, self.i)
                save = self.i
                if m and m.group(0) not in ("nil", "true", "false"):
                    self.i = m.end()
                    self.ws()
                    if self.s[self.i] == "=":
                        self.i += 1
                        result[m.group(0)] = self.value()
                    else:
                        self.i = save
                        n += 1
                        result[n] = self.value()
                else:
                    n += 1
                    result[n] = self.value()
            self.ws()
            if self.s[self.i] in ",;":
                self.i += 1


def lua_list(t):
    """A parsed Lua array (dict 1..n, possibly with holes) as a Python list with None holes."""
    if not isinstance(t, dict):
        return t
    if not t:
        return []
    n = max(k for k in t if isinstance(k, int)) if any(isinstance(k, int) for k in t) else 0
    return [t.get(i) for i in range(1, n + 1)]


def read_questie_table(path, var):
    """Parses `QuestieDB.<var> = [[return { ... }]]` from a QuestieDB data file."""
    text = open(path, encoding="utf-8").read()
    m = re.search(re.escape(var) + r"\s*=\s*\[\[\s*return\s*", text)
    if not m:
        raise ValueError("%s not found in %s" % (var, path))
    p = LuaParser(text)
    p.i = m.end()
    return p.value()


def read_lua_assignment(path, pattern):
    """Parses the table literal that follows `pattern` (a regex) in a Lua support file."""
    text = open(path, encoding="utf-8").read()
    m = re.search(pattern, text)
    if not m:
        raise ValueError("%s not found in %s" % (pattern, path))
    p = LuaParser(text)
    p.i = m.end()
    return p.value()


# ---------------------------------------------------------------------------
# MySQL dump reader
# ---------------------------------------------------------------------------

_tuple_tok = re.compile(r"""\s*(?:'((?:[^'\\]|\\.|'')*)'|(NULL)|(-?[0-9.eE+-]+))\s*([,)])""", re.S)


def _unescape(s):
    return re.sub(r"\\(.)|''", lambda m: {"n": "\n", "r": "\r", "t": "\t", "0": "\0"}.get(m.group(1), m.group(1) or "'"), s)


def sql_columns(sql, table):
    m = re.search(r"CREATE TABLE `%s` \((.*?)\n\)" % re.escape(table), sql, re.S)
    return re.findall(r"^\s*`([^`]+)`", m.group(1), re.M)


def sql_rows(sql, table):
    """Yields every row of `table` as a dict {column: value}."""
    cols = sql_columns(sql, table)
    head = "INSERT INTO `%s` VALUES " % table
    pos = 0
    while True:
        start = sql.find(head, pos)
        if start < 0:
            return
        i = start + len(head)
        while True:
            while sql[i] in " \n\r\t,":
                i += 1
            if sql[i] == ";":
                break
            assert sql[i] == "(", (table, sql[i:i + 40])
            i += 1
            row = []
            while True:
                m = _tuple_tok.match(sql, i)
                if not m:
                    raise ValueError("bad row in %s near %r" % (table, sql[i:i + 80]))
                if m.group(1) is not None:
                    row.append(_unescape(m.group(1)))
                elif m.group(2):
                    row.append(None)
                else:
                    t = m.group(3)
                    row.append(float(t) if ("." in t or "e" in t.lower()) else int(t))
                i = m.end()
                if m.group(4) == ")":
                    break
            yield dict(zip(cols, row))
        pos = i
