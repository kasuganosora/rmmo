extends SceneTree
## Isolated boundary fixtures: real SCN readback, sparse padding, no GLB source.
## Padding crosses the storage gate without allocating a gigabyte of geometry.
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Preparation=preload("res://scripts/world3d/compiled_asset_preparation.gd")
const Ownership=preload("res://scripts/world_editor/prepared_model_ownership.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Manifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Prefetch=preload("res://scripts/world3d/target_scene_prefetch.gd")
const COUNT=65537
var passed:=0
var failures:=0

func check(ok:bool,label:String)->void:
	if ok:passed+=1;print("PASS: ",label)
	else:failures+=1;printerr("FAIL: ",label)

func _initialize()->void:run.call_deferred()

func base_scene()->PackedScene:
	var node:=Node3D.new();node.name="BoundaryRoot"
	var packed:=PackedScene.new();packed.pack(node);node.free()
	return packed

func many_nodes()->PackedScene:
	var packed:=base_scene();var bundle:Dictionary=packed.get("_bundled")
	var names:PackedStringArray=bundle.names
	var nodes:PackedInt32Array=bundle.nodes
	assert(nodes.size()==7)
	var type_index:=nodes[2]
	for i:int in range(1,COUNT):
		var name_index:=names.size();names.append("part_%d"%i)
		nodes.append_array(PackedInt32Array([0,0,type_index,name_index,-1,0,0]))
	bundle.names=names;bundle.nodes=nodes;bundle.node_count=COUNT
	packed.set("_bundled",bundle)
	return packed

func source_bounds()->Dictionary:
	var nodes:Array=[];nodes.resize(COUNT);nodes.fill({})
	var children:Array=[];children.resize(COUNT-1)
	for i:int in COUNT-1:children[i]=i+1
	nodes[0]={"children":children};nodes[COUNT-1]={"mesh":0}
	return {"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":nodes,"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}],"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[-1,0,-2],"max":[1,4,2]}],"bufferViews":[{"buffer":0,"byteLength":36}],"buffers":[{"byteLength":36}]}

func run()->void:
	var folder:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture-root="):folder=arg.trim_prefix("--fixture-root=")
	if folder.is_empty() or not folder.contains("/review_artifacts/"):
		check(false,"external isolated fixture root required");quit(1);return
	if "--seed" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(folder)
		check(ResourceSaver.save(base_scene(),folder.path_join("padded.scn"))==OK,"seed actual uncompressed SCN")
		quit(1 if failures else 0);return
	var manager:=root.get_node("AssetManager");var old_root:String=manager.content_root_override
	manager.content_root_override=folder
	for invalid:Variant in [0,-1,1.5,NAN,INF,"1024",9007199254740992]:
		check(not Compiled.valid_payload_size(invalid),"invalid or inexact file length rejected: "+str(invalid))
	check(Compiled.valid_payload_size(1024.0) and Compiled.valid_payload_size(1024*1024*1024+1),"exact JSON and large integer lengths remain valid")
	var source:=folder.path_join("asset/model.glb")
	var index:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Compiled.index_path(source,folder)))
	check(int(index.bytes)>1024*1024*1024 and not FileAccess.file_exists(source),"fixture crosses 1 GiB with no import source")
	var candidate:=Footprint.candidate(source,folder,"",true)
	check(not candidate.is_empty(),"published native candidate accepts actual file above 1 GiB")
	# Exercise the reader even on the red path where the old candidate rejects it.
	var fixed:Dictionary=index.duplicate();fixed.bytes=int(index.bytes)
	fixed.source_path=source;fixed.product=Compiled.directory(folder).path_join(str(index.payload_sha)+".scn")
	fixed.estimated_bytes=4*1024*1024*1024;fixed.resident_bytes=fixed.estimated_bytes
	var packet:=Preparation.read(source,fixed,folder,Callable(),false,false,"",true)
	check(packet.get("packed") is PackedScene and packet.get("error",FAILED)==OK and not packet.get("fallback_required",false),"strict native reader loads the padded SCN without GLB")
	if packet.get("packed") is PackedScene:
		var scene:Node=packet.packed.instantiate()
		check(scene is Node3D and scene.name=="BoundaryRoot","large file readback instantiates its actual scene")
		scene.free()
		check(Ownership._validate_identity(fixed,packet,fixed.estimated_bytes).is_empty(),"ownership admission uses the supplied envelope instead of a disk-size quota")
	else:check(false,"large file readback instantiates its actual scene")
	check(Prefetch._native_file_identity(fixed.product,{"native_product":true,"sha256":index.payload_sha,"length":fixed.bytes},folder),"prefetch recognizes the same large native product")
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(packet)
	var packed:=many_nodes()
	check(packed.get_state().get_node_count()==COUNT,"fixture represents 65537 scene nodes")
	check(Compiled._valid_packed(packed),"native schema accepts more than 65536 supported nodes")
	check(Ownership._collect_graph(packed).get("ok",false),"ownership graph accepts the complete supported scene")
	check(Deferred._reuse_face_offer(packed).get("ok",false),"geometry reuse does not discard an already prepared scene by node count")
	var path:=folder.path_join("many_nodes.scn")
	check(ResourceSaver.save(packed,path,ResourceSaver.FLAG_COMPRESS)==OK,"engine saves 65537 nodes")
	var loaded:PackedScene=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(loaded!=null and loaded.get_state().get_node_count()==COUNT,"engine reads back every node")
	if loaded!=null:
		var scene:Node=loaded.instantiate()
		check(scene.get_child_count()==COUNT-1 and scene.get_child(COUNT-2).name=="part_%d"%(COUNT-1),"actual native instance retains first-to-last node membership")
		scene.free()
	var bounds:=Manifest.from_json(source_bounds(),36)
	check(bounds.get("known",false) and bounds.get("mesh_nodes",[]).size()==1,"explicit import bounds include the final mesh above the old node threshold")
	var source_json:=JSON.stringify(source_bounds()).to_utf8_buffer()
	while source_json.size()%4:source_json.append(32)
	var import_source:=folder.path_join("explicit_import_bounds.glb")
	var file:=FileAccess.open(import_source,FileAccess.WRITE)
	file.store_32(0x46546c67);file.store_32(2);file.store_32(source_json.size()+64)
	file.store_32(source_json.size());file.store_32(0x4e4f534a);file.store_buffer(source_json)
	file.store_32(36);file.store_32(0x004e4942)
	file.store_buffer(PackedFloat32Array([-1,0,-2,1,4,2,0,1,0]).to_byte_array());file.close()
	var disk_bounds:=Manifest.read(import_source)
	check(disk_bounds.get("known",false) and disk_bounds.get("mesh_nodes",[]).size()==1 and disk_bounds.get("local_bounds")==bounds.get("local_bounds"),"real GLB bounds reader covers 65537 nodes within its JSON byte contract")
	manager.content_root_override=old_root
	print("NATIVE_PRODUCT_BOUNDARIES passed=",passed," failures=",failures)
	quit(1 if failures else 0)
