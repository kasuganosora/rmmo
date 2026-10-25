extends SceneTree
## A diagnostic white load must not poison the reusable author dependency index.
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const EditorPrep=preload("res://scripts/world_editor/terrain_texture_preparation.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Files=preload("res://tools/test_map_dependency_index.gd")
var failures:Array[String]=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var files:=Files.new();files.content_root=Prep.Paths.external_root();files.folder=Prep.Paths.cache_directory("texture_modes_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(files.folder)
	var path:String=files.folder.path_join("same_source.png")
	var image:=Image.create(16,8,false,Image.FORMAT_RGBA8);image.fill(Color(.3,.5,.8));image.save_png(path);files.created.append(path)
	var material:={"name":"mode dependency","color":[1,1,1,1],"roughness":.8,"texture_path":path,"normal_path":path,"normal_format":"opengl"}
	var record:Dictionary=files.box("mode_fixture",0);record.terrain_material=material
	var declared:=Prep.sources(record)
	check(declared.size()==2 and declared[path+"|normal"]==[path,false,true],"ordinary dependency identity carries the explicit normal role")
	var source:Dictionary=files.fixture("modes",[record])
	Controls.enable_white_materials();Controls.discard_map_textures=true
	check(Prep.sources(record)==declared,"white and textured modes enumerate identical authored dependencies")
	var built:=Index.build(source.path,files.content_root,[record])
	check(built.ok,"white mode can build a tiny reusable dependency directory")
	var white_plan:=Prep.estimate(declared,files.content_root)
	check(white_plan.rows.is_empty() and white_plan.estimated_bytes==0 and white_plan.output_bytes==0,"white admission performs no texture preparation")
	var packet:=Prep.prepare(declared,white_plan,files.content_root)
	check(packet.error.is_empty() and packet.images.is_empty() and packet.profile.decoded==0 and packet.profile.source_sha_reads==0,"white producer decodes and reads no textures")
	check(EditorPrep.requests(record,{}).is_empty(),"white editor schedules no image or DDS work")
	Paint.texture_profile_enabled=true;Paint.reset_profile()
	check(Paint.make_material(material)!=null and Paint.profile_snapshot().counters.is_empty(),"white material performs no texture lookup or upload")
	Paint.texture_profile_enabled=false;Controls.white_materials=false;Controls.discard_map_textures=false
	var reopened:=Index.read(source.path,files.content_root)
	check(reopened.ok and reopened.rows[0].prefab_textures==declared,"textured mode reopens white-built directory with complete three-element descriptors")
	for created:String in files.created:
		if FileAccess.file_exists(created):DirAccess.remove_absolute(created)
	DirAccess.remove_absolute(source.path+".resources");DirAccess.remove_absolute(files.folder);files.free()
	print("TEXTURE_DEPENDENCY_MODES ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
