import re, glob, os, sys

FACADE = sys.argv[1] if len(sys.argv) > 1 else "scripts/net/mock_server.gd"
MODULES = sys.argv[2] if len(sys.argv) > 2 else "scripts/net/server/*.gd"

# facade members (vars/signals/funcs/consts) that could be shadowed
hud = open(FACADE, encoding="utf-8").read()
members = set(re.findall(r"(?m)^(?:@\w+(?:\([^\n]*\))?\s+)*var\s+(\w+)", hud))
members |= set(re.findall(r"(?m)^signal\s+(\w+)", hud))
members |= set(re.findall(r"(?m)^const\s+(\w+)", hud))

def indent(ln):
    return len(ln) - len(ln.lstrip("\t"))

hits = []
for f in sorted(glob.glob(MODULES)):
    lines = open(f, encoding="utf-8").read().split("\n")
    base = os.path.basename(f)
    idxs = [i for i, ln in enumerate(lines) if re.match(r"^func (\w+)\(", ln)] + [len(lines)]
    for k in range(len(idxs)-1):
        i0 = idxs[k]
        name = re.match(r"^func (\w+)\(", lines[i0]).group(1)
        if name == "_init": continue
        # method body range; find block-scoped var/for locals that shadow a member
        body = lines[i0:idxs[k+1]]
        # collect (name, decl_line, decl_indent) for var/for locals
        locals_ = []
        for j, ln in enumerate(body):
            for m in re.findall(r"\bvar\s+([A-Za-z_]\w*)", ln):
                locals_.append((m, j, indent(ln)))
            for m in re.findall(r"\bfor\s+([A-Za-z_]\w*)\s+in\b", ln):
                locals_.append((m, j, indent(ln)))
        shadowed = {n for n, _, _ in locals_ if n in members}
        if not shadowed:
            continue
        # for each bare usage of a shadowed name, flag if it is NOT clearly the local
        for n in shadowed:
            # declaration line/indent (first)
            dl, di = next((j, ind) for nm, j, ind in locals_ if nm == n)
            for j, ln in enumerate(body):
                code = re.sub(r'"[^"\n]*"', '""', ln).split("#")[0]
                if not re.search(r"(?<![\w.])%s(?![\w])" % re.escape(n), code):
                    continue
                if "ctrl." + n in code:
                    continue
                # skip the declaration line itself and usages at deeper indent after decl
                if j >= dl and indent(ln) >= di:
                    continue  # likely the local (in scope)
                hits.append("%s  func %s  bare member '%s' at body-line %d: %s" % (base, name, n, j, ln.strip()))

print("SHADOW_SUSPECTS:", len(hits))
for h in hits:
    print("  " + h)
