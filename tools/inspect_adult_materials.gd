extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var model=preload("res://scripts/char/character_model_3d.gd").new();root.add_child(model)
	for gender in ["male","female"]:
		model.configure(gender,{}, {})
		for category in model.gear:
			for mesh in model.gear[category]:
				print(gender," ",category," ",mesh.name," override=",mesh.material_override)
				for i in range(mesh.mesh.get_surface_count()):
					var mat=mesh.get_active_material(i)
					print(" MATERIAL ",mat)
					if mat is StandardMaterial3D:print(" base ",mat.albedo_texture," emit ",mat.emission_texture," color ",mat.albedo_color," flags ",mat.shading_mode)
	quit()
