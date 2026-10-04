extends SceneTree
const Cache=preload("res://scripts/world3d/map_metadata_cache.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var failed:=0
func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if not ok:failed+=1
func _initialize()->void:call_deferred("run")
func load_map(path:String)->Array:
	var loader:=Loader.new();root.add_child(loader);loader.start(path)
	return await loader.finished
func run()->void:
	var directory:=preload("res://scripts/world3d/map_paths.gd").cache_directory("metadata_test_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	var doc=preload("res://scripts/world3d/world_document.gd").new()
	doc.add_box("ground",Vector3.ZERO,Vector3(4,.2,4))
	var record:Dictionary=doc.records[0]
	var extra:Dictionary={"rmmo_format":"rmmo_gltf_map","rmmo_version":1,"map_ref":"test/cache","rmmo_records":[record]}
	var data:Dictionary={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"extras":extra}]}
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	var first:Array=await load_map(path)
	check(first[0]!=null and not first[0].get_meta("load_profile").metadata_cache_hit,"cold native load builds disposable cache")
	if first[0]!=null:first[0].free()
	var second:Array=await load_map(path)
	check(second[0]!=null and second[0].get_meta("load_profile").metadata_cache_hit,"fresh loader reuses cache with full validation")
	if second[0]!=null:second[0].free()
	record.position[0]=2
	file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	var changed:Array=await load_map(path)
	check(changed[0]!=null and not changed[0].get_meta("load_profile").metadata_cache_hit and changed[0].get_meta("stream_library")[0].position.x==2,"source content edit invalidates cache immediately")
	if changed[0]!=null:changed[0].free()
	file=FileAccess.open(Cache.cache_path(path),FileAccess.WRITE);file.store_string("truncated");file.close()
	var repaired:Array=await load_map(path)
	check(repaired[0]!=null and not repaired[0].get_meta("load_profile").metadata_cache_hit,"corrupt/truncated cache falls back to source")
	if repaired[0]!=null:repaired[0].free()
	var texture_path:=directory.path_join("test.png")
	var image:=Image.create(1,1,false,Image.FORMAT_RGB8);image.fill(Color.WHITE);image.save_png(texture_path)
	record.terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-4.0,"heights":[0.,0.,0.,0.,0.,0.,0.,0.,0.],"holes":[false,false,false,false]}
	record.terrain_material={"name":"test","color":[1,1,1,1],"roughness":1.0,"texture_path":texture_path}
	file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	var textured:Array=await load_map(path)
	check(textured[0]!=null,"external material is validated before caching")
	if textured[0]!=null:textured[0].free()
	DirAccess.remove_absolute(texture_path)
	var missing:Array=await load_map(path)
	check(missing[0]==null,"warm metadata cache cannot bypass missing texture checks")
	var paint_cache:Dictionary={}
	check(Paint.valid({"surface_paint":[]},false,"",paint_cache),"plain paint validation primes operation cache")
	check(not Paint.valid({"surface_paint":[],"water_depth_effect":{}},false,"",paint_cache),"paint cache cannot bypass water constraints")
	check(not Paint.valid({"surface_paint":[],"terrain_regions":{}},false,"",paint_cache),"paint cache cannot bypass terrain constraints")
	check(not Paint.valid({"surface_paint":[{}]},false,"",paint_cache),"changed invalid paint cannot hit previous validation")
	DirAccess.remove_absolute(Cache.cache_path(path))
	print("MAP_METADATA_CACHE_FINISHED failures=",failed)
	quit(1 if failed else 0)
