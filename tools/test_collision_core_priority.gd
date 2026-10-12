extends SceneTree
## CPU-only scheduling regression. Candidate envelopes below are hints, not
## collision products: this test never imports a model or grants readiness.
const MapLoader=preload("res://scripts/world3d/map_loader.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Descriptor=preload("res://scripts/world3d/collision_asset_descriptor.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Proof=preload("res://scripts/world3d/dependency_index_proof.gd")
const Wiring=preload("res://tools/test_deferred_collision_prefetch.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
const CLIP=AABB(Vector3(-1,-100,-1),Vector3(20,200,20))
var passed:=0
var failures:=0
var folder:=""
var created:Array[String]=[]

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failures+=1
func put(path:String,bytes:PackedByteArray)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file!=null:file.store_buffer(bytes);file.close();created.append(path)

func candidate_fixture()->String:
	var source:=folder.path_join("hint.glb")
	put(source,"candidate probe does not import these bytes".to_utf8_buffer())
	var candidate:Dictionary={"version":Descriptor.VERSION,"source_path":source,"source_sha":FileAccess.get_sha256(source),"generator":Descriptor.generator(),
		"descriptor_sha":"0".repeat(64),"descriptor_bytes":1,"retained_bytes":0,"product_count":1,"estimated_bytes":Descriptor.WORKSPACE_BYTES}
	put(Descriptor._index_path(source,folder),JSON.stringify(candidate).to_utf8_buffer())
	check(not Descriptor.candidate(source,folder).is_empty(),"bounded candidate fixture is available only as a selection hint")
	return source

func selection_fixture(source:String)->Dictionary:
	var rows:Array=[];var records:Array=[];var entries:Array=[]
	var names:Array=["core_a","core_b","landing","building","owned","unknown","native","missing","ring_first","ring_second"]
	for i:int in names.size():
		var record:Dictionary={"uuid":names[i],"rmmo_ref":{"uri":names[i]+".rmres","sha256":str(i).sha256_text()}}
		var box:=AABB(Vector3(4+i,0,1),Vector3.ONE)
		if i==2:box=AABB(Vector3(-.5,0,-.5),Vector3.ONE)
		var row:Dictionary={"reason":"native_road" if i==6 else "model_accessor_bounds","bounds_known":i!=5,"owner_keys":["owner"] if i==4 else [],
			"group_id":"building:fixture" if i==3 else "","asset_path":folder.path_join("missing.glb") if i==7 else "" if i==6 else source,"bounds":box,"classification":"spatial","memory_bytes":65536}
		rows.append(row);records.append(record)
		entries.append({"record_index":i,"compact_record":record,"bounds":box,"classification":row.classification,"reason":row.reason,"asset_path":row.asset_path,"group_id":row.group_id,"memory_bytes":row.memory_bytes})
	var core:Array=records.slice(0,8);var dependencies:Dictionary={}
	for record:Dictionary in core:dependencies[record.rmmo_ref.uri]=record.rmmo_ref.sha256
	return {"index":{"rows":rows,"extras":{"rmmo_records":records}},"selection":{"ok":true,"record_indices":[0,1,2,3,4,5,6,7],"compact_records":core,
		"deferred_indices":[8,9],"deferred_compact_records":[records[8],records[9]],"deferred_entries":[entries[8],entries[9]],
		"extras":{"rmmo_records":core,"rmmo_resource_dependencies":dependencies,"unchanged":"author metadata"},"dependencies":dependencies,"selected_count":8,"deferred_count":2,"selected_closure_verified":false}}

func ids(entries:Array)->Array:
	var result:Array=[]
	for entry:Dictionary in entries:result.append(entry.compact_record.uuid)
	return result

func queue_fixture(hints:Array)->Dictionary:
	var loader:=Wiring.Loader.new();root.add_child(loader)
	var queue:=Wiring.Queue.new();var rows:Array=[];var items:Array=[]
	var names:Array=["ring_first","core_b","ring_second","core_a","outside","building","native","owned"]
	for i:int in names.size():
		var bounds:=AABB(Vector3(100 if i==4 else 5,0,1),Vector3.ONE)
		var group:String="building:test" if i==5 else ""
		var entry:Dictionary={"record_index":i,"compact_record":{"uuid":names[i]},"asset_path":"fixture.glb","bounds":bounds,"group_id":group}
		rows.append({"reason":"native_road" if i==6 else "model_accessor_bounds","bounds_known":true,"owner_keys":["owner"] if i==7 else []})
		items.append({"record":entry.compact_record,"path":"fixture.glb","bounds":bounds,"native_reference":i==6,"group_id":group,"reference_entry":entry})
	queue.pending=items;queue.configure_references({"rows":rows},"fixture.gltf","fixture",Proof.new())
	loader.test_queue=queue;loader._entry_plan={"safety_clip":CLIP};loader._deferred_assets=items
	loader._collision_core_deferred_ids.assign(hints)
	return {"loader":loader,"queue":queue}

func dispose(value:Dictionary)->void:
	if is_instance_valid(value.loader):value.loader.free()
	if is_instance_valid(value.queue):value.queue.free()

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var old_flag:=Deferred.collision_first_enabled;var old_pipeline:=MapLoader.entry_pipeline_enabled
	Deferred.collision_first_enabled=true;MapLoader.entry_pipeline_enabled=true
	folder=Paths.cache_directory("collision_core_priority_%d"%Time.get_ticks_usec())
	var source:=candidate_fixture();var fixture:=selection_fixture(source)
	var loader:=MapLoader.new();loader._content_root=folder;loader._entry_origin=Vector3.ZERO
	var selected:Dictionary=loader._collision_first_selection(fixture.index,fixture.selection)
	check(loader._collision_core_deferred_ids==["core_a","core_b"],"selection records only actual eligible core deferrals")
	check(loader._profile.collision_first_core_deferred==2 and loader._profile.collision_first_core_deferred_ids==["core_a","core_b"],"load profile records the exact core-deferral count and bounded UUID sample")
	check(selected.record_indices==[2,3,4,5,6,7],"landing building owner unknown native and missing-candidate records remain selected")
	check(selected.deferred_indices==[8,9,0,1] and ids(selected.deferred_entries)==["ring_first","ring_second","core_a","core_b"],"hint preserves the full pre-existing deferred set and exact added record identities")
	check(selected.selected_count+selected.deferred_count==10 and selected.dependencies.size()==6 and selected.extras.unchanged=="author metadata" and not selected.selected_closure_verified,"selection preserves author metadata and closure status without granting verification")
	var hints:Array=loader._collision_core_deferred_ids.duplicate()
	var wide:=selection_fixture(source)
	for i:int in 40:
		var record:Dictionary=wide.index.extras.rmmo_records[0].duplicate(true);record.uuid="more_"+str(i)
		var at:int=wide.index.rows.size();wide.index.rows.append(wide.index.rows[0].duplicate(true));wide.index.extras.rmmo_records.append(record)
		wide.selection.record_indices.append(at)
	loader._collision_first_selection(wide.index,wide.selection)
	check(loader._collision_core_deferred_ids.size()==42 and loader._profile.collision_first_core_deferred==42 and loader._profile.collision_first_core_deferred_ids.size()==32,"diagnostic UUID sample is bounded while scheduling keeps all core deferrals")
	fixture=selection_fixture(source);fixture.index.rows[0].bounds_known=false;fixture.index.rows[1].bounds_known=false
	loader._collision_first_selection(fixture.index,fixture.selection)
	check(loader._collision_core_deferred_ids.is_empty(),"a subsequent selection replaces rather than accumulates previous hints")
	loader._collision_core_deferred_ids.assign(hints);Deferred.collision_first_enabled=false
	fixture=selection_fixture(source);selected=loader._collision_first_selection(fixture.index,fixture.selection)
	check(loader._collision_core_deferred_ids.is_empty() and selected.record_indices==[0,1,2,3,4,5,6,7],"disabled experiment clears hints and retains ordinary core selection")
	loader.free();Deferred.collision_first_enabled=true
	var baseline:=queue_fixture([]);baseline.loader._start_entry_prefetch()
	var original:Array=ids(baseline.queue.created.tickets.entry_safety)
	check(original==["ring_first","core_b","ring_second","core_a"],"baseline safety ordering is preserved without a hint")
	dispose(baseline)
	var value:=queue_fixture(hints);value.loader._start_entry_prefetch()
	var service:Node=value.queue.created;var ordered:Array=ids(service.tickets.entry_safety)
	check(ordered==["core_b","core_a","ring_first","ring_second"],"real MapLoader forwards core hints and Deferred stably partitions eligible safety entries")
	var expected_set:=original.duplicate();var actual_set:=ordered.duplicate();expected_set.sort();actual_set.sort()
	check(actual_set==expected_set,"priority changes order only and keeps every safety dependency exactly once")
	# The ordinary ensure path also forwards owner-bound records for the real
	# Loader to reject; that existing fallback behavior is not a sorting change.
	check(not value.queue.ensure_collision(CLIP,"entry_safety") and ids(service.tickets.entry_safety)==ordered+["owned"],"adopt-time safety refresh preserves core-first order and ordinary fallback records without granting readiness")
	check(service.get_node_or_null("CollisionInstanceResidency")==null and not value.queue.geometry_published(CLIP),"CPU prefetch sorting creates no Store and does not publish geometry")
	dispose(value)
	value=queue_fixture(["core_a","unknown","core_b","core_a","outside","building","native","owned"]);value.loader._start_entry_prefetch()
	check(ids(value.queue.created.tickets.entry_safety)==ordered,"duplicate unknown distant and unsupported hints cannot add remove or duplicate safety records")
	dispose(value)
	await process_frame
	Deferred.collision_first_enabled=old_flag;MapLoader.entry_pipeline_enabled=old_pipeline
	for path:String in created:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	for path:String in [Descriptor.directory(folder),Descriptor.Products.directory(folder),folder.path_join("cache/world3d"),folder.path_join("cache"),folder]:
		if DirAccess.dir_exists_absolute(path):DirAccess.remove_absolute(path)
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero unexpected engine or script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_CORE_PRIORITY passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
