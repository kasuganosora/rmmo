extends RefCounted
## Offline writer/version contract for material-free native geometry products.
## Runtime scheduling and diagnostics do not change serialized product bytes.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const META:=&"_rmmo_native_cpu_geometry_v1"
# Compatibility belongs to the exported product, not the runtime source text.
# Bump for changed serialized geometry/LOD/faces/key/culling or node semantics.
# Scheduling, retirement and profiler edits do not require model regeneration.
const PRODUCT_REVISION:=2
static var _generator:=""
static var _generator_mutex:=Mutex.new()
static func active()->bool:return Controls.native_geometry_only or (Controls.white_materials and Controls.discard_map_textures)
static func directory(root:String)->String:return root.path_join("cache/world3d/white_native_assets_v1")
static func generator()->String:
	_generator_mutex.lock()
	if not _generator.is_empty():
		var cached:=_generator;_generator_mutex.unlock();return cached
	# Keep the engine revision as a conservative native/import compatibility gate.
	var inputs:Array=[PRODUCT_REVISION,Engine.get_version_info().hash,str(META)]
	_generator=str(inputs).sha256_text()
	var result:=_generator;_generator_mutex.unlock();return result
static func exporter_provenance()->Dictionary:
	# Export-time audit only; these hashes never gate a runtime native read.
	var sources:Dictionary={}
	for name:String in ["white_native_asset_writer","gltf_map_io","runtime_probe_controls","model_lod_preparation","ground_cpu_mesh","static_mesh_cpu_preparation","prefab_face_arrays","importer_lod_hint"]:
		sources[name]=FileAccess.get_sha256("res://scripts/world3d/"+name+".gd")
	return {"product_revision":PRODUCT_REVISION,"engine_revision":Engine.get_version_info().hash,"sources":sources}
static func index_path(path:String,root:String)->String:return directory(root).path_join(path.replace("\\","/").simplify_path().sha256_text()+".json")

static func _store_geometry(mesh:ArrayMesh)->void:
	var cpu:Mesh=Cpu.capture(mesh);var culls:=PackedInt32Array()
	for material:Material in cpu.materials:
		culls.append(material.cull_mode if material is BaseMaterial3D else BaseMaterial3D.CULL_BACK)
	mesh.set_meta(META,{"surfaces":cpu.surfaces,"lods":cpu.lods,"faces":cpu.collision_faces(),"culls":culls,"geometry_key":cpu.geometry_key()})
	# Keep surface slots and culling semantics, but no material Resource in the
	# native file. This also removes material deserialization/replacement/retirement.
	for slot:int in mesh.get_surface_count():mesh.surface_set_material(slot,null)
	if mesh.has_meta("ground_cpu_cache"):mesh.remove_meta("ground_cpu_cache")
	if mesh.has_meta(preload("res://scripts/world3d/importer_lod_hint.gd").META):mesh.remove_meta(preload("res://scripts/world3d/importer_lod_hint.gd").META)

static func build(path:String,root:String)->Dictionary:
	# The staged runtime mode may read this product alongside map textures, but
	# must not change the established offline material-free export semantics.
	assert(Thread.is_main_thread() and Controls.white_materials and Controls.discard_map_textures)
	if not Paths.allowed(path,root):return {"ok":false,"reason":"source_path"}
	var began:=Time.get_ticks_usec();var sha:=FileAccess.get_sha256(path)
	var manifest:=preload("res://scripts/world3d/asset_bounds_manifest.gd").read(path)
	if not manifest.get("known",false):return {"ok":false,"reason":"unsupported_static_model"}
	var document:=GLTFDocument.new();var state:=GLTFState.new();Controls.configure_gltf(state)
	var error:=document.append_from_file(path,state,0,path.get_base_dir())
	if error!=OK:return {"ok":false,"reason":"parse","error":error}
	var scene:Node=load("res://scripts/world3d/gltf_map_io.gd").generate_scene(document,state,true)
	if scene==null:return {"ok":false,"reason":"generate"}
	var captured:=preload("res://scripts/world3d/static_mesh_cpu_preparation.gd").capture(scene,true)
	if not captured.error.is_empty():scene.free();return {"ok":false,"reason":captured.error}
	var nodes:Array=[scene];var seen:Dictionary={};var surfaces:=0
	while not nodes.is_empty():
		var node:Node=nodes.pop_back()
		for child:Node in node.get_children():child.owner=scene;nodes.append(child)
		if not node is MeshInstance3D or not node.mesh is ArrayMesh or seen.has(node.mesh.get_instance_id()):continue
		var mesh:ArrayMesh=node.mesh;seen[mesh.get_instance_id()]=true
		surfaces+=mesh.get_surface_count();_store_geometry(mesh)
	var packed:=PackedScene.new();error=packed.pack(scene)
	if error==OK and not load("res://scripts/world3d/compiled_asset_cache.gd")._valid_packed(packed):error=ERR_INVALID_DATA
	var folder:=directory(root);DirAccess.make_dir_recursive_absolute(folder)
	var temporary:=folder.path_join("build_%d_%d.scn"%[OS.get_process_id(),Time.get_ticks_usec()])
	if error==OK:error=ResourceSaver.save(packed,temporary,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_scene(scene)
	preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer();packed=null;scene=null;state=null;document=null
	if error!=OK:return {"ok":false,"reason":"save","error":error}
	if not ResourceLoader.get_dependencies(temporary).is_empty() or FileAccess.get_sha256(path)!=sha:return {"ok":false,"reason":"source_or_dependency_changed"}
	var payload_sha:=FileAccess.get_sha256(temporary);var product:=folder.path_join(payload_sha+".scn")
	var bytes:=FileAccess.open(temporary,FileAccess.READ).get_length()
	if FileAccess.file_exists(product):DirAccess.remove_absolute(temporary)
	else:error=DirAccess.rename_absolute(temporary,product)
	if error!=OK:return {"ok":false,"reason":"publish_product","error":error}
	var index:=index_path(path,root);var staged:=index+".%d.tmp"%OS.get_process_id()
	var info:={"source_sha":sha,"payload_sha":payload_sha,"generator":generator(),"bytes":bytes,"meshes":seen.size(),"surfaces":surfaces,"cpu_bytes":captured.capture_bytes,"face_bytes":captured.face_bytes,"exporter_provenance":exporter_provenance()}
	var file:=FileAccess.open(staged,FileAccess.WRITE)
	if file==null:return {"ok":false,"reason":"manifest_write"}
	file.store_string(JSON.stringify(info));file.flush();error=file.get_error();file.close()
	if error==OK:error=preload("res://scripts/world3d/atomic_file.gd").publish(staged,index)
	return {"ok":error==OK,"error":error,"product":product,"manifest":info,"elapsed_us":Time.get_ticks_usec()-began}
