import re, glob, os, collections

# map func name -> list of files that DEFINE it (top-level `func name(`)
defs = collections.defaultdict(list)
for f in glob.glob("scripts/**/*.gd", recursive=True):
    path = f.replace("\\", "/")
    for ln in open(f, encoding="utf-8", errors="ignore").read().split("\n"):
        m = re.match(r"^func (\w+)\(", ln)
        if m:
            defs[m.group(1)].append(path)

dups = {n: fs for n, fs in defs.items() if len(fs) > 1}
# sort by count desc
for n, fs in sorted(dups.items(), key=lambda kv: -len(kv[1])):
    # ignore common lifecycle / very generic
    print("%-28s x%-2d %s" % (n, len(fs), ", ".join(os.path.basename(x) for x in fs[:6])))
print("\ntotal duplicate func names:", len(dups))
