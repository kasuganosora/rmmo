extends "res://tools/test_prefab_material_owner_reuse.gd"
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
func _initialize()->void:
	Controls.enable_white_materials()
	var mats:Array[Material]=[Controls.white_material(),Controls.white_material(BaseMaterial3D.CULL_FRONT),Controls.white_material(BaseMaterial3D.CULL_DISABLED)]
	var began:=Time.get_ticks_usec();var first:Dictionary={}
	for i:int in 400:
		var value:=entry(mats);publish("first_%d"%i,value,"geometry_%d"%i)
		if i==0:first=value
	var elapsed:=Time.get_ticks_usec()-began
	var same:=entry(mats);publish("repeat",same,"geometry_0")
	check(is_same(first.mesh,same.mesh),"same geometry and canonical white owners share exact mesh")
	var changed:=entry([mats[1],mats[0],mats[2]]);publish("cull_change",changed,"geometry_0")
	check(not is_same(changed.mesh,first.mesh),"surface cull ordering remains part of the identity")
	var old:Mesh=first.mesh
	House._meshes.clear();House._render_meshes.clear();Controls.enable_white_materials()
	var fresh:=entry([Controls.white_material(),Controls.white_material(BaseMaterial3D.CULL_FRONT),Controls.white_material(BaseMaterial3D.CULL_DISABLED)]);publish("new_generation",fresh,"geometry_0")
	check(not is_same(fresh.mesh,old),"new white generation cannot reuse previous material owners")
	if "--expect-scan" not in OS.get_cmdline_user_args():check(House.material_identity_scans==0,"different geometries never serialize canonical white material properties")
	print("WHITE_PREFAB_MATERIAL_IDENTITY ",JSON.stringify({"us":elapsed,"scans":House.material_identity_scans,"failures":failures}));quit(1 if failures else 0)
