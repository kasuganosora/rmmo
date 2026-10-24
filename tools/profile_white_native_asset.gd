extends SceneTree
## Offline format experiment. Uses the same source and keeps author assets intact.
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Capture=preload("res://scripts/world3d/static_mesh_cpu_preparation.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const SOURCE="D:/code/rmmo_runtime/packs/default/assets/7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd.glb"
const FOLDER="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/white_native36"
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fingerprint(scene:Node)->Dictionary:
	var structure:Array=[];var geometry:Array=[];var collision:Array=[];var meshes:Dictionary={};var surfaces:=0;var faces:=0;var white:=true
	var stack:Array=[scene]
	while not stack.is_empty():
		var node:Node=stack.pop_front();stack.append_array(node.get_children())
		var row:Array=[str(scene.get_path_to(node)),node.get_class(),node.get_meta("extras",{})]
		if node is Node3D:row.append(node.transform)
		if node is MeshInstance3D:
			var mesh:Mesh=node.mesh;var id:=mesh.get_instance_id()
			if not meshes.has(id):
				meshes[id]=meshes.size();var cpu:Mesh=Cpu.capture(mesh)
				geometry.append([cpu.surfaces,cpu.lods,cpu.bounds])
				collision.append(cpu.collision_faces());surfaces+=mesh.get_surface_count();faces+=cpu.collision_faces().size()
			row.append(meshes[id]);row.append(node.cast_shadow);row.append(node.layers)
			for slot:int in mesh.get_surface_count():
				var material:Material=node.get_active_material(slot)
				white=white and material is StandardMaterial3D and material.albedo_color==Color.WHITE and material.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED and material.albedo_texture==null
				row.append(material.cull_mode)
		structure.append(row)
	check(white,"all native surfaces stay texture-free white")
	var result:={"nodes":structure.size(),"meshes":meshes.size(),"surfaces":surfaces,"face_vertices":faces}
	for entry:Array in [["structure",structure],["geometry",geometry],["collision",collision]]:
		var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(var_to_bytes(entry[1]));result[entry[0]]=hash_.finish().hex_encode()
	return result
func run()->void:
	var mode:="build";var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if not mode in ["build","raw","native","compressed","prepared"] or output.is_empty():quit(2);return
	check(DisplayServer.get_name()!="headless","real GPU on the private desktop")
	DirAccess.make_dir_recursive_absolute(FOLDER)
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	var before:=FileAccess.get_sha256(SOURCE);var report:={"mode":mode,"source_sha":before,"source_bytes":FileAccess.get_file_as_bytes(SOURCE).size()}
	var document:GLTFDocument;var state:GLTFState;var scene:Node;var packed:PackedScene
	var started:=Time.get_ticks_usec();var phase:=started
	if mode in ["build","raw"]:
		document=GLTFDocument.new();state=GLTFState.new();Controls.configure_gltf(state)
		check(document.append_from_file(SOURCE,state,0,SOURCE.get_base_dir())==OK,"raw source parses")
		report.read_us=Time.get_ticks_usec()-phase;phase=Time.get_ticks_usec()
		scene=Io.generate_scene(document,state,true)
		report.instance_us=Time.get_ticks_usec()-phase
	elif mode=="prepared":
		var hit:=preload("res://scripts/world3d/white_native_asset_cache.gd").read(SOURCE,before,"D:/code/rmmo_runtime",true)
		report.read_us=Time.get_ticks_usec()-phase;phase=Time.get_ticks_usec()
		check(hit.get("hit",false),"prepared native product opens")
		if not hit.get("hit",false):print(hit);quit(1);return
		packed=hit.packed;scene=Compiled.instantiate(packed);report.instance_us=Time.get_ticks_usec()-phase
	else:
		var path:=FOLDER.path_join(mode+".scn")
		packed=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		report.read_us=Time.get_ticks_usec()-phase;phase=Time.get_ticks_usec()
		check(packed!=null and Compiled._valid_packed(packed),"native product retains supported closed scene schema")
		report.validation_us=Time.get_ticks_usec()-phase;phase=Time.get_ticks_usec()
		scene=packed.instantiate();report.instance_us=Time.get_ticks_usec()-phase
	check(scene!=null,"private scene instantiated")
	if scene==null:quit(1);return
	if mode=="build":
		phase=Time.get_ticks_usec()
		var nodes:Array=[scene];var seen:Dictionary={}
		while not nodes.is_empty():
			var node:Node=nodes.pop_back();nodes.append_array(node.get_children())
			if node is MeshInstance3D and not seen.has(node.mesh.get_instance_id()):
				seen[node.mesh.get_instance_id()]=true
				if node.mesh.has_meta(preload("res://scripts/world3d/importer_lod_hint.gd").META):node.mesh.remove_meta(preload("res://scripts/world3d/importer_lod_hint.gd").META)
		Compiled._own(scene,scene);packed=PackedScene.new();check(packed.pack(scene)==OK,"native scene packed once offline")
		report.products={}
		for variant:String in ["native","compressed"]:
			var target:=FOLDER.path_join(variant+".scn");var flags:=ResourceSaver.FLAG_BUNDLE_RESOURCES
			if variant=="compressed":flags|=ResourceSaver.FLAG_COMPRESS
			check(ResourceSaver.save(packed,target,flags)==OK,"offline native product saved")
			check(ResourceLoader.get_dependencies(target).is_empty(),"native product has no external resource dependencies")
			report.products[variant]={"bytes":FileAccess.get_file_as_bytes(target).size(),"sha":FileAccess.get_sha256(target)}
		report.offline_pack_save_us=Time.get_ticks_usec()-phase
	phase=Time.get_ticks_usec();report.capture=Capture.capture(scene,true);report.capture_us=Time.get_ticks_usec()-phase
	report.total_us=Time.get_ticks_usec()-started
	check(report.capture.error.is_empty(),"CPU and collision preparation completes")
	report.fingerprint=fingerprint(scene)
	if mode=="build":FileAccess.open(FOLDER.path_join("expected.json"),FileAccess.WRITE).store_string(JSON.stringify(report.fingerprint))
	else:
		var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FOLDER.path_join("expected.json")));var same:=true
		for key:String in report.fingerprint:
			same=same and (int(expected[key])==report.fingerprint[key] if report.fingerprint[key] is int else expected[key]==report.fingerprint[key])
		check(same,"node metadata, poses, exact GPU channels, LODs and collision match the GLB")
	Drainer.dispose_scene(scene);scene=null;Drainer.synchronize_transfer();packed=null;state=null;document=null
	check(FileAccess.get_sha256(SOURCE)==before,"formal source bytes remain unchanged")
	report.failures=failures;FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WHITE_NATIVE_ASSET ",JSON.stringify(report));quit(1 if failures else 0)
