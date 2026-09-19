import re, io, sys

ROOT = sys.argv[1]
target = sys.argv[2]

rlines = io.open(ROOT, "r", encoding="utf-8").read().split("\n")


def capture_consts(lines):
    """Capture const declarations, including multi-line arrays and `:=` forms."""
    out, i, n = {}, 0, len(lines)
    while i < n:
        m = re.match(r"^const\s+([A-Za-z_]\w*)", lines[i])
        if not m:
            i += 1
            continue
        name = m.group(1)
        buf = [lines[i]]
        depth = 0
        for ch in lines[i]:
            if ch in "[({":
                depth += 1
            elif ch in "])}":
                depth -= 1
        j = i + 1
        while depth > 0 and j < n:
            buf.append(lines[j])
            for ch in lines[j]:
                if ch in "[({":
                    depth += 1
                elif ch in "])}":
                    depth -= 1
            j += 1
        out[name] = "\n".join(buf)
        i = j
    return out


wconsts = capture_consts(rlines)
tsrc = io.open(target, "r", encoding="utf-8").read()

declared = set(re.findall(r"^const\s+([A-Za-z_]\w*)", tsrc, re.M))
# never inject a const that points back at the target itself (self preload cycle)
target_res = "res://" + target.replace("d:/code/rmmo/", "").replace("\\", "/")
need = [n for n in wconsts
        if n not in declared
        and target_res not in wconsts[n]
        and re.search(r"(?<![\w.])%s(?![\w])" % n, tsrc)]

# := inference is unreliable through untyped ctrl
tsrc2 = re.sub(r"\bvar\s+([A-Za-z_]\w*)\s*:=", r"var \1 =", tsrc)

lines = tsrc2.split("\n")
if need:
    idx = next(i for i, ln in enumerate(lines) if ln.startswith("static func"))
    lines[idx:idx] = [wconsts[n] for n in need] + [""]

io.open(target, "w", encoding="utf-8").write("\n".join(lines))
print("FIXED", target)
print("  consts added:", need)
