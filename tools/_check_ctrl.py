import re, io, glob

APP_DIRS = [
    "d:/code/rmmo/scripts/game/*/*.gd",   # application/ + infrastructure/ + interface/
    "d:/code/rmmo/scripts/ui/panels/*.gd",  # HUD panel modules
]
# composition roots: world.gd, player.gd, game_hud.gd, ...
ROOT_GLOBS = ["d:/code/rmmo/scripts/game/*.gd", "d:/code/rmmo/scripts/ui/game_hud.gd"]

# declarations must come from EVERY composition root, otherwise modules of
# another root report false positives.
decl = set()
for pat in ROOT_GLOBS:
    for root in sorted(glob.glob(pat)):
        src = io.open(root, "r", encoding="utf-8").read()
        decl |= set(re.findall(r"(?:func|static func|var|const|signal|@onready var)\s+([A-Za-z_]\w*)", src))

builtin = {
    "get_node_or_null", "create_tween", "add_child", "queue_free", "get_node",
    "has_method", "has_signal", "remove_child", "get_parent", "get_tree",
    "call_deferred", "set_deferred", "get_meta", "set_meta", "has_meta",
    "remove_meta", "emit_signal", "connect", "disconnect", "global_position",
    "position", "visible", "name", "z_index", "is_instance_valid",
    "is_inside_tree", "modulate",  # Node/Node2D members, valid on ctrl
    # Node / CanvasItem / Node2D members (valid on ctrl, not World-declared)
    "move_child", "get_viewport", "get_global_mouse_position",
    "get_local_mouse_position", "get_viewport_rect", "get_canvas_transform",
    "get_screen_transform", "get_window", "set_process", "set_physics_process",
    "get_index", "raise", "show", "hide", "is_visible_in_tree",
    "get_child", "get_children", "get_child_count", "to_local", "to_global",
    # Control / CanvasItem members (HUD root is a Control)
    "size", "scale", "rotation", "pivot_offset", "mouse_filter", "focus_mode",
    "get_rect", "get_global_rect", "has_focus", "grab_focus", "release_focus",
    "accept_event", "set_anchors_preset", "set_offsets_preset", "queue_redraw",
    "get_screen_position", "custom_minimum_size", "theme", "anchor_mode",
}

bad_total = 0
paths = []
for pat in APP_DIRS:
    paths += sorted(glob.glob(pat))
for path in paths:
    src = io.open(path, "r", encoding="utf-8").read()
    words = set(re.findall(r"ctrl\.([A-Za-z_]\w*)", src))
    missing = sorted(w for w in words if w not in decl and w not in builtin)
    print("%-46s ctrl.<word>=%d  MISSING=%s" % (path.split("/")[-1], len(words), missing or "none"))
    bad_total += len(missing)

print("TOTAL MISSING:", bad_total)
