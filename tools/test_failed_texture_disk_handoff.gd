extends SceneTree
## Explicit failed-preparation invalidation, including the trusted disk layer.
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Handoff=preload("res://scripts/world_editor/terrain_texture_preparation.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func write_image(path:String,color:Color)->void:
	var image:=Image.create(8,8,false,Image.FORMAT_RGBA8);image.fill(color)
	check(image.save_png(path)==OK,"write isolated repair fixture")
func _initialize()->void:run.call_deferred()
func run()->void:
	var folder:=Paths.cache_directory("failed_texture_disk_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("repair.png");var other:=folder.path_join("unrelated.png")
	var previous_policy:bool=Pixels.Policy.verify_packages
	Pixels.Policy.verify_packages=false;Pixels.profile_enabled=true;Pixels.reset_profile()
	write_image(path,Color.RED);write_image(other,Color.GREEN)
	var original:=Pixels.image(path,false);var flipped:=Pixels.image(path,true);var unrelated:=Pixels.image(other,false)
	var straight_cache:=Pixels.cache_path(path,false);var flipped_cache:=Pixels.cache_path(path,true);var other_cache:=Pixels.cache_path(other,false)
	check(FileAccess.file_exists(straight_cache) and FileAccess.file_exists(flipped_cache) and FileAccess.file_exists(other_cache),"all three trusted disk products exist")
	write_image(path,Color.BLUE)
	var key:=Paint.texture_key(path,true,true)
	var previous:=Handoff.install({"images":{},"failed":[key]})
	check(not FileAccess.file_exists(flipped_cache),"failed normal variant revokes disk product")
	check(FileAccess.file_exists(straight_cache) and FileAccess.file_exists(other_cache),"unaffected variants and sources keep their caches")
	var repaired_flip:=Pixels.image(path,true)
	check(repaired_flip.get_pixel(0,0).b>.9 and repaired_flip.get_pixel(0,0).g>.9,"same-path normal repair decodes new pixels and preserves flip")
	check(original.get_pixel(0,0).r>.9 and flipped.get_pixel(0,0).r>.9,"existing CPU owners retain original pixels")
	Handoff.restore(previous,[Paint.texture_key(path,false,false)])
	check(not FileAccess.file_exists(straight_cache),"failed fallback restore revokes disk product")
	var repaired:=Pixels.image(path,false)
	check(repaired.get_pixel(0,0).b>.9 and repaired.get_pixel(0,0).r<.1,"same-path color repair does not reload stale pixels")
	var warm:=Pixels.image(path,false)
	check(warm.get_data()==repaired.get_data() and FileAccess.file_exists(straight_cache),"successful repair rebuilds reusable derived cache")
	check(FileAccess.file_exists(other_cache) and unrelated.get_pixel(0,0).g>.9,"unrelated source remains resident")
	check(not Pixels.profile_snapshot().stages.has("texture.image.source_sha"),"explicit invalidation adds no per-load source checksum")
	for target:String in [straight_cache,flipped_cache,other_cache,path,other]:
		if FileAccess.file_exists(target):DirAccess.remove_absolute(target)
	DirAccess.remove_absolute(folder);Pixels.Policy.verify_packages=previous_policy;Pixels.profile_enabled=false
	print("FAILED_TEXTURE_DISK_HANDOFF ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
