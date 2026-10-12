extends RefCounted
## Shared CPU-only immutable fixtures for directory and private GPU integration tests.
const Store = preload("res://scripts/world3d/map_resource_store.gd")
const Fort = preload("res://scripts/world3d/fortification_data.gd")
const Layout = preload("res://scripts/world3d/city_layout.gd")

static func prefab(size: Vector3) -> Dictionary:
	var h := size / 2.0
	var vertices := PackedVector3Array()
	for face in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
		for corner in [face[0], face[1], face[2], face[0], face[2], face[3]]:
			vertices.append(Vector3(h.x if corner & 1 else -h.x, h.y if corner & 2 else -h.y, h.z if corner & 4 else -h.z))
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = vertices
	var data := {"materials": [{"null": true}], "meshes": [{"bounds": AABB(-h, size), "box_size": Vector3.ZERO, "surfaces": [arrays], "materials": [0]}], "entries": [[[0], [0, 0]]], "specs": []}
	var bytes := var_to_bytes(data)
	return {"version": 1, "sha256": Store._sha(bytes), "length": bytes.size(), "data": Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}

static func wall(id: String, x: float, owner: String = "test_ring") -> Dictionary:
	return {"uuid": id, "kind": "box", "position": [x, 2, 0], "rotation": [0, 0, 0], "size": [1, 1, 1], "surface_id": "block", "collision": "block", "fortification": {"id": owner, "part": id, "role": "prefab"}, "house_prefab": prefab(Vector3(8, 4, 2)), "prefab_locked": true, "prefab_materials": [], "editor_group": owner}

static func door(id: String, x: float, owner: String = "test_ring", right: bool = false) -> Dictionary:
	var value := wall(id, x, owner)
	value.house_prefab = prefab(Vector3(2, 4, .3))
	value.fixture = {"id": "main_gate", "kind": "door", "pivot": [1 if right else -1, 0, 0], "angle": -100 if right else 100, "open": 0.0}
	return value

static func bridge(id: String, x: float, content_root: String) -> Dictionary:
	var material := {"name": "fixture stone", "color": [.6, .6, .6, 1.0], "tile_size": [1, 1], "roughness": .9}
	return {"uuid": id, "kind": "asset", "position": [x, -.4, 0], "rotation": [0, 0, 0], "size": [1, 1, 1], "surface_id": "bridge_deck", "collision": "walk", "asset_path": content_root.path_join("packs/default/assets/bridges/medieval_stone/stone_segmental.glb"), "bounds_position": [0, 0, 0], "bounds_size": [1, 1, 1], "bridge_mesh": {"version": 1, "prefab_id": "stone_segmental", "length": 20, "width": 6, "depth": 2, "camber": 0, "arches": 2, "recipe": {"style": "segmental", "max_span": 10, "rail_height": 1.05, "pier_width": 1.3}}, "bridge_materials": {"deck": material, "masonry": material.duplicate(), "trim": material.duplicate()}, "house_prefab": prefab(Vector3(20, .8, 6)), "prefab_locked": true, "prefab_materials": []}

static func records(content_root: String) -> Array:
	return [wall("near_wall", 0), wall("far_wall", 512), door("gate_left", 520), door("gate_right", 522, "test_ring", true), door("other_gate", 650, "other_ring"), bridge("whole_bridge", 900, content_root)]

static func metadata(records_: Array) -> Dictionary:
	var regions := {}
	for record: Dictionary in records_:
		if not record.has("fortification"): continue
		var id: String = record.fortification.id
		if not regions.has(id):
			var settings := Fort.defaults(); settings.id = id; settings.points = [[0, 0], [1000, 0]]
			regions[id] = {"version": 1, "baked": true, "source_part_count": 20, "settings": settings, "parts": []}
		regions[id].parts.append({"id": record.uuid, "signature": Layout.token(record)})
	var layout := Layout.defaults()
	layout.fortifications = regions.values()
	return {"editor_layout": layout}
