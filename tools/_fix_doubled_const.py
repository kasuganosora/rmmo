import re, io, glob

# collapse `const X = const X = VALUE` (from a double-insertion bug) back to `const X = VALUE`
pat = re.compile(r"^const\s+([A-Za-z_]\w*)\s*=\s*const\s+\1\s*=\s*", re.M)

for p in sorted(glob.glob("d:/code/rmmo/scripts/ui/panels/*.gd")):
    s = io.open(p, "r", encoding="utf-8").read()
    new, n = pat.subn(r"const \1 = ", s)
    if n:
        io.open(p, "w", encoding="utf-8").write(new)
        print("fixed %d doubled const(s) in %s" % (n, p))
