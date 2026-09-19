"""Reusable slice extractor: move a group of world.gd methods into a layer module.

Usage:
  python3 tools/_surgery_slice.py <out_res_path> <ConstName> "<header>" <m1,m2,...>

Handles: multi-line signatures, body-based return detection, Node member prefixing,
auto const injection.
"""
import re, io, sys

WORLD = "d:/code/rmmo/scripts/game/world.gd"

out_res, constname, header, methods = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].split(",")
OUT = out_res.replace("res://", "d:/code/rmmo/")

src = io.open(WORLD, "r", encoding="utf-8").read()
lines = src.split("\n")

consts = set(re.findall(r"^const\s+([A-Za-z_]\w*)", src, re.M))
members = set()
# captures `var x`, `@onready var x`, and annotated forms like `@export var x`
for m in re.findall(r"^(?:@[A-Za-z_]\w*(?:\([^)]*\))?\s+)*var\s+([A-Za-z_]\w*)", src, re.M):
    members.add(m)
for m in re.findall(r"^signal\s+([A-Za-z_]\w*)", src, re.M):
    members.add(m)
for m in re.findall(r"^(?:func|static\s+func)\s+([A-Za-z_]\w*)", src, re.M):
    members.add(m)
members -= consts

GLOBALS = {
    "str", "int", "float", "bool", "Vector2", "Vector2i", "Vector3", "Color", "Array",
    "Dictionary", "String", "Variant", "maxf", "minf", "mini", "maxi", "clampf", "typeof",
    "abs", "sign", "round", "floor", "ceil", "clamp", "lerp", "randf_range", "randi",
    "is_instance_valid", "ResourceLoader", "FileAccess", "JSON", "ProjectSettings",
    "load", "PackedStringArray", "PackedVector2Array", "Rect2", "Transform2D",
    "AudioStream", "AudioStreamPlayer", "AudioStreamOggVorbis", "AudioStreamWAV",
    "Resource", "CanvasLayer", "Label", "Node", "Node2D", "Tween", "Timer",
}

NODE_MEMBERS = [
    "add_child", "get_node_or_null", "create_tween", "is_inside_tree", "queue_free",
    "remove_child", "get_parent", "get_tree", "has_method", "emit_signal", "connect",
    "get_meta", "set_meta", "has_meta", "remove_meta", "modulate", "global_position",
    "position", "to_local", "to_global", "get_child", "get_children", "get_child_count",
    # Node/CanvasItem/Node2D methods discovered during ground-loot slice:
    "move_child", "get_viewport", "get_global_mouse_position",
    "get_local_mouse_position", "get_viewport_rect", "get_canvas_transform",
    "get_screen_transform", "get_window", "set_process", "set_physics_process",
    "get_index", "raise", "show", "hide", "is_visible_in_tree",
    # Object/Node methods seen later (call_deferred etc.)
    "call_deferred", "set_deferred", "is_node_ready", "request_ready",
    "get_path", "get_name", "set_name", "duplicate", "free", "get_instance_id",
    "notify_property_list_changed", "has_node", "find_child", "find_children",
    "get_last_child", "add_sibling", "reparent", "force_update_transform",
    "update_configuration_warnings", "get_signal_list", "get_method_list",
    "get_property_list", "get_script", "set_script", "tr", "to_string",
    "get_class", "is_class", "is_queued_for_deletion", "cancel_free",
]


def parse_params(sig_text):
    i = sig_text.index("(")
    depth, j = 0, i
    while j < len(sig_text):
        if sig_text[j] == "(":
            depth += 1
        elif sig_text[j] == ")":
            depth -= 1
            if depth == 0:
                break
        j += 1
    inner = sig_text[i + 1:j]
    parts, d, cur = [], 0, ""
    for ch in inner:
        if ch == "(":
            d += 1
        elif ch == ")":
            d -= 1
        if ch == "," and d == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    return [p.strip().split(":")[0].split("=")[0].strip() for p in parts if p.strip()]


def read_func(idx):
    """Return (sig_text, body_lines, end_idx) handling multi-line signatures."""
    sig, k = [lines[idx]], idx
    while not sig[-1].rstrip().endswith(":") and k + 1 < len(lines):
        k += 1
        sig.append(lines[k])
    bs = k + 1
    be, n = bs, len(lines)
    while be < n:
        s = lines[be].strip()
        if s == "":
            be += 1
            continue
        if len(lines[be]) - len(lines[be].lstrip(" \t")) == 0:
            break
        be += 1
    return "\n".join(sig), lines[bs:be], be


def returns_value(body):
    for ln in body:
        s = ln.strip()
        if s == "return" or s.startswith("return#"):
            continue
        if re.match(r"^return\s+\S", s):
            return True
    return False


def collect_locals(body):
    loc = set()
    for ln in body:
        for m in re.findall(r"\bvar\s+([A-Za-z_]\w*)", ln):
            loc.add(m)
        for m in re.findall(r"\bfor\s+([A-Za-z_]\w*)\s+in\b", ln):
            loc.add(m)
    return loc


def prefix(line, skip):
    if line.strip().startswith("#"):
        return line
    parts = line.split('"')
    for k in range(0, len(parts), 2):
        seg = parts[k]
        for nm in sorted(members - skip - GLOBALS, key=len, reverse=True):
            seg = re.sub(r"(?<![\w.])%s(?![\w])" % re.escape(nm), "ctrl." + nm, seg)
        for nm in NODE_MEMBERS:
            # CRITICAL: never rewrite locals/params (a local named `show` or
            # `position` would otherwise become `ctrl.show` and break the syntax).
            if nm in skip or nm in GLOBALS:
                continue
            seg = re.sub(r"(?<![\w.])%s(?![\w])" % re.escape(nm), "ctrl." + nm, seg)
        # `self` is illegal in a static func; it referred to the world node -> ctrl
        seg = re.sub(r"(?<![\w.])self(?![\w])", "ctrl", seg)
        parts[k] = seg
    return '"'.join(parts)


targets = []
for i, ln in enumerate(lines):
    m = re.match(r"^func (%s)\(" % "|".join(re.escape(x) for x in methods), ln)
    if m:
        targets.append((m.group(1), i))

blocks, value_returns = [], set()
for name, idx in reversed(targets):
    sig_text, body, be = read_func(idx)
    blocks.append((name, sig_text, body))
    if returns_value(body):
        value_returns.add(name)
    params = parse_params(sig_text)
    ret = "return " if name in value_returns else ""
    sig_first = sig_text.split("\n")[0]
    end = be
    del lines[idx + 1:end]
    lines[idx] = sig_first
    lines.insert(idx + 1, "\t%s%s.%s(self, %s)" % (ret, constname, name, ", ".join(params)))
blocks.reverse()

out = ["extends RefCounted"]
out += header.split("\n")
out.append("")
for name, sig_text, body in blocks:
    newsig = re.sub(r"^func\s+", "static func ", sig_text)
    newsig = re.sub(r"^static func (\w+)\(", r"static func \1(ctrl, ", newsig, count=1)
    newsig = newsig.replace("(ctrl, )", "(ctrl)")
    loc = collect_locals(body)
    out += newsig.split("\n")
    for ln in body:
        out.append(prefix(ln, loc))
    out.append("")

tsrc = "\n".join(out)
cdecl = dict(re.findall(r"^const\s+([A-Za-z_]\w*)\s*=\s*(preload\(.*?\))", src, re.M))
declared = set(re.findall(r"^const\s+([A-Za-z_]\w*)", tsrc, re.M))
need = [n for n in cdecl if n not in declared and re.search(r"(?<![\w.])%s(?![\w])" % n, tsrc)]
if need:
    idx = next(i for i, ln in enumerate(out) if ln.startswith("static func"))
    out[idx:idx] = ["const %s = %s" % (n, cdecl[n]) for n in need] + [""]

io.open(OUT, "w", encoding="utf-8").write("\n".join(out))

text = "\n".join(lines)
# NOTE: must match the exact declaration; a substring check would be fooled by
# an existing `const SkillAimOverlay` when inserting `const SkillAim`.
if not re.search(r"^const\s+%s\s*=" % re.escape(constname), text, re.M):
    last = max(i for i, ln in enumerate(lines[:60]) if ln.startswith("const "))
    lines.insert(last + 1, 'const %s = preload("%s")' % (constname, out_res))
    text = "\n".join(lines)
io.open(WORLD, "w", encoding="utf-8").write(text)

print("MOVED %d into %s" % (len(blocks), out_res))
print("VALUE_RETURNING:", sorted(value_returns))
print("CONSTS_ADDED:", need)
