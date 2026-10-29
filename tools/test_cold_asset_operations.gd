extends "res://tools/test_editor_native_asset_requests.gd"
## Real editor/document/HTTP dispatcher. Split upload alone uses the existing
## explicitly identified CPU protocol fixture; GPU coverage is separate.
var editor:Node3D
var completed:Dictionary={}
func operation_done(id:int,result:Dictionary)->void:completed[id]=result
func invoke(name_:String,args:Dictionary={})->Dictionary:
	var result:Dictionary=editor._mcp.call_tool(name_,args)
	if result.get("pending",false):
		var deadline:=Time.get_ticks_msec()+10000
		while not completed.has(result.request_id) and Time.get_ticks_msec()<deadline:await process_frame
		return completed.get(result.request_id,{"ok":false,"error":"timed out"})
	return result
func model_visible(id:String)->bool:
	var visual:Node=editor._view.get_node_or_null(NodePath(id))
	return visual!=null and not visual.get_meta("missing_asset",false) and not visual.has_meta("paint_error") and Ready.scene_ready(visual.get_child(0))

func state_copy()->Dictionary:
	var bodies:Dictionary={}
	for id:String in editor._bodies_by_uuid:bodies[id]=editor._bodies_by_uuid[id].map(func(node):return node.get_instance_id())
	return {"document":editor._doc.get_instance_id(),"records":editor._doc.records.duplicate(true),"meta":editor._doc.map_meta.duplicate(true),"next":editor._doc._next,"revision":editor._doc.authoring_revision,"undo":editor._doc._undo.duplicate(true),"redo":editor._doc._redo.duplicate(true),"dirty":editor._dirty,"selection":editor._selection_tools.ids.duplicate(),"visuals":editor._view.get_children().map(func(node):return node.get_instance_id()),"bodies":bodies,"membership":editor._authoring._membership.duplicate(),"settings":editor._authoring.settings.duplicate(true)}
func entry_for(name_:String)->Dictionary:
	var model:=fixture(name_,true)
	var entry:={"asset_path":model.path,"label":name_,"bounds_position":[0,0,0],"bounds_size":[1,1,1]}
	editor._assets.entries.append(entry);return entry
func wait_result(id:int)->Dictionary:
	var deadline:=Time.get_ticks_msec()+10000
	while not completed.has(id) and Time.get_ticks_msec()<deadline:await process_frame
	return completed.get(id,{"ok":false,"error":"timeout"})
func wait_entered(pool:ControlledPool)->void:
	var deadline:=Time.get_ticks_msec()+8000
	while not pool.has_entered() and Time.get_ticks_msec()<deadline:await process_frame
	check(pool.has_entered(),"real preparation reached the controlled CPU upload boundary")
func cancellation_case(kind:String)->void:
	var service:Node=load(ServicePath).for_consumer(editor);var pool:=ControlledPool.new();pool.hold=true;configure(service,pool)
	var entry:=entry_for("cancel_"+kind);var before:=state_copy()
	var pending:Dictionary=editor._asset_operations.place(entry,Vector3(5,0,0))
	check(pending.get("pending",false),kind+": returns explicit deferred contract")
	await wait_entered(pool)
	check(state_copy()==before,kind+": pending request leaves document/history/UUID/body/view unchanged")
	var old_doc:RefCounted=editor._doc;var old_settings:Dictionary=editor._authoring.settings.duplicate(true)
	if kind=="explicit":editor._asset_operations.cancel(pending.request_id)
	elif kind=="revision":editor._doc.checkpoint()
	elif kind=="protection":editor._authoring.settings.base_height+=1
	elif kind=="document":editor._doc=Doc.new()
	elif kind=="transport":editor._asset_operations.bind_transport(pending.request_id,func():return false)
	var after_change:=state_copy()
	for i:int in 2:await process_frame
	check(state_copy()==after_change,kind+": cancellation adds no mutation to the changed context")
	check(completed.has(pending.request_id) and not completed[pending.request_id].ok,kind+": caller receives explicit failure")
	check(service.ledger.count()>0,kind+": blocked worker still owns its admission lease")
	pool.gate.post();await settle(service.ledger,pool)
	editor._doc=old_doc;editor._authoring.settings=old_settings
	check(not service._closed,kind+": editor-wide preparation service remains open")
func rejection_case(kind:String)->void:
	var service:Node=load(ServicePath).for_consumer(editor);var pool:=ControlledPool.new();configure(service,pool)
	var entry:=entry_for("reject_"+kind)
	if kind=="upload":pool.fail=true
	elif kind=="instance":entry.tree_settings={}
	var before:=state_copy();var pending:Dictionary=editor._asset_operations.place(entry,Vector3(5,0,0))
	var result:=await wait_result(pending.request_id)
	check(not result.get("ok",true),kind+": real preparation/instance failure rejects publication")
	check(state_copy()==before,kind+": failed private result preserves every live owner and transaction")
	await settle(service.ledger,pool)

func freshness_case(kind:String)->void:
	var service:Node=load(ServicePath).for_consumer(editor);var pool:=ControlledPool.new();configure(service,pool)
	var entry:=entry_for("freshness_"+kind);var source_path:String=entry.asset_path
	if kind=="prefab":
		var local:=Doc.new();local.add_asset(entry,Vector3.ZERO)
		var path:=content_root.path_join("assets/prefabs/freshness.json")
		write(path,JSON.stringify({"format":"rmmo_prefab","version":1,"records":local.records,"building_instances":{}}))
		entry={"prefab_path":path,"label":"freshness"}
	var before:=state_copy();editor._asset_operations.work_budget_us=1
	var pending:Dictionary=editor._asset_operations.place(entry,Vector3(25,0,0))
	var deadline:=Time.get_ticks_msec()+10000
	while editor._asset_operations._operations.has(pending.request_id) and editor._asset_operations._operations[pending.request_id].cursor<1 and Time.get_ticks_msec()<deadline:await process_frame
	check(editor._asset_operations._operations.has(pending.request_id),kind+": freshness change occurs after a private visual exists but before publication")
	if kind=="prefab":write(entry.prefab_path,FileAccess.get_file_as_string(entry.prefab_path)+" \n")
	else:
		var path:=Compiled.index_path(source_path,content_root)
		var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		manifest.source_sha="b".repeat(64);write(path,JSON.stringify(manifest))
	editor._asset_operations.work_budget_us=2000
	var result:=await wait_result(pending.request_id)
	check(not result.get("ok",true),kind+": final source freshness check rejects the privately prepared instance")
	check(state_copy()==before,kind+": stale candidate/file leaves live document, history and derived owners unchanged")
	await settle(service.ledger,pool)
func concurrent_case()->void:
	var service:Node=load(ServicePath).for_consumer(editor);var pool:=ControlledPool.new();pool.hold=true;configure(service,pool)
	var entry:=entry_for("shared_revision");var produced:int=service.profile.producers
	var a:Dictionary=editor._asset_operations.place(entry,Vector3(8,0,0));var b:Dictionary=editor._asset_operations.place(entry,Vector3(10,0,0))
	await wait_entered(pool);pool.gate.post()
	var first:=await wait_result(a.request_id);var second:=await wait_result(b.request_id)
	check(int(first.ok)+int(second.ok)==1,"shared preparation permits one commit and explicitly rejects the stale sibling revision")
	check(service.profile.producers-produced==1 and pool.audit.created==1,"two concurrent placements share one real producer and upload")
	await settle(service.ledger,pool)
func incremental_case(id:String)->void:
	var visual:Node=editor._view.get_node(NodePath(id));var identity:=visual.get_instance_id()
	var bodies:Array=editor._bodies_by_uuid[id].map(func(body):return body.get_instance_id())
	var prepared:int=editor._asset_operations.profile.visuals
	var classified:int=editor._asset_operations.profile.history_plan_visits
	editor._doc.checkpoint();editor._doc._find(id).position[0]+=1;editor._sync_record_transform(editor._doc._find(id))
	await invoke("undo");await invoke("redo")
	check(editor._view.get_node(NodePath(id)).get_instance_id()==identity and editor._bodies_by_uuid[id].map(func(body):return body.get_instance_id())==bodies,"ordinary pose undo/redo preserves node and body identities")
	editor._doc.checkpoint();editor._doc._find(id).editor_name="renamed";editor._commit_record_properties([editor._doc._find(id)],false)
	await invoke("undo");await invoke("redo")
	check(editor._view.get_node(NodePath(id)).get_instance_id()==identity and editor._asset_operations.profile.visuals==prepared,"ordinary metadata undo/redo constructs zero prepared visuals")
	check(editor._asset_operations.profile.history_plan_visits==classified+4*editor._doc.records.size(),"pose/property history classifies records once and directly consumes the same plan")
	# Combining metadata and pose no longer matches either incremental shortcut.
	editor._doc.checkpoint();editor._doc._find(id).editor_name="mixed";editor._doc._find(id).position[0]+=1
	editor._sync_record_transform(editor._doc._find(id))
	await invoke("undo")
	check(model_visible(id),"mixed metadata/pose history prepares the fallback record-replacement path")

func shape_reuse_case(entry:Dictionary,id:String)->void:
	var shape_id:int=editor._bodies_by_uuid[id][0].get_child(0).shape.get_instance_id()
	var built:int=editor._picking_shapes.built
	var pending:Dictionary=editor._asset_operations.place(entry,Vector3(15,0,0));var result:=await wait_result(pending.request_id)
	check(result.get("ok",false) and editor._bodies_by_uuid[result.ids[0]][0].get_child(0).shape.get_instance_id()==shape_id,"sequential successful placement reuses the scene's immutable shape object")
	check(editor._picking_shapes.built==built,"reused model performs zero additional collision shape builds")
	await invoke("undo")
	var service:Node=load(ServicePath).for_consumer(editor);var pool:=ControlledPool.new();configure(service,pool)
	var fresh:=entry_for("private_shape_cancel");var before:=state_copy();var size_:int=editor._picking_shapes._entries.size()
	editor._asset_operations.work_budget_us=1
	pending=editor._asset_operations.place(fresh,Vector3(18,0,0))
	var deadline:=Time.get_ticks_msec()+10000
	while editor._asset_operations._operations.has(pending.request_id) and editor._asset_operations._operations[pending.request_id].shapes._entries.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(editor._asset_operations._operations.has(pending.request_id),"private collision shape can be cancelled before publication")
	editor._asset_operations.cancel(pending.request_id);editor._asset_operations.work_budget_us=2000
	check(state_copy()==before and editor._picking_shapes._entries.size()==size_ and editor._picking_shapes.built==built,"cancelled private shape never enters the live cache or view")
	await settle(service.ledger,pool)

func terrain_context_case(entry:Dictionary)->void:
	var terrain_id:String=editor._doc.add_box_silent("ground",Vector3(40,0,0),Vector3(4,1,4))
	var terrain:Dictionary=editor._doc._find(terrain_id)
	terrain.terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-1,"heights":[0,0,0,0,0,0,0,0,0],"holes":[false,false,false,false]}
	editor._commit_records([terrain_id])
	var neighbors:RefCounted=editor._doc.terrain_neighbors
	var image_id:int=neighbors.data[terrain_id].image.get_instance_id()
	var before_updates:int=editor._asset_operations.profile.terrain_updates
	var pending:Dictionary=editor._asset_operations.place(entry,Vector3(35,0,0));var result:=await wait_result(pending.request_id)
	await invoke("undo");await invoke("redo")
	check(result.get("ok",false) and editor._doc.terrain_neighbors==neighbors and neighbors.data[terrain_id].image.get_instance_id()==image_id,"native placement/history borrows the existing terrain halo without rebuilding it")
	check(editor._asset_operations.profile.terrain_updates==before_updates,"native-only target preparation performs zero terrain updates")
	var id:String=result.ids[0]
	terrain=editor._doc._find(terrain_id)
	editor._doc.checkpoint();terrain.terrain_mesh.heights[4]=.5;editor._doc._find(id).size=[2,2,2]
	editor._sync_record_transform(editor._doc._find(id));editor._commit_records([terrain_id])
	check(editor._doc._find(terrain_id).terrain_mesh.heights[4]==.5,"terrain test mutates the current post-history record")
	var live_image:int=neighbors.data[terrain_id].image.get_instance_id()
	var contexts:int=editor._asset_operations.profile.terrain_contexts
	var undo:Dictionary=editor._undo()
	check(undo.get("pending",false) and neighbors.data[terrain_id].image.get_instance_id()==live_image,"mixed geometry history prepares terrain privately and leaves the current halo intact")
	await wait_result(undo.request_id)
	check(model_visible(id) and editor._doc._find(terrain_id).terrain_mesh.heights[4]==0,"mixed terrain/model history publishes the exact target geometry")
	check(editor._asset_operations.profile.terrain_updates==before_updates+1 and editor._asset_operations.profile.terrain_contexts==contexts+1,"one changed terrain tile generates one private context with no second publication update")
	var model_visual:int=editor._view.get_node(NodePath(id)).get_instance_id()
	var model_bodies:Array=editor._bodies_by_uuid[id].map(func(body):return body.get_instance_id())
	var prepared:int=editor._asset_operations.profile.visuals
	editor._doc.checkpoint();editor._doc._find(terrain_id).terrain_saturation=.7
	var terrain_ids:Array[String]=[terrain_id]
	editor._refresh_records(terrain_ids)
	await invoke("undo");await invoke("redo")
	check(editor._view.get_node(NodePath(id)).get_instance_id()==model_visual and editor._bodies_by_uuid[id].map(func(body):return body.get_instance_id())==model_bodies and editor._asset_operations.profile.visuals==prepared and is_equal_approx(editor._doc._find(terrain_id).terrain_saturation,.7),"terrain-material history refreshes the affected terrain while preserving unrelated native nodes/bodies and preparing no native replacements")

func full_history_case()->void:
	var previous_view:Node=editor._view
	editor._doc.checkpoint_recovery();editor._doc.map_meta["candidate_test_metadata"]=1
	var result:Dictionary=editor._undo()
	check(result.get("pending",false) and editor._view==previous_view and editor._doc.map_meta.has("candidate_test_metadata"),"full-view history keeps the old document/view until target preparation completes")
	var operation:Dictionary=editor._asset_operations._operations[result.request_id]
	check(operation.full and operation.records.size()==operation.target.records.size(),"only metadata requiring full rebuild prepares the complete target")
	operation={}
	var done:=await wait_result(result.request_id)
	check(done.get("ok",false) and editor._view!=previous_view and not editor._doc.map_meta.has("candidate_test_metadata"),"full target swaps only after successful preparation")
	check(not editor._view.get_children().any(func(node):return node.get_meta("missing_asset",false) or node.has_meta("paint_error")),"full history prepares every private native dependency without a global cache")

func gravity_case()->void:
	var floor_id:String=editor._doc.add_box_silent("ground",Vector3(0,-.5,30),Vector3(20,1,20));editor._commit_records([floor_id])
	for i:int in 3:await physics_frame
	var entry:=entry_for("gravity");var service:Node=load(ServicePath).for_consumer(editor);var pool:=ControlledPool.new();configure(service,pool)
	editor._gravity.configure(true);editor._dirty=false
	var before:=state_copy();var pending:Dictionary=editor._asset_operations.place(entry,Vector3(0,2,30));var result:=await wait_result(pending.request_id)
	check(result.get("ok",false) and editor._gravity.falling and editor._doc._undo.size()==before.undo.size(),"prepared gravity placement starts the original visible fall without committing history")
	editor._gravity.complete(true)
	check(state_copy()==before,"cancelling the fall restores identity, dirty, history, selection, bodies and records")
	pending=editor._asset_operations.place(entry,Vector3(0,.5,30));result=await wait_result(pending.request_id)
	var deadline:=Time.get_ticks_msec()+8000
	while editor._gravity.falling and Time.get_ticks_msec()<deadline:await physics_frame
	check(not editor._gravity.falling and editor._doc._undo.size()==before.undo.size()+1,"settlement contributes exactly one undo transaction")
	editor._gravity.configure(false)
	await invoke("undo")
	check(not editor._doc.has_uuid(str(result.ids[0])),"undo removes the complete prepared-and-settled model")
	await settle(service.ledger,pool)
func placement_prefab_case()->void:
	var service:Node=load(ServicePath).for_consumer(editor);var pool:=ControlledPool.new();configure(service,pool)
	var entry:=entry_for("prefab_model");var other:=entry_for("prefab_model_other");var local:=Doc.new()
	local.add_asset(entry,Vector3.ZERO);local.add_asset(entry,Vector3(2,0,0));local.add_asset(other,Vector3(4,0,0));local.add_box("block",Vector3(6,1,0),Vector3.ONE)
	var path:=content_root.path_join("assets/prefabs/cold.json")
	write(path,JSON.stringify({"format":"rmmo_prefab","version":1,"records":local.records,"building_instances":{}}))
	var before:int=editor._doc._undo.size();var produced:int=service.profile.producers
	editor._asset_operations.work_budget_us=1
	var pending:Dictionary=editor._asset_operations.place({"prefab_path":path,"label":"cold pair"},Vector3(20,0,0))
	var result:=await wait_result(pending.request_id);editor._asset_operations.work_budget_us=2000
	check(result.get("ok",false) and result.ids.size()==4,"mixed model/primitive prefab publishes every independently editable member")
	if result.get("ok",false):
		check(model_visible(result.ids[0]) and model_visible(result.ids[1]) and model_visible(result.ids[2]),"duplicate and distinct prefab model paths are all READY")
		check(editor._doc._find(result.ids[0]).editor_group==editor._doc._find(result.ids[1]).editor_group,"prefab member group identity remains intact")
	check(editor._doc._undo.size()==before+1 and service.profile.producers==produced+2,"whole prefab owns one undo and exactly one producer per distinct model path")
	await invoke("undo")
	for i:int in 12:await process_frame
	check(pool.audit.created==pool.audit.releases.size(),"prefab cold-redo precondition has no remaining source texture owner")
	await invoke("redo")
	check(result.get("ok",false) and model_visible(result.ids[0]),"prefab redo prepares its cold model dependency")
	await settle(service.ledger,pool)
func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(120).timeout.connect(func():quit(2))
	var model:=fixture("cold_placement",true)
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=Doc.new();session.world3d_editor_path=""
	editor=load("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false
	editor._draft_directory=content_root.path_join("drafts");root.add_child(editor);editor._safety.enabled=false
	var port:=29876;var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"actual 3D dispatcher starts")
	if "_asset_operations" in editor:editor._asset_operations.finished.connect(operation_done)
	var service:Node=load(ServicePath).for_consumer(editor);var pool:=ControlledPool.new();configure(service,pool)
	var entry:={"asset_path":model.path,"label":"cold fixture","bounds_position":[0,0,0],"bounds_size":[1,1,1]}
	editor._assets.entries.append(entry)
	var placed:=await invoke("place_asset",{"asset_id":model.path,"position":[0,0,0]})
	check(placed.get("ok",false),"cold placement returns final success")
	var id:String=str(placed.get("ids",[""])[0])
	check(model_visible(id),"cold placement publishes a READY native model rather than a fallback")
	check(Assets._scenes.is_empty(),"cold placement does not populate the global scene cache")
	check(editor._doc._undo.size()==1,"placement contributes exactly one undo entry")
	var owner:WeakRef=weakref(editor._view.get_node(NodePath(id)).get_child(0).get_meta("_compiled_resource_owner")) if model_visible(id) else null
	await invoke("undo")
	for i:int in 12:await process_frame
	check(editor._doc.records.is_empty() and pool.audit.releases.size()==pool.audit.created,"last placed owner is gone before cold redo")
	check(owner==null or owner.get_ref()==null,"cold redo has no surviving PackedScene template owner")
	check(not service._private_models.values().any(func(row):return row.packed.get_ref()!=null),"private weak index contains no valid owner before cold redo")
	var redone:=await invoke("redo")
	check(redone.get("ok",false) and model_visible(id),"truly cold redo restores a READY model")
	check(editor._doc._undo.size()==1 and editor._doc._redo.is_empty(),"redo consumes history only once")
	await incremental_case(id)
	await shape_reuse_case(entry,id)
	await terrain_context_case(entry)
	for kind:String in ["explicit","revision","protection","document","transport"]:await cancellation_case(kind)
	for kind:String in ["upload","instance"]:await rejection_case(kind)
	for kind:String in ["candidate","prefab"]:await freshness_case(kind)
	await concurrent_case()
	await placement_prefab_case()
	await gravity_case()
	await full_history_case()
	print("COLD_ASSET_PROFILE ",JSON.stringify(editor._asset_operations.snapshot()))
	var ledger:RefCounted=editor._shared_preparation_ledger
	editor.free();editor=null;session.world3d_editor_doc=null;session.world3d_editor_path=""
	await settle(ledger,pool)
	print("COLD_ASSET_OPERATIONS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
