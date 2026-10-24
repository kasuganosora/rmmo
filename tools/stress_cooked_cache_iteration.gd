extends SceneTree
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Probe=preload("res://tools/cooked_cache_iteration_probe.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var cache:Dictionary={};var library:Array=[]
	for i:int in 63:
		var heights:Array=[];var holes:Array=[];var normals:Dictionary={}
		for j:int in 65*65:heights.append(float(j%65)*.01);normals[j]=Vector3.UP
		for j:int in 64*64:holes.append(false)
		var record:={"uuid":"terrain%d"%i,"kind":"box","position":[i*128.,0,0],"rotation":[0,0,0],"size":[128.,1.,128.],"terrain_mesh":{"version":1,"columns":64,"rows":64,"floor":-2.,"heights":heights,"holes":holes}}
		var surface:Array=[];surface.resize(Mesh.ARRAY_MAX);surface[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK])
		var mesh:=Cpu.from_surfaces([surface],[null]);cache[["terrain_mesh",record,normals]]={"mesh":mesh,"source":mesh}
		library.append({"uuid":record.uuid,"mesh":mesh,"collision_mesh":mesh,"surface_overrides":[],"extras":{},"native_visual":false,"cast_shadow":1,"transform":Transform3D.IDENTITY,"position":Vector3.ZERO,"rotation":Vector3.ZERO,"chunk":Vector2i.ZERO,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO,"ground_batch_record":record})
	var expected:=Cook.pack(cache,"source","generator",library);var reference:=var_to_bytes(expected)
	var trials:Array=[]
	for optimized:bool in [false,true,true,false]:
		Cook.pack_iteration_enabled=optimized
		var elapsed:=0;var exact:=true
		for repeat:int in 8:
			var began:=Time.get_ticks_usec()
			var output:Dictionary=Cook.pack(cache,"source","generator",library)
			elapsed+=Time.get_ticks_usec()-began
			exact=exact and var_to_bytes(output)==reference
		check(exact,"cooked snapshot bytes, key order, meshes, materials and specs stay exact")
		trials.append({"optimized":optimized,"us":elapsed,"records":63*8,"full_key_hash_lookups":0 if optimized else 63*8*2})
	Cook.pack_iteration_enabled=true
	check(Cook.valid_data(expected),"full serialized snapshot remains valid")
	var restored:Dictionary=Cook.restore(bytes_to_var(reference));check(restored.size()==cache.size(),"plain snapshot roundtrip restores every geometry key")
	for key:Array in cache:check(restored.has(key) and restored[key].mesh.surfaces==cache[key].mesh.surfaces,"source channels survive exact restore")
	var report:={"trials":trials,"failures":failures}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("COOKED_CACHE_ITERATION ",JSON.stringify(report));quit(1 if failures else 0)
