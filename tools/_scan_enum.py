import re, glob, os, sys

FACADE = sys.argv[1] if len(sys.argv) > 1 else "scripts/editor/content_editor.gd"
MODULES = sys.argv[2] if len(sys.argv) > 2 else "scripts/editor/field/*.gd"

ce = open(FACADE, encoding="utf-8").read()
evals = set()
for eb in re.findall(r"enum\s+\w*\s*\{(.*?)\}", ce, re.S):
    for entry in eb.split(","):
        m = re.match(r"\s*([A-Za-z_]\w*)", entry)
        if m:
            evals.add(m.group(1))
print("enum values in facade:", len(evals))
bad = 0
for f in sorted(glob.glob(MODULES)):
    for i, ln in enumerate(open(f, encoding="utf-8").read().split("\n"), 1):
        code = re.sub(r'"[^"\n]*"', '""', ln).split("#")[0]
        for ev in evals:
            if re.search(r"(?<![\w.])%s(?![\w])" % re.escape(ev), code):
                print("BARE %s:%d %s -> %s" % (os.path.basename(f), i, ev, ln.strip()[:60]))
                bad += 1
print("BARE_ENUM_USAGES:", bad)
