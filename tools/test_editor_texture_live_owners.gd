extends SceneTree
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Prepare=preload("res://scripts/world_editor/terrain_texture_preparation.gd")
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
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):folder=arg.trim_prefix("--root=")
	if folder.is_empty() or not Paths.allowed(folder):quit(2);return
	check(DirAccess.make_dir_recursive_absolute(folder)==OK,"isolated source directory")
	var path:=folder.path_join("shared.png")
	var image:=Image.create(32,32,false,Image.FORMAT_RGBA8);image.fill(Color(.3,.4,.8))
	check(image.save_png(path)==OK,"actual source image")
	var key:=Paint.texture_key(path)
	var record:={"terrain_material":{"texture_path":path}}
	var old_budget:=Paint.cache_byte_budget;Paint.cache_byte_budget=0
	Pixels.reset_profile();Pixels.profile_enabled=true;Paint.texture_profile_enabled=true
	# A real material, rather than the LRU or this fixture's local Texture2D,
	# owns the resource after its first publication.
	var owner:=StandardMaterial3D.new();owner.albedo_texture=Paint.texture(record.terrain_material)
	var original:WeakRef=weakref(owner.albedo_texture)
	check(original.get_ref()!=null and not Paint._textures.has(key),"live material retains texture after real zero-budget eviction")
	var checked:={key:true}
	check(Prepare.requests(record,{}).has(key),"fresh load still checks a mutable source even with a live old owner")
	var unnecessary:=0
	for i in 100:
		if not Prepare.requests(record,checked).is_empty():unnecessary+=1
	check(unnecessary==0,"100 later records do not requeue already checked live pixels")
	check(Paint.cache_byte_budget==0 and not Paint._textures.has(key),"planning does not promote weak owners or enlarge the hot cache")
	var before:Dictionary=Pixels.profile_snapshot("")
	var reused:Texture2D=Paint.texture(record.terrain_material)
	var after:Dictionary=Pixels.profile_snapshot("")
	check(reused==original.get_ref(),"actual consumer uses the same material-owned texture")
	check(after.counters.get("paint.texture.runtime_image_lookup",0)==before.counters.get("paint.texture.runtime_image_lookup",0) and after.counters.get("paint.texture.upload_bytes",0)==before.counters.get("paint.texture.upload_bytes",0),"reuse adds neither a source read nor an upload")
	reused=null
	var with_normal:={"terrain_material":{"texture_path":path,"normal_path":path,"normal_format":"directx"}}
	var normal_key:=Paint.texture_key(path,true,true)
	var normal_requests:=Prepare.requests(with_normal,checked)
	check(normal_requests.size()==1 and normal_requests.has(normal_key),"color owner cannot satisfy a distinct flipped normal role")
	var replacement:=Image.create(32,32,false,Image.FORMAT_RGBA8)
	replacement.set_meta("runtime_source_sha256","different_generation")
	Paint.prepared_images={key:replacement}
	check(Prepare.requests(record,checked).has(key),"a conflicting prepared source generation cannot reuse old pixels")
	replacement.set_meta("runtime_source_sha256",owner.albedo_texture.get_meta("runtime_source_sha256"))
	replacement.set_meta("runtime_texture_representation","different_representation")
	check(Prepare.requests(record,checked).has(key),"a conflicting DDS/source representation cannot reuse old pixels")
	Paint.prepared_images={}
	owner.albedo_texture=null;owner=null
	check(original.get_ref()==null,"planning keeps no hidden strong reference after the last material releases")
	check(Prepare.requests(record,checked).has(key),"expired owner requires a real new preparation")
	Paint.cache_byte_budget=old_budget;Pixels.profile_enabled=false;Paint.texture_profile_enabled=false
	print("EDITOR_TEXTURE_LIVE_OWNERS ",JSON.stringify({"checks":checks,"failures":failures,"unnecessary_requests":unnecessary,"before":before,"after":after}))
	quit(0 if failures.is_empty() else 1)
