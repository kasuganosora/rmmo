import re, io, sys

WORLD = "d:/code/rmmo/scripts/game/world.gd"
target = sys.argv[1]

wsrc = io.open(WORLD, "r", encoding="utf-8").read()
# ALL const declarations in world.gd (preload or plain value), keep source line
wconsts = {}
for m in re.finditer(r"^const\s+([A-Za-z_]\w*)\s*=\s*(.+)$", wsrc, re.M):
    wconsts[m.group(1)] = m.group(0)

tsrc = io.open(target, "r", encoding="utf-8").read()

# 1) add referenced-but-undeclared consts (plain values too, not just preload)
declared = set(re.findall(r"^const\s+([A-Za-z_]\w*)", tsrc, re.M))
need = [n for n in wconsts
        if n not in declared and re.search(r"(?<![\w.])%s(?![\w])" % n, tsrc)]

# 2) := -> =  (ctrl is untyped, so type inference is unreliable in moved code)
tsrc2 = re.sub(r"\bvar\s+([A-Za-z_]\w*)\s*:=", r"var \1 =", tsrc)

lines = tsrc2.split("\n")
if need:
    idx = next(i for i, ln in enumerate(lines) if ln.startswith("static func"))
    lines[idx:idx] = [wconsts[n] for n in need] + [""]

io.open(target, "w", encoding="utf-8").write("\n".join(lines))
print("FIXED", target)
print("  consts added:", need)
