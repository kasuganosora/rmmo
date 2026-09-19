import re, io, glob

WORLD = "d:/code/rmmo/scripts/game/world.gd"
wsrc = io.open(WORLD, "r", encoding="utf-8").read()

# world.gd: const Name = preload("res://...")  ->  reverse map path -> const name
wconsts = dict(re.findall(r'^const\s+(\w+)\s*=\s*preload\("([^"]+)"\)', wsrc, re.M))
path2const = {v: k for k, v in wconsts.items()}

apps = {}
for p in glob.glob("d:/code/rmmo/scripts/game/*/*.gd"):  # application/ + infrastructure/
    src = io.open(p, "r", encoding="utf-8").read()
    blocks, cur_name, cur = {}, None, []
    for ln in src.split("\n"):
        m = re.match(r"^static func (\w+)\(", ln)
        if m:
            if cur_name:
                blocks[cur_name] = "\n".join(cur)
            cur_name, cur = m.group(1), [ln]
        elif cur_name is not None:
            cur.append(ln)
    if cur_name:
        blocks[cur_name] = "\n".join(cur)
    cname = path2const.get("res://" + p.replace("d:/code/rmmo/", "").replace("\\", "/"))
    if cname:
        apps[cname] = (blocks, p)

print("mapped consts:", sorted(apps))


def returns_value(body):
    for ln in body.split("\n"):
        s = ln.strip()
        if s == "return" or s.startswith("return#"):
            continue
        if re.match(r"^return\s+\S", s):
            return True
    return False


bad, total = [], 0
for i, ln in enumerate(wsrc.split("\n")):
    m = re.match(r"^\t(?:return\s+)?(\w+)\.(\w+)\(self\b", ln)
    if not m:
        continue
    const, name = m.group(1), m.group(2)
    if const not in apps:
        continue
    blocks, path = apps[const]
    total += 1
    if name in blocks and returns_value(blocks[name]) and not ln.strip().startswith("return "):
        bad.append((const, name, "line %d" % (i + 1)))

print("delegates checked:", total)
print("MISSING return (would silently return null):")
for b in bad:
    print("  ", b)
if not bad:
    print("  (none)")
