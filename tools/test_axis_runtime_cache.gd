extends SceneTree
const Assets=preload("res://scripts/char/character_axis_assets.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func save_json(path:String,value:Variant)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(value));file.close()
func run()->void:
	var folder:=Art.review_path("character_3d/runtime_performance_02/cache_fixture")
	DirAccess.make_dir_recursive_absolute(folder)
	var topology:Dictionary={"display_points":[[0,0,0],[1,0,0],[1,1,0],[0,1,0]],"ranges":[[0,1],[1,1],[2,1],[3,1]],"surfaces":[[[[0,1,2,3],[[0,0],[1,0],[1,1],[0,1]]]]]}
	var rig:Dictionary={"nodes":[]}
	save_json(folder+"/female_axis_rig.json",rig);save_json(folder+"/female_display_topology.json",topology)
	var mesh:=Assets.build_mesh(topology)
	assert(ResourceSaver.save(mesh,folder+"/axis_runtime_mesh.res")==OK)
	var file:=FileAccess.open(folder+"/axis_runtime_data.bin",FileAccess.WRITE)
	file.store_var({"signature":Assets.signature(folder),"mesh_sha256":FileAccess.get_sha256(folder+"/axis_runtime_mesh.res"),"rig":rig,"topology":topology});file.close()
	var hit:=Assets.get_assets(folder)
	assert(hit.mesh is ArrayMesh and Assets.get_assets(folder)==hit)
	# A changed source must win over the persisted mesh and data.
	topology.display_points[0][0]=-.25
	save_json(folder+"/female_display_topology.json",topology)
	Assets.entries.erase(folder)
	var stale:=Assets.get_assets(folder)
	assert(stale.topology.display_points[0][0]==-.25)
	assert(stale.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0].x==-.25)
	# A matching data stamp with the wrong mesh checksum also rebuilds geometry.
	file=FileAccess.open(folder+"/axis_runtime_data.bin",FileAccess.WRITE)
	file.store_var({"signature":Assets.signature(folder),"mesh_sha256":"wrong","rig":rig,"topology":topology});file.close()
	Assets.entries.erase(folder)
	assert(Assets.get_assets(folder).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0].x==-.25)
	print("PASS baked cache reuse, source hash invalidation and mismatched mesh fallback")
	quit()
