extends "res://tools/test_native_kit_consumer_preparation.gd"
## Actual initial model coordinator and complete record builder. CPU texture
## protocol stub only; final file authority is separately tested through start.
const MapLoader=preload("res://scripts/world3d/map_loader.gd")
const CacheScope=preload("res://scripts/world3d/runtime_asset_cache_scope.gd")

class StageLoader extends MapLoader:
	func _final_index_integrity(_prepared:Dictionary)->bool:return true

func spec_owner_refs(spec:Dictionary)->Array:
	var references:Array=[]
	for owner:PackedScene in spec.mesh.get_meta("_compiled_resource_owners",[]):references.append(weakref(owner))
	return references

func loader_case(background:bool)->void:
	var top:=fixture("loader_top_"+str(background),true);var edge:=fixture("loader_edge_"+str(background),true)
	delete_authoring_source(top);delete_authoring_source(edge)
	var document:=kit_document(top.path,edge.path)
	var duplicate:Dictionary=document.records[-1].duplicate(true);duplicate.uuid="duplicate";document.records.append(duplicate)
	var before:=document.recovery_snapshot()
	var pool:=ControlledPool.new();var loader:=StageLoader.new();root.add_child(loader)
	loader.background_preload=background;loader._content_root=content_root;loader._path=content_root.path_join("loader_map.gltf")
	loader._model_preparation.require_native_products=true
	loader._model_preparation.native_texture_pool=pool;loader._model_preparation.native_texture_preparer=pixels
	loader._model_preparation.native_resident_bridge=loader._native_resident_bridge
	loader._record_meta={"rmmo_records":document.records};loader._mesh_cache_allowed=false
	var worker:=Thread.new();check(worker.start(loader._prepare_record_assets_inner)==OK,"MapLoader starts its real worker coordinator")
	while worker.is_alive():await process_frame
	worker.wait_to_finish()
	check(loader._error==OK and loader._asset_states.size()==2 and loader._model_signatures.size()==2,"MapLoader prepares and verifies two unique native kit models")
	var refs:Array=[]
	for entry:Dictionary in loader._asset_states.values():refs.append(weakref(entry.packed))
	loader._publish_initial_native_textures()
	var received:Dictionary={}
	loader.finished.connect(func(scene:Node,_path:String,error:String):received.scene=scene;received.error=error)
	await loader._build_records()
	check(received.has("scene") and received.scene!=null and received.error.is_empty(),"complete MapLoader record builder publishes native kit stream specs")
	var scene:Node=received.get("scene")
	if scene!=null:
		var specs:Array=scene.get_meta("stream_library",[])
		var tiles:Array=specs.filter(func(spec:Dictionary):return spec.uuid in [document.asset_uuid,"duplicate"])
		check(tiles.size()==2 and tiles.all(func(spec:Dictionary):return spec.mesh is ArrayMesh and spec.mesh.get_meta("_compiled_resource_owners",[]).size()==2),"both runtime tile specs retain exact native source owners")
		check(scene.has_meta(CacheScope.META)!=background,"normal kit load claims map cache scope while background stays private")
		check(Assets._scenes.has(top.path)!=background and Assets._scenes.has(edge.path)!=background,"kit templates follow existing foreground/background publication policy")
		kit_observations.append({"background":background,"profile":scene.get_meta("load_profile"),"native_owners":refs.size(),"kit_specs":tiles.size()})
		specs.clear();tiles.clear()
	check(document.recovery_snapshot()==before,"runtime kit build preserves author records")
	for i in 3:await process_frame
	check(not is_instance_valid(loader) and refs.all(func(reference:WeakRef):return reference.get_ref()!=null),"finished loader releases its context while runtime specs retain the graph")
	if scene!=null:scene.free()
	received.clear()
	await retired(PublishedGeometry.for_tree(self),refs)
	check(refs.all(expired) and not Assets._scenes.has(top.path) and not Assets._scenes.has(edge.path),"last runtime map releases kit native graphs and its cache claims")
	check(pool.audit.releases.size()==pool.audit.created,"all CPU texture protocol owners release after map exit")

func public_start_case()->Dictionary:
	var model:=fixture("public_loader_kit",true);delete_authoring_source(model)
	var document:=kit_document(model.path)
	var map_path:=content_root.path_join("public_map/map.gltf")
	check(document.save(map_path)==OK,"native-only kit map saves through actual document export")
	var saved_sha:=FileAccess.get_sha256(map_path)
	var pool:=ControlledPool.new();var loader:=MapLoader.new();root.add_child(loader)
	loader._model_preparation.native_texture_pool=pool;loader._model_preparation.native_texture_preparer=pixels
	var received:Dictionary={}
	loader.finished.connect(func(scene:Node,_path:String,error:String):received.scene=scene;received.error=error)
	loader.start(map_path)
	var deadline:=Time.get_ticks_msec()+20000
	while not received.has("scene") and Time.get_ticks_msec()<deadline:await process_frame
	check(received.get("scene")!=null and received.get("error","").is_empty(),"real MapLoader.start validates saved references and loads native kit without GLB")
	if not received.get("error","").is_empty():print("PUBLIC_LOADER_ERROR ",received.error)
	var refs:Array=[];var scene:Node=received.get("scene")
	if scene!=null:
		var spec:Dictionary=scene.get_meta("stream_by_id",{}).get(document.asset_uuid,{})
		check(not spec.is_empty() and spec.mesh is ArrayMesh,"public loader publishes the authored kit stream record")
		refs=spec_owner_refs(spec)
		spec.clear();scene.free()
	received.clear()
	for i in 3:await process_frame
	if is_instance_valid(loader):loader.cancel();loader.free()
	check(FileAccess.get_sha256(map_path)==saved_sha,"runtime loading preserves saved author map bytes")
	return {"refs":refs,"pool":pool}

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(80).timeout.connect(func():printerr("NATIVE_KIT_MAP_LOADER watchdog");quit(2))
	await loader_case(false);await loader_case(true)
	var public_case:Dictionary=await public_start_case()
	await retired(PublishedGeometry.for_tree(self),public_case.refs)
	check(public_case.refs.all(expired) and public_case.pool.audit.releases.size()==public_case.pool.audit.created,"actual public loader and map exit release all prepared kit ownership")
	write(content_root.get_base_dir().path_join("observations.json"),JSON.stringify({"checks":checks,"failures":failures,"cases":kit_observations,"scope":"CPU actual model coordinator/build; texture upload stub; final index authority intercepted; no GPU claim"},"\t"))
	print("NATIVE_KIT_MAP_LOADER checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
