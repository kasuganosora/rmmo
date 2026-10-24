extends SceneTree
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:
	Controls.enable_white_materials();Controls.discard_map_textures=true
	var original:=StandardMaterial3D.new();original.albedo_color=Color.BLACK;original.emission_enabled=true
	var definition:=Cook.material_data(original);var values:Array=[]
	for i:int in 600:
		var value:Dictionary=definition.duplicate(true);value["values"].roughness=float(i)/601.;value["values"].cull_mode=i%3;values.append(value)
	var timings:Array=[]
	for round_:int in 4:
		var pool:Dictionary={};var started:=Time.get_ticks_usec()
		for value:Dictionary in values:Cook.restore_material(value,null,pool)
		timings.append(Time.get_ticks_usec()-started)
		var same:=true
		for value:Dictionary in values:same=same and pool[[value]]==Controls.white_material(value["values"].cull_mode)
		check(same,"white restore directly shares one plain material per cull mode")
	var pool:Dictionary={};var painted:={"paint":{"color":[0.,0.,0.,1.]},"cull":BaseMaterial3D.CULL_FRONT,"vertex_color":true}
	check(Cook.restore_material(painted,null,pool) and pool[[painted]]==Controls.white_material(BaseMaterial3D.CULL_FRONT),"white diagnostic ignores unused paint and vertex color while preserving culling")
	Controls.white_materials=false;pool={}
	check(Cook.restore_material(definition,null,pool) and pool[[definition]].albedo_color==Color.BLACK and pool[[definition]].emission_enabled,"ordinary material restoration remains exact after disabling the white control")
	print("WHITE_MATERIAL_RESTORE ",JSON.stringify({"trials_us":timings,"failures":failures}));quit(1 if failures else 0)
