import re, io, glob

WORLD = "d:/code/rmmo/scripts/game/world.gd"
APP_DIR = "d:/code/rmmo/scripts/game/*/*.gd"  # application/ + infrastructure/

world = io.open(WORLD, "r", encoding="utf-8").read()
decl = set(re.findall(r"(?:func|static func|var|const|signal|@onready var)\s+([A-Za-z_]\w*)", world))

builtin = {
    "get_node_or_null", "create_tween", "add_child", "queue_free", "get_node",
    "has_method", "has_signal", "remove_child", "get_parent", "get_tree",
    "call_deferred", "set_deferred", "get_meta", "set_meta", "has_meta",
    "remove_meta", "emit_signal", "connect", "disconnect", "global_position",
    "position", "visible", "name", "z_index", "is_instance_valid",
    "is_inside_tree", "modulate",  # Node/Node2D members, valid on ctrl
}

bad_total = 0
for path in sorted(glob.glob(APP_DIR)):
    src = io.open(path, "r", encoding="utf-8").read()
    words = set(re.findall(r"ctrl\.([A-Za-z_]\w*)", src))
    missing = sorted(w for w in words if w not in decl and w not in builtin)
    print("%-46s ctrl.<word>=%d  MISSING=%s" % (path.split("/")[-1], len(words), missing or "none"))
    bad_total += len(missing)

print("TOTAL MISSING:", bad_total)
