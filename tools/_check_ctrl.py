import re, io

AA = "d:/code/rmmo/scripts/game/application/action_apply.gd"
WORLD = "d:/code/rmmo/scripts/game/world.gd"

aa = io.open(AA, "r", encoding="utf-8").read()
world = io.open(WORLD, "r", encoding="utf-8").read()

# distinct ctrl.<word> immediate members (skip chained ctrl.hud.x handled separately)
ctrl_words = set(re.findall(r"ctrl\.([A-Za-z_]\w*)", aa))

# world.gd declared names: func / static func / var / const / signal / @onready var
decl = set(re.findall(r"(?:func|static func|var|const|signal|@onready var)\s+([A-Za-z_]\w*)", world))

# builtin Node/Node2D/Object members allowed on ctrl (World extends Node2D)
builtin = {
    "get_node_or_null", "create_tween", "add_child", "queue_free", "get_node",
    "has_method", "has_signal", "remove_child", "get_parent", "get_tree",
    "call_deferred", "set_deferred", "get_meta", "set_meta", "has_meta",
    "remove_meta", "emit_signal", "connect", "disconnect", "global_position",
    "position", "visible", "name", "z_index", "is_instance_valid",
}

missing = sorted(w for w in ctrl_words if w not in decl and w not in builtin)
print("DISTINCT ctrl.<word> count:", len(ctrl_words))
print("WORLD declared names count:", len(decl))
print("MISSING (ctrl.X not found in World):")
for m in missing:
    print("  ", m)
if not missing:
    print("  (none)")
