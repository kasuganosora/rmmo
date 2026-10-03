extends "res://tools/test_terrain_surface.gd"
const OUTPUT="D:/code/rmmo_runtime/review_artifacts/river_bank_lab"
func _initialize() -> void:
	var reference:=GDScript.new(); reference.source_code=FileAccess.get_file_as_string(OUTPUT.path_join("terrain_mesh_before_optimization.gd"))
	check(reference.reload()==OK,"baseline terrain script loads")
	var r:=fixture(); r.size=[24,1,24]; r.terrain_mesh.columns=64; r.terrain_mesh.rows=64; r.terrain_mesh.heights.resize(4225); r.terrain_mesh.holes.resize(4096); r.terrain_mesh.holes.fill(false)
	for z in 65:
		for x in 65: r.terrain_mesh.heights[z*65+x]=sin(x*.25)*cos(z*.23)*2
	var results:={}
	for mode in ["solid","holes"]:
		if mode=="holes":
			for z in range(24,31):
				for x in range(24,31): r.terrain_mesh.holes[z*64+x]=true
		var old: ArrayMesh=reference.mesh(r,null); var next:=T.mesh(r,null)
		for slot in 2:
			var a:=old.surface_get_arrays(slot); var b:=next.surface_get_arrays(slot)
			for field in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_INDEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_TEX_UV]: check(a[field]==b[field],"same mesh/paint signature "+str([mode,slot,field]))
		var before: Array[float]=[]; var after: Array[float]=[]
		for i in 6:
			var start:=Time.get_ticks_usec(); reference.mesh(r,null); before.append((Time.get_ticks_usec()-start)/1000.)
			start=Time.get_ticks_usec(); T.mesh(r,null); after.append((Time.get_ticks_usec()-start)/1000.)
		before.sort(); after.sort(); results[mode]={"before_median_ms":before[3],"after_median_ms":after[3]}
	results.failures=failures
	var f:=FileAccess.open(OUTPUT.path_join("mesh_performance.json"),FileAccess.WRITE); f.store_string(JSON.stringify(results,"\t")); f.close()
	print("TERRAIN_MESH_PERFORMANCE ",JSON.stringify(results)); quit(1 if failures else 0)
