extends SceneTree
## Isolate surface binding from simulation. Does not overwrite cloth captures.
const Art = preload("res://scripts/asset/art_paths.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var studio = preload("res://tools/character_skin_studio.gd").new()
	studio.interactive = false
	root.add_child(studio)
	studio.show_new_base()
	studio.set_surface_outfit(8)
	var body: Node3D = studio.regional_preview
	var garment: Node3D = studio.surface_wardrobe.garments.Clothing2
	for pose in ["rest", "stand", "sit"]:
		body.set_test_pose(pose)
		for frame in 3: await process_frame
		var values: Array = []
		for p: Vector3 in garment.evaluate(body.posed_points): values.append([p.x,p.y,p.z])
		var file := FileAccess.open(Art.review_path("character_3d/binding_hw_"+pose+".json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"garment_id":garment.garment_id,"garment":values}))
		file.close()
	studio.free()
	for frame in 4: await process_frame
	print("PASS captured binding-only geometry, no candidate simulation")
	quit()
