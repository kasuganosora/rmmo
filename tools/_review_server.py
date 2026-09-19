import re, glob, os, sys

FACADE = sys.argv[1] if len(sys.argv) > 1 else "scripts/net/mock_server.gd"
MODULES = sys.argv[2] if len(sys.argv) > 2 else "scripts/net/server/*.gd"

hud = open(FACADE, encoding="utf-8").read()
members = set(re.findall(r"(?m)^(?:@\w+(?:\([^\n]*\))?\s+)*var\s+(\w+)", hud))
members |= set(re.findall(r"(?m)^signal\s+(\w+)", hud))
members |= set(re.findall(r"(?m)^(?:static\s+)?func\s+(\w+)", hud))
members |= set(re.findall(r"(?m)^const\s+(\w+)", hud))
members |= set(re.findall(r"(?m)^enum\s+(\w+)", hud))

BUILTINS = set("""add_child get_node_or_null create_tween is_inside_tree queue_free remove_child
get_parent get_tree has_method emit_signal connect disconnect get_meta set_meta has_meta remove_meta
modulate global_position position to_local to_global get_child get_children get_child_count move_child
get_viewport get_global_mouse_position get_local_mouse_position get_viewport_rect get_canvas_transform
get_screen_transform get_window set_process set_physics_process get_index raise show hide is_visible_in_tree
call_deferred set_deferred is_node_ready request_ready get_path get_name set_name duplicate free
get_instance_id notify_property_list_changed has_node find_child find_children get_last_child add_sibling
reparent force_update_transform update_configuration_warnings get_signal_list get_method_list get_property_list
get_script set_script tr to_string get_class is_class is_queued_for_deletion cancel_free
is_instance_valid str int float bool len range print printt prints push_error push_warning
set_process_input set_process_unhandled_input randf randi randf_range randi_range seed randomize
clamp clampf clampi maxf minf mini maxi abs sign floor ceil round lerp snapped fmod fposmod
Time JSON FileAccess DirAccess ResourceLoader ProjectSettings load PackedStringArray
Vector2 Vector2i Vector3 Color Array Dictionary String Variant Callable Signal
create_timer change_scene_to_file get_multiplayer rpc rpc_id is_server is_client""".split())

def params_of(sig):
    i = sig.index("("); depth, j = 0, i
    while j < len(sig):
        if sig[j] == "(": depth += 1
        elif sig[j] == ")":
            depth -= 1
            if depth == 0: break
        j += 1
    inner = sig[i+1:j]; parts, d, cur = [], 0, ""
    for ch in inner:
        if ch == "(": d += 1
        elif ch == ")": d -= 1
        if ch == "," and d == 0: parts.append(cur); cur = ""
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

issues = []
module_methods = {}
for f in sorted(glob.glob(MODULES)):
    lines = open(f, encoding="utf-8").read().split("\n")
    base = os.path.basename(f)
    src = "\n".join(lines)
    mset = set(re.findall(r"(?m)^func (\w+)\(", src))
    module_methods[base[:-3]] = mset
    # member resolution + bare self
    for cm in sorted(set(re.findall(r"\bctrl\.(\w+)", src))):
        if cm not in members and cm not in BUILTINS:
            issues.append("%s: ctrl.%s (not a facade member/builtin)" % (base, cm))
    for ln in lines:
        code = re.sub(r'"[^"\n]*"', '""', ln).split("#")[0]
        if re.search(r"\bself\b", code):
            issues.append("%s: bare self -> %s" % (base, ln.strip()))
    # param/local shadow
    idxs = [i for i, ln in enumerate(lines) if re.match(r"^func (\w+)\(", ln)] + [len(lines)]
    for k in range(len(idxs)-1):
        i0 = idxs[k]
        name = re.match(r"^func (\w+)\(", lines[i0]).group(1)
        if name == "_init": continue
        sig = lines[i0]; kk = i0
        while not sig.rstrip().endswith(":") and kk+1 < idxs[k+1]:
            kk += 1; sig += " " + lines[kk].strip()
        body = lines[kk+1:idxs[k+1]]
        # params are function-scoped: `ctrl.<param>` is ALWAYS wrong. Block-scoped
        # locals are handled precisely by _scan_shadow.py (a `ctrl.<member>` sharing a
        # block-local's name is legitimate), so we only flag params here.
        skip = set(params_of(sig))
        for ln in body:
            code = re.sub(r'"[^"\n]*"', '""', ln).split("#")[0]
            for cm in re.findall(r"\bctrl\.(\w+)", code):
                if cm in skip:
                    issues.append("%s: func %s param '%s' wrongly -> ctrl.%s" % (base, name, cm, cm))

# delegation consistency
for m in re.finditer(r"\b_(\w+)_logic\.(\w+)\(", hud):
    snake, meth = m.group(1), m.group(2)
    if snake in module_methods and meth not in module_methods[snake]:
        issues.append("facade: _%s_logic.%s missing in module" % (snake, meth))

print("facade members:", len(members), "| modules:", len(module_methods))
print("ISSUES:", len(issues))
for i in issues[:60]:
    print("  " + i)
