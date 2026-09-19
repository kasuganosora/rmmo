import re, io, glob

for p in sorted(glob.glob("d:/code/rmmo/scripts/ui/panels/*.gd")):
    s = io.open(p, "r", encoding="utf-8").read()
    self_res = "res://" + p.replace("d:/code/rmmo/", "").replace("\\", "/")
    # drop a const that preloads the module itself (self preload cycle)
    pat = r"^const\s+\w+\s*=\s*preload\(\"" + re.escape(self_res) + r"\"\)\s*\n"
    new = re.sub(pat, "", s, flags=re.M)
    if new != s:
        io.open(p, "w", encoding="utf-8").write(new)
        print("removed self-const in", p)
