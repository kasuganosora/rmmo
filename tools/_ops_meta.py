import re, json

src = open("scripts/editor/adapters/editor_mcp_ops.gd", encoding="utf-8").read()

# --- ops from the dispatch MATCH chain (authoritative) ---
disp = src[src.index("func dispatch("):]
arity = {}
for m in re.finditer(r'(?m)^\s*"(\w+)":\s*$\n\s*return (\w+)\((args)?\)', disp):
    arity[m.group(2)] = bool(m.group(3))

# --- metadata blocks from tools_list ---
tl = src[src.index("func tools_list("):src.index("func dispatch(")]
tll = tl.split("\n")
blocks = {}
i = 0
while i < len(tll):
    m = re.match(r'\s*mcp\._tool\("(\w+)"', tll[i])
    if m:
        name = m.group(1)
        buf = [tll[i].strip()]
        depth = tll[i].count("(") - tll[i].count(")")
        j = i + 1
        while depth > 0 and j < len(tll):
            buf.append(tll[j].strip())
            depth += tll[j].count("(") - tll[j].count(")")
            j += 1
        blocks[name] = "\n".join(buf)
        i = j
    else:
        i += 1

ops = sorted(arity.keys())
noarg = [o for o in ops if not arity[o]]
print("REAL ops in match chain:", len(ops))
print("no-arg ops (need signature fix):", noarg)
print("metadata blocks:", len(blocks))
print("ops missing metadata:", [o for o in ops if o not in blocks])
json.dump({"arity": arity, "blocks": blocks}, open("tools/_ops_meta.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
