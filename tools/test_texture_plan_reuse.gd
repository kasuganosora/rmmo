extends SceneTree
const Base=preload("res://tools/test_prefab_texture_preparation.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
func reads()->int:return int(Prep.Pixels.profile_snapshot().counters.get("texture.prefab_source_header_reads",0))
func run()->void:
	var fixture:=Base.new();fixture.files=Base.Files.new();fixture.files.content_root=Prep.Paths.external_root()
	fixture.files.folder=Prep.Paths.cache_directory("texture_plan_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(fixture.files.folder)
	var path:String=fixture.files.folder.path_join("shared.png")
	var image:=Image.create(19,13,false,Image.FORMAT_RGB8);image.fill(Color(.2,.4,.6));image.save_png(path)
	var material:Dictionary={"texture_path":path,"normal_path":path,"normal_format":"opengl"}
	var sources:=Prep.sources({"surface_material":material})
	# Build the same already-derived source table supplied by the map index.
	if sources.is_empty():sources={path:[path,false,false],path+"|normal":[path,false,true]}
	var queue:=Deferred.new();queue._reference_root=fixture.files.content_root;queue._reference_index={"rows":[{"prefab_textures":sources}]}
	var requests:Array=[{"record_index":0}]
	var original:=Prep.estimate(sources,fixture.files.content_root)
	Prep.Pixels.profile_enabled=true;Prep.Pixels.reset_profile()
	for i:int in 12:
		queue._demand_revision+=1
		var plan:Dictionary=queue._prefab_texture_plan({"path":"reference:"+str(i)},requests)
		check(plan==original,"reused source plan retains exact row and byte reservation")
	check(reads()==2,"twelve changed demands open each source-role header once, not twelve times")
	# Explicit editor source refresh invalidates even the same demand/path.
	var replacement:=Image.create(31,17,false,Image.FORMAT_RGB8);replacement.fill(Color.RED);replacement.save_png(path)
	Paint.refresh_sources()
	var refreshed:Dictionary=queue._prefab_texture_plan({"path":"reference:11"},requests)
	check(refreshed.get("rows",{}).get(path,{}).get("width")==31,"explicit source refresh reopens metadata for the same demand")
	check(reads()==4,"refresh observes each changed source role once")
	# Strict diagnostics retain mutable-file observations instead of trusting a
	# package-operation catalogue; no stale entry survives a policy change.
	Prep.Pixels.Policy.verify_packages=true;Prep.Pixels.reset_profile()
	for i:int in 3:queue._demand_revision+=1;queue._prefab_texture_plan({"path":"strict:"+str(i)},requests)
	check(reads()==6,"strict source diagnostics do not reuse mounted metadata")
	Prep.Pixels.Policy.verify_packages=false
	preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures=true;Prep.Pixels.reset_profile()
	var white:Dictionary=queue._prefab_texture_plan({"path":"white"},requests)
	check(white.is_empty() and reads()==0,"white stage opens no texture header")
	preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures=false
	Prep.Pixels.profile_enabled=false;queue.free()
	DirAccess.remove_absolute(path);fixture.files.free();fixture.free()
	print("TEXTURE_PLAN_REUSE failures=",failures);quit(1 if failures else 0)
