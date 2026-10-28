extends SceneTree
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	var folder:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):folder=arg.trim_prefix("--root=")
	if folder.is_empty() or not Paths.allowed(folder):quit(1);return
	check(DirAccess.make_dir_recursive_absolute(folder)==OK,"create isolated source directory")
	var path:=folder.path_join("preflight.png")
	var image:=Image.create(32,32,false,Image.FORMAT_RGBA8);image.fill(Color(.3,.4,.8))
	check(image.save_png(path)==OK,"create actual source pixels")
	var node:=MeshInstance3D.new();node.mesh=BoxMesh.new()
	var geo:=Paint.geometry(node)
	var entry:={"mesh":".","surface":0,"face":geo.surfaces[0].faces.keys()[0],"geometry":geo.surfaces[0].signature,"mapping":"planar","scale":[1.,1.],"offset":[0.,0.],"rotation":0.,"material":{"name":"budget owner","texture_path":path,"color":[1.,1.,1.,1.],"roughness":.9}}
	var old_budget:=Paint.cache_byte_budget;Paint.cache_byte_budget=0
	Pixels.reset_profile();Pixels.profile_enabled=true;Paint.texture_profile_enabled=true
	var plan:=Paint.validate_paint(node,[entry])
	check(plan.ok,"preflight succeeds under zero retained-cache budget")
	var key:=Paint.texture_key(path)
	check(not Paint._textures.has(key),"temporary texture does not bypass the retained-cache budget")
	# Do not retain an extra strong owner in the assertion or it would prepay
	# the very lifetime the regression is testing.
	var borrowed:WeakRef=weakref(Paint.retained_texture(key)) if Paint.retained_texture(key)!=null else null
	check(borrowed!=null and borrowed.get_ref()!=null,"validation packet keeps the borrowed texture alive through commit")
	var before:Dictionary=Pixels.profile_snapshot("")
	var built:=Paint.painted_mesh(node,[entry])
	var after:Dictionary=Pixels.profile_snapshot("")
	check(built.ok,"final painted mesh builds after validation")
	var before_reads:=int(before.counters.get("paint.texture.runtime_image_lookup",0))
	check(before_reads==1 and int(after.counters.get("paint.texture.runtime_image_lookup",0))==before_reads,"commit performs no second source lookup after cache eviction")
	check(int(after.counters.get("paint.texture.upload_bytes",0))==int(before.counters.get("paint.texture.upload_bytes",0)),"commit performs no second GPU upload after cache eviction")
	plan.clear()
	check(borrowed!=null and borrowed.get_ref()!=null,"final mesh owns the same texture after validation retires")
	if borrowed!=null:
		var same:=false
		for slot in built.mesh.get_surface_count():
			var material:Material=built.mesh.surface_get_material(slot)
			if material is StandardMaterial3D and material.albedo_texture==borrowed.get_ref():same=true
		check(same,"actual final material reuses the validated owner")
	Paint.cache_byte_budget=old_budget;Pixels.profile_enabled=false;Paint.texture_profile_enabled=false
	node.free()
	print("PAINT_VALIDATION_OWNERS ",JSON.stringify({"checks":checks,"failures":failures,"before":before,"after":after}))
	quit(0 if failures.is_empty() else 1)
