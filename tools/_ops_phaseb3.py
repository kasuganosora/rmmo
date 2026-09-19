import re

SRC = "scripts/editor/adapters/editor_mcp_ops.gd"
lines = open(SRC, encoding="utf-8").read().split("\n")

def find(pred, start=0):
    for i in range(start, len(lines)):
        if pred(lines[i]):
            return i
    return -1

idx_tl = find(lambda l: l.startswith("func tools_list("))
idx_disp = find(lambda l: l.startswith("func dispatch("))
idx_ed = find(lambda l: l.startswith("func ed("))
assert idx_tl != -1 and idx_disp != -1 and idx_ed != -1, (idx_tl, idx_disp, idx_ed)

# --- new tools_list (registry aggregate) ---
new_tl = [
 "func tools_list() -> Array:",
 "\tif _op_modules.is_empty():",
 "\t\t_build_op_registry()",
 "\tvar out: Array = []",
 "\tfor m in _op_modules:",
 "\t\tout.append_array(m.tools())",
 "\treturn out",
 "",
]

# --- new dispatch (registry lookup) + registry state + builder ---
new_disp = [
 "var _op_modules: Array = []",
 "var _op_registry: Dictionary = {}",
 "",
 "func _build_op_registry() -> void:",
 "\tif _op_modules.is_empty():",
 "\t\t_op_modules = [",
 "\t\t\t_inspect_ops_logic, _map_settings_ops_logic, _paint_ops_logic,",
 "\t\t\t_tiles_ops_logic, _stamp_ops_logic, _map_crud_ops_logic,",
 "\t\t\t_history_ops_logic, _asset_ops_logic, _entity_ops_logic,",
 "\t\t]",
 "\t_op_registry = {}",
 "\tfor m in _op_modules:",
 "\t\tfor op in m.op_names():",
 "\t\t\t_op_registry[op] = m",
 "",
 "func dispatch(name: String, args: Dictionary) -> Dictionary:",
 "\tif _op_registry.is_empty():",
 "\t\t_build_op_registry()",
 "\tvar m: RefCounted = _op_registry.get(name)",
 "\tif m == null:",
 "\t\treturn {\"ok\": false, \"error\": \"unknown tool: %s\" % name}",
 "\treturn m.call(name, args)",
 "",
]

# splice: [0, idx_tl) + new_tl + new_disp + [idx_ed:]
out = lines[:idx_tl] + new_tl + new_disp + lines[idx_ed:]

# --- remove op delegations: func op(...): <1-line body `return _mod.op(...)`) ---
res = []
i = 0
removed = 0
while i < len(out):
    m = re.match(r"^func (\w+)\(", out[i])
    if m and i + 1 < len(out):
        name = m.group(1)
        body = out[i + 1].strip()
        if re.match(r"^return _\w+_ops_logic\.%s\(" % re.escape(name), body):
            i += 2  # skip sig + body
            removed += 1
            continue
    res.append(out[i])
    i += 1

# collapse 3+ blank lines to 1
final = []
blank = 0
for ln in res:
    if ln.strip() == "":
        blank += 1
        if blank <= 1:
            final.append(ln)
    else:
        blank = 0
        final.append(ln)

open(SRC, "w", encoding="utf-8").write("\n".join(final))
print("removed %d delegations" % removed)
print("facade lines: %d -> %d" % (len(lines), len(final)))
