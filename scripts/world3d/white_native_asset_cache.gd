extends RefCounted
## Offline white-model product. GPU storage and exact CPU geometry share one
## native resource file, with no serialized materials or textures. Runtime binds
## shared materials separately; no GLTF parsing or GPU readback on hit.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Writer=preload("res://scripts/world3d/white_native_asset_writer.gd")
const META=Writer.META
static var enabled:=true
static func active()->bool:return Writer.active()
static func directory(root:String)->String:return Writer.directory(root)
static func generator()->String:return Writer.generator()
static func index_path(path:String,root:String)->String:return Writer.index_path(path,root)
static func read(path:String,digest:String,root:String,trusted:bool)->Dictionary:
	var started:=Time.get_ticks_usec()
	if not enabled:return {"hit":false,"reason":"white_native_disabled"}
	if root.is_empty() or not Paths.asset_key_allowed(path,root):return {"hit":false,"reason":"white_native_source"}
	if not trusted and (not Paths.allowed(path,root) or not FileAccess.file_exists(path)):return {"hit":false,"reason":"white_native_source"}
	var index:=index_path(path,root)
	if not Paths.allowed(index,directory(root)):return {"hit":false,"reason":"white_native_path"}
	var file:=FileAccess.open(index,FileAccess.READ)
	if file==null or file.get_length()>8192:return {"hit":false,"reason":"white_native_absent"}
	var info:Variant=JSON.parse_string(file.get_as_text());file.close()
	if not info is Dictionary or info.get("generator")!=generator():return {"hit":false,"reason":"white_native_version"}
	if not info.get("payload_sha") is String or info.payload_sha.length()!=64 or not info.payload_sha.is_valid_hex_number(false):return {"hit":false,"reason":"white_native_identity"}
	if not info.get("source_sha") is String or info.source_sha.length()!=64 or not info.source_sha.is_valid_hex_number(false):return {"hit":false,"reason":"white_native_identity"}
	# The trusted native index owns identity. Never open/hash an optional GLB
	# merely because its logical key has a human-readable filename.
	var identity:String=info.source_sha if trusted else FileAccess.get_sha256(path)
	if not digest.is_empty() and digest!=identity:return {"hit":false,"reason":"white_native_source_changed"}
	var key:=path.get_file().get_basename()
	if trusted and key.length()==64 and key.is_valid_hex_number(false) and key!=identity:return {"hit":false,"reason":"white_native_source_changed"}
	if identity!=info.get("source_sha"):return {"hit":false,"reason":"white_native_source_changed"}
	var product:=directory(root).path_join(info.payload_sha+".scn")
	if not Paths.allowed(product,directory(root)):return {"hit":false,"reason":"white_native_product_path"}
	file=FileAccess.open(product,FileAccess.READ)
	if file==null or file.get_length()!=int(info.get("bytes",0)):return {"hit":false,"reason":"white_native_size"}
	file.close()
	# Authored package products are trusted at runtime; checksum authentication
	# remains available only through the explicit diagnostic read.
	if not trusted and FileAccess.get_sha256(product)!=info.payload_sha:return {"hit":false,"reason":"white_native_checksum"}
	var phase:=Time.get_ticks_usec()
	var loaded:Resource=ResourceLoader.load(product,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	preload("res://scripts/world3d/load_trace.gd").elapsed("white_native.read",phase,{"path":path})
	if not loaded is PackedScene:return {"hit":false,"reason":"white_native_type","retained_resources":[loaded] if loaded!=null else []}
	# The offline builder checks the closed resource schema once. Its immutable,
	# native product owns these arrays; never re-read GPU buffers to
	# validate the same resource properties on every runtime load.
	phase=Time.get_ticks_usec()
	var state:SceneState=loaded.get_state();var seen:Dictionary={}
	for i:int in state.get_node_count():
		for j:int in state.get_node_property_count(i):
			if state.get_node_property_name(i,j)!=&"mesh":continue
			var mesh:Variant=state.get_node_property_value(i,j)
			if not mesh is ArrayMesh or seen.has(mesh.get_instance_id()):continue
			seen[mesh.get_instance_id()]=true
			if not mesh.has_meta(META):return {"hit":false,"reason":"white_native_cpu_missing","retained_resources":[loaded]}
			_bind_geometry(mesh)
	preload("res://scripts/world3d/load_trace.gd").elapsed("white_native.bind_cpu",phase,{"meshes":seen.size()})
	if not trusted and FileAccess.get_sha256(path)!=identity:return {"hit":false,"reason":"white_native_source_changed","retained_resources":[loaded]}
	loaded.set_meta("compiled_asset_validated",true);loaded.set_meta("white_native_geometry",true)
	if preload("res://scripts/world3d/asset_spec_template.gd").enabled:
		var description:=preload("res://scripts/world3d/asset_spec_template.gd").compile(loaded)
		if not description.is_empty():loaded.set_meta(preload("res://scripts/world3d/asset_spec_template.gd").META,description)
	return {"hit":true,"packed":loaded,"source_digest":identity,"elapsed_us":Time.get_ticks_usec()-started,"bytes":int(info.bytes),"white_native":true}

static func _store_geometry(mesh:ArrayMesh)->void:Writer._store_geometry(mesh)

static func _bind_geometry(mesh:ArrayMesh)->void:
	var data:Dictionary=mesh.get_meta(META)
	# The file is geometry-only. Bind canonical process-owned materials before
	# the CPU owner so later white publication reuses this exact GPU mesh.
	for slot:int in mesh.get_surface_count():mesh.surface_set_material(slot,Controls.white_material(data.culls[slot]))
	var cpu:Mesh=Cpu.remember(mesh,data.surfaces,data.lods);cpu._collision_faces=data.faces
	# The immutable native product already computed this exact surfaces+LOD key.
	# Re-hashing on the first batch used to serialize large meshes on main.
	cpu.set_geometry_key(data.geometry_key)
	mesh.remove_meta(META)

static func build(path:String,root:String)->Dictionary:
	var result:=Writer.build(path,root)
	if not result.get("ok",false):return result
	var metadata:=preload("res://scripts/world3d/white_native_asset_metadata.gd").build(path,root)
	if not metadata.ok:return metadata
	result.metadata=metadata;return result
