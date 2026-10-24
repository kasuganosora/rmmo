extends "res://tools/profile_white_native_asset.gd"
## Native files contain geometry only. Runtime material binding must preserve
## culling and reuse the existing CPU/GPU mesh instead of uploading it again.
const Native=preload("res://scripts/world3d/white_native_asset_cache.gd")
func _find_materials(value:Variant,seen:Dictionary,materials:Dictionary,path:String="root")->void:
	if value is Material:materials[value.get_instance_id()]=path
	if value is Resource:
		if seen.has(value.get_instance_id()):return
		seen[value.get_instance_id()]=true
		for info:Dictionary in value.get_property_list():
			if int(info.usage)&PROPERTY_USAGE_STORAGE:_find_materials(value.get(info.name),seen,materials,path+"."+str(info.name))
	elif value is Dictionary:
		for key:Variant in value:
			_find_materials(key,seen,materials,path+".key")
			_find_materials(value[key],seen,materials,path+"."+str(key))
	elif value is Array:
		for i:int in value.size():_find_materials(value[i],seen,materials,path+"[%d]"%i)

func _check_cull_roundtrip(folder:String)->void:
	var mesh:=ArrayMesh.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	for cull:int in [BaseMaterial3D.CULL_BACK,BaseMaterial3D.CULL_FRONT,BaseMaterial3D.CULL_DISABLED]:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(cull,Controls.white_material(cull))
	var original:Mesh=Cpu.capture(mesh);var faces:PackedVector3Array=original.collision_faces()
	Native._store_geometry(mesh)
	var path:=folder.path_join("white_native42_culls_%d.res"%OS.get_process_id())
	check(ResourceSaver.save(mesh,path,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)==OK,"three cull modes saved without material objects")
	var restored:ArrayMesh=ResourceLoader.load(path,"ArrayMesh",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var seen:Dictionary={};var materials:Dictionary={};_find_materials(restored,seen,materials)
	check(materials.is_empty(),"cull fixture has no serialized materials")
	Native._bind_geometry(restored)
	var cpu:Mesh=Cpu.capture(restored);var correct:=true
	for cull:int in 3:correct=correct and restored.surface_get_material(cull)==Controls.white_material(cull)
	check(correct and cpu.surfaces==original.surfaces and cpu.lods==original.lods and cpu.collision_faces()==faces,"back/front/double-sided semantics and exact CPU geometry survive roundtrip")
	var spec:Dictionary={"mesh":cpu};Controls.whiten_spec(spec)
	check(spec.mesh==cpu and cpu.restore()==restored,"three cull modes share runtime owners without a second GPU upload")
	Drainer.synchronize_transfer()

func _check_town()->Array:
	var directory:=preload("res://scripts/world3d/map_dependency_index.gd").read("D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf","D:/code/rmmo_runtime","",33554432,67108864,4,true)
	check(directory.ok,"town model directory opens")
	var rows:Array=[]
	for source:String in directory.models:
		var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Native.index_path(source,"D:/code/rmmo_runtime")))
		var packed:PackedScene=ResourceLoader.load(Native.directory("D:/code/rmmo_runtime").path_join(manifest.payload_sha+".scn"),"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var seen:Dictionary={};var materials:Dictionary={};_find_materials(packed,seen,materials)
		check(materials.is_empty(),"town native product has zero material resources: "+source.get_file())
		if not materials.is_empty():print("RETAINED_MATERIALS ",materials.values())
		rows.append({"source":source,"serialized_materials":materials.size(),"material_paths":materials.values(),"bytes":manifest.bytes,"payload_sha":manifest.payload_sha})
		Drainer.synchronize_transfer();packed=null
	return rows

func run()->void:
	var output:="";var expect_duplicate:=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg=="--expect-duplicate":expect_duplicate=true
	if output.is_empty():quit(2);return
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	var sha:=FileAccess.get_sha256(SOURCE)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Native.index_path(SOURCE,"D:/code/rmmo_runtime")))
	var serialized:PackedScene=ResourceLoader.load(Native.directory("D:/code/rmmo_runtime").path_join(manifest.payload_sha+".scn"),"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var serialized_materials:Dictionary={};var serialized_seen:Dictionary={}
	_find_materials(serialized,serialized_seen,serialized_materials)
	var material_count:=serialized_materials.size()
	check(material_count>0 if "--expect-materials" in OS.get_cmdline_user_args() else material_count==0,"serialized native file has expected material resource count")
	Drainer.synchronize_transfer();serialized=null
	var hit:=Native.read(SOURCE,sha,"D:/code/rmmo_runtime",true)
	check(hit.get("hit",false),"native product hit")
	if not hit.get("hit",false):print(hit);quit(1);return
	var scene:Node=Compiled.instantiate(hit.packed)
	var visuals:=scene.find_children("*","MeshInstance3D",true,false)
	var seen:Dictionary={};var duplicates:=0;var projections:=0;var retained:Array[Mesh]=[]
	var began:=Time.get_ticks_usec()
	for visual:MeshInstance3D in visuals:
		var mesh:Mesh=visual.mesh
		if seen.has(mesh.get_instance_id()):continue
		seen[mesh.get_instance_id()]=true
		var original:Mesh=Cpu.capture(mesh)
		var spec:Dictionary={"mesh":original}
		Controls.whiten_spec(spec)
		if spec.mesh!=original:projections+=1
		var restored:Mesh=spec.mesh.restore();retained.append(restored)
		if restored!=mesh:duplicates+=1
	var elapsed:=Time.get_ticks_usec()-began
	check(duplicates==seen.size() if expect_duplicate else duplicates==0,"native GPU reuse matches expected route")
	check(projections==seen.size() if expect_duplicate else projections==0,"native CPU material reuse matches expected route")
	var report:={"source_sha":sha,"serialized_materials":material_count,"unique_meshes":seen.size(),"duplicate_gpu_meshes":duplicates,"cpu_material_projections":projections,"restore_us":elapsed,"fingerprint":fingerprint(scene)}
	# A historical renderer/compiler fingerprint is not the current source
	# oracle. Compare a fresh GLB through the same current import pipeline;
	# retain the old fingerprint difference as evidence without overwriting it.
	var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FOLDER.path_join("expected.json")))
	report.historical_differences=[]
	for key:String in report.fingerprint:
		if not (int(expected[key])==report.fingerprint[key] if report.fingerprint[key] is int else expected[key]==report.fingerprint[key]):report.historical_differences.append(key)
	var document:=GLTFDocument.new();var state:=GLTFState.new();Controls.configure_gltf(state)
	check(document.append_from_file(SOURCE,state,0,SOURCE.get_base_dir())==OK,"current GLB reference parses")
	var raw:Node=Io.generate_scene(document,state,true)
	check(raw!=null,"current GLB reference instantiates")
	if raw==null:quit(1);return
	check(Capture.capture(raw,true).error.is_empty(),"current GLB reference CPU capture succeeds")
	report.current_source_fingerprint=fingerprint(raw)
	check(report.fingerprint==report.current_source_fingerprint,"exact structure, geometry, LODs and collision match current GLB")
	Drainer.dispose_scene(raw);raw=null;Drainer.synchronize_transfer();document=null;state=null
	Drainer.dispose_scene(scene);scene=null;Drainer.synchronize_transfer();hit.clear();retained.clear()
	_check_cull_roundtrip(output.get_base_dir())
	if "--town" in OS.get_cmdline_user_args():report.town=_check_town()
	check(FileAccess.get_sha256(SOURCE)==sha,"formal source unchanged")
	report.failures=failures;FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WHITE_NATIVE_GPU_REUSE meshes=",report.unique_meshes," duplicates=",duplicates," restore_us=",elapsed," failures=",failures)
	quit(1 if failures else 0)
