import re
for f in ["achievement_catalog", "fish_catalog", "gather_catalog", "recipe_catalog", "title_catalog"]:
    p = "scripts/net/combat/%s.gd" % f
    src = open(p, encoding="utf-8").read()
    m = re.search(r'\.get\("(\w+)", \[\]\)', src)
    getters = re.findall(r"func ((?:get|has|register)_\w+)\(", src)
    print("%-22s key=%-14s paths=%s getters=%s" % (f, m.group(1) if m else "?", "DATA_PATHS" in src, getters))
