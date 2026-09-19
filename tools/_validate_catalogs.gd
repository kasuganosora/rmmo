extends SceneTree

const CATS := [
	"res://scripts/net/combat/item_catalog.gd",
	"res://scripts/net/combat/skill_catalog.gd",
	"res://scripts/net/combat/achievement_catalog.gd",
	"res://scripts/net/combat/fish_catalog.gd",
	"res://scripts/net/combat/gather_catalog.gd",
	"res://scripts/net/combat/recipe_catalog.gd",
	"res://scripts/net/combat/title_catalog.gd",
]

func _init() -> void:
	var bad := 0
	for path in CATS:
		var name = path.get_file()
		var sc = load(path)
		if sc == null:
			print("FAIL load ", name); bad += 1; continue
		var c = sc.new()
		c.load_catalog()
		if c.all_ids().is_empty():
			print("FAIL ", name, " all_ids empty"); bad += 1
		if c.list_all().is_empty():
			print("FAIL ", name, " list_all empty"); bad += 1
		var first = str(c.all_ids()[0]) if not c.all_ids().is_empty() else ""
		if first != "" and not c.has_id(first):
			print("FAIL ", name, " has_id"); bad += 1
		if first != "" and c.get_def(first).is_empty():
			print("FAIL ", name, " get_def"); bad += 1
		var nid = c.register_def({"id": "__t", "name": "T"})
		if nid != "__t" or not c.has_id("__t"):
			print("FAIL ", name, " register/has"); bad += 1
		if path.ends_with("fish_catalog.gd"):
			var spots: Array = c.spots_for_map("demo_map")
			if spots.is_empty():
				print("FAIL ", name, " spots_for_map"); bad += 1
			elif typeof(spots[0].get("cell", null)) != TYPE_DICTIONARY:
				print("FAIL ", name, " cell normalize"); bad += 1
			elif not (spots[0].get("yields", []) as Array).is_empty() and str(spots[0]["yields"][0].get("item_id", "")).is_empty():
				print("FAIL ", name, " yields normalize"); bad += 1
		if path.ends_with("gather_catalog.gd"):
			var nodes: Array = c.nodes_for_map("demo_map")
			if nodes.is_empty():
				print("FAIL ", name, " nodes_for_map"); bad += 1
			elif typeof(nodes[0].get("cell", null)) != TYPE_DICTIONARY:
				print("FAIL ", name, " cell normalize"); bad += 1
		print("OK    %-24s ids=%d" % [name, c.all_ids().size()])
	print("CATALOGS_OK=", bad == 0, " bad=", bad)
	quit()
