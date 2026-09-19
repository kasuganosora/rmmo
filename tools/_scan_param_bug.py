import re, glob, os

def params_of(sig):
    i = sig.index("(")
    depth, j = 0, i
    while j < len(sig):
        if sig[j] == "(": depth += 1
        elif sig[j] == ")":
            depth -= 1
            if depth == 0: break
        j += 1
    inner = sig[i+1:j]
    parts, d, cur = [], 0, ""
    for ch in inner:
        if ch == "(": d += 1
        elif ch == ")": d -= 1
        if ch == "," and d == 0:
            parts.append(cur); cur = ""
        else: cur += ch
    if cur.strip(): parts.append(cur)
    return [p.strip().split(":")[0].split("=")[0].strip() for p in parts if p.strip()]

def locals_of(body):
    loc = set()
    for ln in body:
        loc |= set(re.findall(r"\bvar\s+([A-Za-z_]\w*)", ln))
        loc |= set(re.findall(r"\bfor\s+([A-Za-z_]\w*)\s+in\b", ln))
        for m in re.findall(r"\bfunc\s*\(([^)]*)\)", ln):
            for p in m.split(","):
                pn = p.strip().split(":")[0].split("=")[0].strip()
                if re.match(r"^[A-Za-z_]\w*$", pn): loc.add(pn)
    return loc

total = 0
for f in sorted(glob.glob("scripts/ui/panels/*.gd")):
    lines = open(f, encoding="utf-8").read().split("\n")
    base = os.path.basename(f)
    idxs = [i for i, ln in enumerate(lines) if re.match(r"^func (\w+)\(", ln)]
    idxs.append(len(lines))
    for k in range(len(idxs)-1):
        i0 = idxs[k]
        name = re.match(r"^func (\w+)\(", lines[i0]).group(1)
        if name == "_init": continue
        sig = lines[i0]; kk = i0
        while not sig.rstrip().endswith(":") and kk+1 < idxs[k+1]:
            kk += 1; sig += " " + lines[kk].strip()
        body = lines[kk+1:idxs[k+1]]
        skip = set(params_of(sig)) | locals_of(body)
        for ln in body:
            code = re.sub(r'"[^"\n]*"', '""', ln).split("#")[0]
            for cm in re.findall(r"\bctrl\.(\w+)", code):
                if cm in skip:
                    print("%s  func %s  local '%s' wrongly -> ctrl.%s" % (base, name, cm, cm))
                    total += 1
print("LOCAL_SHADOW_BUGS:", total)
