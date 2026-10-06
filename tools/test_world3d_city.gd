extends SceneTree
## Module search, one-stroke ground paint, and chunk load/unload around the player.

const Modules = preload("res://scripts/world3d/world_modules.gd")
const Paint = preload("res://scripts/world3d/world_paint.gd")
const Document = preload("res://scripts/world3d/world_document.gd")
const Stream = preload("res://scripts/world3d/world_stream.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var walls: Array = Modules.search("墙")
	failed += _expect(walls.size() == 1 and str(walls[0].id) == "wall_4", "module search finds the wall")
	failed += _expect(Modules.get_module("missing_wall").is_empty(), "a missing module id is not replaced")
	var doc = Document.new()
	var stroke = Paint.new()
	var ground: Dictionary = Modules.get_module("ground_4")
	stroke.begin(doc)
	stroke.add(doc, Vector3(0.2, 0.2, 0.2), ground)
	stroke.add(doc, Vector3(5.2, 0.2, 0.2), ground)
	var painted := stroke.end()
	failed += _expect(painted == 2 and doc.records.size() == 2, "one stroke paints two ground cells")
	failed += _expect(doc.undo() and doc.records.is_empty(), "undo removes the whole stroke")
	var host := Node3D.new()
	root.add_child(host)
	var map := Node3D.new()
	host.add_child(map)
	_box(map, "near", Vector3.ZERO)
	_box(map, "mid", Vector3(70, 0, 0))
	_box(map, "far", Vector3(200, 0, 0))
	Stream.sync(map, host, Vector3.ZERO)
	var mid := map.get_node_or_null("mid") as MeshInstance3D
	failed += _expect(mid == null and host.get_node_or_null("mid_body") != null, "chunk at 70 m keeps collision without a visual")
	failed += _expect(map.get_node_or_null("far") == null and host.get_node_or_null("far_body") == null, "chunk at 200 m is not loaded")
	Stream.sync(map, host, Vector3(200, 0, 0))
	failed += _expect(map.get_node_or_null("far") != null and host.get_node_or_null("far_body") != null, "walking to 200 m loads that chunk")
	failed += _expect(map.get_node_or_null("near") == null and host.get_node_or_null("near_body") == null, "the chunk left behind is unloaded")
	host.free()
	print("test_world3d_city: %s" % ("FAIL %d" % failed if failed else "PASS"))
	quit(1 if failed else 0)


func _box(parent: Node, box_name: String, at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = box_name
	var shape := BoxMesh.new()
	shape.size = Vector3.ONE
	mesh.mesh = shape
	mesh.position = at
	parent.add_child(mesh)


func _expect(ok: bool, label: String) -> int:
	if not ok:
		print("test_world3d_city: FAIL %s" % label)
		return 1
	return 0
