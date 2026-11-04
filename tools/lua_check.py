"""Structural Lua 5.1 check for machines without a Lua interpreter.

Catches the mistakes that most often break a mod at load time: unbalanced
function/if/for/while/do/repeat blocks, unbalanced brackets, unterminated strings
and comments, and Lua 5.2+ syntax (goto, ::labels::) that the game rejects.
It is not a full parser; luacheck in CI is the real gate.

Usage: python tools/lua_check.py <file-or-folder> [...]
Exit code 1 if any problem is found.
"""
import pathlib
import re
import sys

OPENERS = {"function", "if", "for", "while", "repeat"}
CLOSE_FOR = {"(": ")", "[": "]", "{": "}"}
LONG_BRACKET = re.compile(r"\[(=*)\[")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def check_source(text):
    problems = []
    blocks = []  # (keyword, line)
    brackets = []  # (char, line)
    pending_do = 0
    i, line, n = 0, 1, len(text)

    def skip_long(start, level, kind):
        nonlocal line
        closer = "]" + "=" * level + "]"
        end = text.find(closer, start)
        if end < 0:
            problems.append((line, "unterminated long " + kind))
            return n
        line += text.count("\n", start, end)
        return end + len(closer)

    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
        elif text.startswith("--", i):
            m = LONG_BRACKET.match(text, i + 2)
            if m:
                i = skip_long(m.end(), len(m.group(1)), "comment")
            else:
                end = text.find("\n", i)
                i = n if end < 0 else end
        elif c in "\"'":
            j = i + 1
            while j < n and text[j] != c:
                if text[j] == "\\":
                    j += 1
                elif text[j] == "\n":
                    break
                j += 1
            if j >= n or text[j] != c:
                problems.append((line, "unterminated string"))
            i = j + 1
        elif c == "[" and LONG_BRACKET.match(text, i):
            m = LONG_BRACKET.match(text, i)
            i = skip_long(m.end(), len(m.group(1)), "string")
        elif c in "([{":
            brackets.append((c, line))
            i += 1
        elif c in ")]}":
            if not brackets or CLOSE_FOR[brackets[-1][0]] != c:
                problems.append((line, "unexpected '%s'" % c))
            else:
                brackets.pop()
            i += 1
        elif c == ":" and text.startswith("::", i):
            problems.append((line, "'::label::' is Lua 5.2+ and fails in FS25"))
            end = text.find("::", i + 2)
            i = n if end < 0 else end + 2
        elif c.isalpha() or c == "_":
            m = IDENT.match(text, i)
            word = m.group(0)
            prev = text[i - 1] if i > 0 else ""
            i = m.end()
            if prev and prev in ".:":
                continue  # field or method name, not a keyword
            if word in OPENERS:
                blocks.append((word, line))
                if word in ("for", "while"):
                    pending_do += 1
            elif word == "do":
                if pending_do > 0:
                    pending_do -= 1
                else:
                    blocks.append(("do", line))
            elif word == "end":
                if not blocks or blocks[-1][0] == "repeat":
                    problems.append((line, "'end' without an open block"))
                else:
                    blocks.pop()
            elif word == "until":
                if not blocks or blocks[-1][0] != "repeat":
                    problems.append((line, "'until' without 'repeat'"))
                else:
                    blocks.pop()
            elif word == "goto":
                problems.append((line, "'goto' is Lua 5.2+ and fails in FS25"))
        else:
            i += 1

    for word, opened in blocks:
        problems.append((opened, "'%s' opened here is never closed" % word))
    for char, opened in brackets:
        problems.append((opened, "'%s' opened here is never closed" % char))
    return problems


def main(argv):
    targets = argv[1:] or ["mod"]
    files = []
    for target in targets:
        path = pathlib.Path(target)
        files.extend(sorted(path.rglob("*.lua")) if path.is_dir() else [path])
    failed = False
    for path in files:
        for line, message in check_source(path.read_text(encoding="utf-8")):
            print("%s:%d: %s" % (path, line, message))
            failed = True
    print("lua_check: %d file(s), %s" % (len(files), "problems found" if failed else "ok"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
