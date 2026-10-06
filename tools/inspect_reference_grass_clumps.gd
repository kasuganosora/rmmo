extends SceneTree
func _initialize()->void:
	var n=preload("res://scripts/world_editor/asset_library.gd").instantiate("D:/code/rmmo_runtime/assets/reference_grass_clumps/arch_A.glb")
	for m in preload("res://scripts/world3d/surface_materials.gd").meshes(n):
		var mat=m.get_active_material(0);var colors=m.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR];var lo=1.;var hi=0.
		for c in colors:lo=minf(lo,c.r);hi=maxf(hi,c.r)
		print("TINT ",m.name," use ",mat.vertex_color_use_as_albedo," srgb ",mat.vertex_color_is_srgb," first ",colors[0]," range ",lo," ",hi)
	n.free();quit()
