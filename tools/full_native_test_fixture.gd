extends "res://tools/test_asset_bounds_manifest.gd"
const Source=preload("res://scripts/world3d/asset_source_metadata.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const TargetPrefetch=preload("res://scripts/world3d/target_scene_prefetch.gd")
const CrossPrefetch=preload("res://scripts/world3d/cross_map_prefetch.gd")
const DependencyIndex=preload("res://scripts/world3d/map_dependency_index.gd")
const ResourceStore=preload("res://scripts/world3d/map_resource_store.gd")
const Location=preload("res://scripts/world3d/world_location.gd")
const Bridge=preload("res://scripts/world3d/bridge_mesh.gd")
const Fortification=preload("res://scripts/world3d/fortification_art.gd")
class SourceHashTrap extends "res://scripts/world3d/model_source_hashes.gd":
	var calls:=0
	func run(_paths:Array,_root:String,_workers:int=4,_starter:Callable=Callable(),_reader:Callable=Callable())->Dictionary:
		calls+=1
		return {"error":ERR_BUG,"reason":"native route dispatched authoring-source hasher","error_path":"","elapsed_us":0,"signatures":{}}
var created:Array[String]=[]
var samples:Array[Dictionary]=[]
var directory:=""
var gpu:=false


## Shared full-native integration fixture. Not a standalone test.

func save_bytes(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes);file.close()

func check_cold_hints()->void:
	var records:Array=[];var expected:Array=[]
	for sample:Dictionary in samples:
		expected.append(sample.path)
		var record:={"uuid":"near_%d"%records.size(),"kind":"asset","asset_path":sample.path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}
		records.append(record)
		var far:=record.duplicate(true);far.uuid+="_far";far.position[0]=500;records.append(far)
	var loader:=Loader.new();loader._content_root=directory;loader._entry_origin=Vector3.ZERO;loader._model_preparation.require_native_products=true
	var hints:Dictionary=loader._cold_model_hints(records)
	check(hints.error.is_empty() and hints.paths==expected and hints.manifests.size()==samples.size(),"cold-loader hints classify repeated near/far instances without any original GLB")
	loader.free()

func check_remaining_source_signatures()->void:
	var loader:=Loader.new();loader._content_root=directory;loader._model_preparation.require_native_products=true
	var trap:=SourceHashTrap.new();loader._source_hash_preparation=trap
	var paths:Array=[];var expected:={}
	for sample:Dictionary in samples:paths.append(sample.path);expected[sample.path]=sample.sha
	var observed:Dictionary=loader._prepare_source_signatures(paths)
	check(observed.get("error",FAILED)==OK and observed.get("signatures",{})==expected and observed.get("mode")=="native_product_index","remaining fortification/art identities resolve from native package descriptors")
	check(trap.calls==0 and observed.get("source_reads",-1)==0,"native identity collection never dispatches the original-source hash coordinator")
	var missing:=paths.duplicate();missing.append(directory.path_join("no_native_product.glb"))
	var rejected:Dictionary=loader._prepare_source_signatures(missing)
	check(rejected.get("error",OK)!=OK and rejected.get("signatures",{}).is_empty() and trap.calls==0,"missing remaining native identity fails atomically without source hashing")
	loader.free()

func write_reference_fixture(path:String,records:Array)->bool:
	# Use the same immutable reference writer as a saved native map. A document
	# save would correctly require its authoring GLB, which this runtime no longer has.
	var stored:=ResourceStore.write_records(records,path,directory)
	if not stored.get("ok",false):return false
	var extras:={"rmmo_format":Location.FORMAT,"rmmo_version":Location.FORMAT_VERSION,"rmmo_storage":Location.STORAGE,"rmmo_unit":"m","rmmo_records":stored.records,"rmmo_resource_dependencies":stored.dependencies,"spawn":[0,1,0]}
	var contents:={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"extras":extras}]}
	save_bytes(path,JSON.stringify(contents).to_utf8_buffer());created.append(path)
	created.append(DependencyIndex.cache_path(path,directory))
	for uri:String in stored.dependencies:created.append(path.get_base_dir().path_join(uri))
	return true

func worker_result(task:Callable)->Dictionary:
	var worker:=Thread.new();var error:=worker.start(task)
	check(error==OK,"private native preparation worker starts")
	if error!=OK:return {"error":error}
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish();Drainer.synchronize_transfer()
	return result

func check_shared_mesh(first:Node,second:Node)->void:
	var a:=first.find_children("*","MeshInstance3D",true,false);var b:=second.find_children("*","MeshInstance3D",true,false)
	check(a.size()==1 and b.size()==1 and a[0].mesh==b[0].mesh and a[0].mesh.get_meta("ground_cpu_cache")==b[0].mesh.get_meta("ground_cpu_cache"),"repeated native instances share the same GPU mesh and CPU geometry owners")

func kit_source_data(names:Array)->Dictionary:
	# The kit wrappers require named mesh modules, not particular building
	# dimensions. Reuse the tiny triangle buffer with distinct local poses.
	var value:=data();var children:Array=[];var nodes:Array=[{"name":"kit_fixture","children":children}]
	for i in names.size():
		children.append(i+1)
		nodes.append({"name":names[i],"mesh":0,"translation":[i*2,0,0]})
	value.nodes=nodes
	return value

func check_kit_geometry(pieces:Dictionary,names:Array)->bool:
	if pieces.size()!=names.size():return false
	for i in names.size():
		var piece:Dictionary=pieces.get(names[i],{})
		var mesh:Mesh=piece.get("mesh")
		if mesh==null or mesh.get_surface_count()!=1:return false
		if piece.get("transform")!=Transform3D(Basis.IDENTITY,Vector3(i*2,0,0)):return false
	return true

func check_initial_loader_without_source()->void:
	if samples.size()!=2:return
	var model:Dictionary=samples[0];var art:Dictionary=samples[1]
	var loader:=Loader.new();loader._content_root=directory;loader.near_first=true
	# Empty terrain preparation stays synchronous; model decoding still uses
	# the real coordinator. This is the real entry method, without a map/GPU scene.
	loader.background_preload=true;loader._model_preparation.require_native_products=true;loader._model_preparation.prepare_static_scenes=true
	loader._record_meta={"rmmo_records":[
		{"uuid":"initial_asset","kind":"asset","asset_path":model.path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]},
		{"uuid":"remaining_art","kind":"box","fortification_art":{"asset_path":art.path},"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}]}
	var trap:=SourceHashTrap.new();loader._source_hash_preparation=trap
	# No dependency directory is supplied: exercise the actual cold fallback.
	var result:Dictionary=await worker_result(func()->Dictionary:
		loader._prepare_record_assets_inner()
		return {"error":loader._error,"reason":loader._failure_reason})
	check(result.error==OK and loader._model_signatures.get(model.path)==model.sha and loader._model_signatures.get(art.path)==art.sha,"initial loader prepares an asset plus remaining fortification identity with no GLB or warm directory")
	check(loader._asset_states.has(model.path) and loader._asset_states[model.path].get("compiled",false),"initial loader retains the actual native model preparation result")
	check(trap.calls==0 and loader._profile.get("source_hash_profile",{}).get("source_reads",-1)==0,"initial loader's remaining fortification path performs zero source hashing")
	# This isolated off-tree loader owns all returned resources and any worker.
	loader._exit_tree();loader.free();Drainer.synchronize_transfer()
