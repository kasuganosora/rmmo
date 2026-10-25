extends SceneTree
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
	var materials:Array[Material]=[];var meshes:Array=[]
	for i:int in 32:
		var material:=StandardMaterial3D.new()
		material.set_meta("runtime_paint_definition",{"texture_path":"source/"+str(i),"normal_path":"source/normal","normal_format":"directx"})
		materials.append(material)
	for i:int in 512:
		var mesh:=Cpu.new();mesh.materials=[materials[i%32]];meshes.append(mesh)
		Prefab._meshes[str(i)]={"mesh":mesh,"source":mesh};Prefab._render_meshes[str(i)]=mesh
	var before:=Prefab.texture_invalidation_material_scans;var began:=Time.get_ticks_usec()
	Prefab.invalidate_texture_materials({"source/missing":true})
	var scans:=Prefab.texture_invalidation_material_scans-before
	print("INVALIDATION_WORK scans=",scans," elapsed_us=",Time.get_ticks_usec()-began)
	check(scans==32,"512 cached meshes inspect their 32 shared material definitions once")
	check(Prefab._meshes.size()==512 and Prefab._render_meshes.size()==512,"missing texture does not invalidate unrelated meshes")
	Prefab.invalidate_texture_materials({"source/7":true})
	check(Prefab._meshes.size()==496 and Prefab._render_meshes.size()==496,"exactly the sixteen affected source/render aliases are invalidated")
	var owner:Mesh=meshes[7]
	check(owner.materials[0]==materials[7],"cache eviction preserves existing geometry/material owners")
	materials[8].set_meta("runtime_paint_definition",{"texture_path":"source/edited"})
	Prefab.invalidate_texture_materials({"source/edited":true})
	check(Prefab._meshes.size()==480 and Prefab._render_meshes.size()==480,"a later notification observes an editor material change")
	Prefab.invalidate_texture_materials({"source/normal|normal":true})
	check(Prefab._meshes.size()==480,"OpenGL role does not evict DirectX normal materials")
	Prefab.invalidate_texture_materials({"source/normal|normal|flip_y":true})
	check(Prefab._meshes.is_empty() and Prefab._render_meshes.is_empty(),"normal orientation remains part of the affected texture identity")
	var rows:Array=[]
	for round_:int in 8:
		for i:int in 512:Prefab._meshes[str(i)]={"mesh":meshes[i],"source":meshes[i]};Prefab._render_meshes[str(i)]=meshes[i]
		began=Time.get_ticks_usec();Prefab.invalidate_texture_materials({"absent":true});rows.append(Time.get_ticks_usec()-began)
	print("INVALIDATION_STRESS_US ",rows)
	Prefab._meshes.clear();Prefab._render_meshes.clear();meshes.clear();materials.clear();owner=null
	print("TEXTURE_INVALIDATION_REUSE failures=",failures);quit(1 if failures else 0)
