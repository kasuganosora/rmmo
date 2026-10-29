extends "res://tools/test_editor_native_ui_gpu.gd"
## Real HTTP, editor operations, split products, default service and tracker.
## Pausing the operation processor controls publication scheduling only.
const Document=preload("res://scripts/world3d/world_document.gd")
var editor:Node3D
var completed:Dictionary={}
var port:=29903
var serial:=0
var http_trace:Array=[]
var frame_last:=0
var frame_max_us:=0
var operation_frame_max_us:=0
var owned_paths:Array=[]
var retained_ground:Dictionary={}

func ground_snapshot()->Dictionary:
	var groups:Dictionary={};var bodies:Dictionary={}
	for key:String in editor._ground_batches.groups:
		var group:Dictionary=editor._ground_batches.groups[key]
		if group.category=="ground" and is_instance_valid(group.get("visual")):groups[key]=group.visual.get_instance_id()
	for record:Dictionary in editor._doc.records:
		if record.kind=="box" and record.get("surface_id")=="ground":bodies[str(record.uuid)]=editor._bodies_by_uuid.get(str(record.uuid),[]).map(func(body):return body.get_instance_id())
	return {"groups":groups,"bodies":bodies}

func seed_ground_batch()->void:
	var ids:Array[String]=[]
	for index:int in 6:ids.append(editor._doc.add_box_silent("ground",Vector3(100+index*2,-.1,100),Vector3(2,.2,2)))
	editor._commit_records(ids)
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		var stats:Dictionary=editor._ground_batches.stats()
		if stats.pending_groups==0 and stats.groups>0:break
		await process_frame
	retained_ground=ground_snapshot();report.ground_before=editor._ground_batches.stats()
	check(not retained_ground.groups.is_empty() and report.ground_before.render_surfaces<report.ground_before.source_surfaces,"ordinary ground actually merges before cold model operations")

func measured_frame()->void:
	var now:=Time.get_ticks_usec()
	if frame_last!=0:
		frame_max_us=maxi(frame_max_us,now-frame_last)
		if is_instance_valid(editor) and editor._asset_operations.snapshot().pending>0:operation_frame_max_us=maxi(operation_frame_max_us,now-frame_last)
	frame_last=now

func send_rpc(method:String,params:Dictionary={})->Dictionary:
	serial+=1
	var payload:={"jsonrpc":"2.0","id":serial,"method":method,"params":params}
	var body:=JSON.stringify(payload).to_utf8_buffer()
	var bytes:=("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n"%[port,body.size()]).to_utf8_buffer();bytes.append_array(body)
	var peer:=StreamPeerTCP.new();peer.connect_to_host("127.0.0.1",port)
	var until:=Time.get_ticks_msec()+5000
	while peer.get_status()!=StreamPeerTCP.STATUS_CONNECTED and Time.get_ticks_msec()<until:peer.poll();await process_frame
	check(peer.get_status()==StreamPeerTCP.STATUS_CONNECTED,"real loopback HTTP connection opens")
	peer.put_data(bytes)
	return {"peer":peer,"bytes":PackedByteArray(),"request":payload}

func receive_rpc(request:Dictionary)->Dictionary:
	var deadline:=Time.get_ticks_msec()+45000
	var peer:StreamPeerTCP=request.peer
	while Time.get_ticks_msec()<deadline:
		await process_frame;peer.poll()
		if peer.get_available_bytes()>0:request.bytes.append_array(peer.get_partial_data(peer.get_available_bytes())[1])
		var split:int=editor._mcp._find_headers_end(request.bytes)
		if split<0:continue
		var length:=int(editor._mcp._header_value(request.bytes.slice(0,split).get_string_from_utf8(),"Content-Length"))
		if request.bytes.size()<split+4+length:continue
		var response:Variant=JSON.parse_string(request.bytes.slice(split+4,split+4+length).get_string_from_utf8())
		peer.disconnect_from_host();http_trace.append({"request":request.request,"response":response})
		return response if response is Dictionary else {}
	peer.disconnect_from_host();check(false,"HTTP response finishes before deadline");return {}

func send_tool(name_:String,args:Dictionary={})->Dictionary:return await send_rpc("tools/call",{"name":name_,"arguments":args})
func tool_result(response:Dictionary)->Dictionary:
	var content:Array=response.get("result",{}).get("content",[])
	return JSON.parse_string(content[0].text) if not content.is_empty() else {"ok":false,"error":response.get("error",{})}
func call_tool(name_:String,args:Dictionary={},expected:bool=true)->Dictionary:
	var result:=tool_result(await receive_rpc(await send_tool(name_,args)))
	check(result.get("ok",false)==expected and not result.get("pending",false),"HTTP "+name_+" resolves its final result")
	return result

func doc_state()->Dictionary:
	var bodies:Dictionary={}
	for key:String in editor._bodies_by_uuid:bodies[key]=editor._bodies_by_uuid[key].map(func(body):return body.get_instance_id())
	return {"records":editor._doc.records.duplicate(true),"meta":editor._doc.map_meta.duplicate(true),"undo":editor._doc._undo.duplicate(true),"redo":editor._doc._redo.duplicate(true),"next":editor._doc._next,"revision":editor._doc.authoring_revision,"dirty":editor._dirty,"selected":editor._selection_tools.ids.duplicate(),"view":editor._view.get_instance_id(),"children":editor._view.get_children().map(func(node):return node.get_instance_id()),"bodies":bodies}
func ready_model(id:String)->Node3D:
	var holder:Node=editor._view.get_node_or_null(NodePath(id))
	if holder==null or holder.get_meta("missing_asset",false) or holder.has_meta("paint_error") or holder.get_child_count()==0:return null
	var model:Node3D=holder.get_child(0)
	return model if Ready.scene_ready(model) else null
func identity(id:String)->Dictionary:
	var model:=ready_model(id)
	if model==null:return {}
	var state:=native_state(model);var meshes:=model.find_children("*","MeshInstance3D",true,false)
	state.packed_id=model.get_meta("_compiled_resource_owner").get_instance_id();state.mesh_id=meshes[0].mesh.get_instance_id()
	return state
func entry(path:String)->Dictionary:
	var value:={"asset_path":path,"label":path.get_file(),"bounds_position":[-1,-1,-1],"bounds_size":[2,2,2]}
	editor._assets.entries.append(value);return value
func pending_ready(count:int)->void:
	var deadline:=Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<deadline:
		editor._asset_operations.set_process(false)
		if editor._asset_operations._operations.size()==count and editor._asset_operations._operations.values().all(func(op):return op.phase=="building"):break
		await process_frame
	check(editor._asset_operations._operations.size()==count,"HTTP requests retain their own pending operation")
	check(editor._asset_operations._operations.values().all(func(op):return op.phase=="building"),"real service completes binding before controlled publication")
func release_ui()->void:
	editor._preview.show_asset("");editor._palette.hide();editor._thumbnails.set_visible_entries([])
func cube_product(prepared:Dictionary,label:String)->String:
	var path:=publish_fixture(original,prepared,label)
	var file:=Footprint.descriptor_path(path,folder);var row:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(file));var body:Dictionary=JSON.parse_string(row.body)
	body.model_metadata.local_bounds=[-1,-1,-1,2,2,2]
	var text:=JSON.stringify(body);write_json(file,{"version":1,"body":text,"sha256":text.sha256_text()})
	owned_paths.append(path);return path

func render_placed(id:String)->void:
	var model:=ready_model(id)
	if model==null:check(false,"placed visual exists for rendered comparison");return
	var source:=viewport(original.duplicate());var target:=viewport(model.duplicate())
	await compare_views(source,target,"placed_native")
	report.render_identity=identity(id)
	check(int(Engine.get_singleton("TextureStreaming").call("get_memory_budget_bytes_used"))>0,"real engine accounts rendered STEX residency")
	source.free();target.free();model=null
	await RenderingServer.frame_post_draw
	capture_file("actual_editor",root.get_texture().get_image())

func run()->void:
	if DisplayServer.get_name()=="headless" or not Prep.Streamed.enabled():quit(2);return
	folder=Prep.Paths.external_root()
	if not folder.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(210).timeout.connect(func():printerr("COLD_OPERATION_GPU watchdog");quit(2));Engine.max_fps=60
	Paint.refresh_sources();original=fixture();var products:=Products.prepare(original,folder)
	check(products.ok and products.stats.textures==1,"actual fine-pattern multi-mip STEX is produced")
	var path:=cube_product(products,"placement_first");var second:=cube_product(products,"placement_second")
	Products.restore(products);products.clear()
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=Document.new();session.world3d_editor_path=""
	editor=load("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=folder.path_join("drafts");root.add_child(editor);editor._safety.enabled=false
	ui_host=editor;service=Service.for_consumer(editor);tracker=Ownership.for_tree(self)
	await seed_ground_batch()
	editor._asset_operations.finished.connect(func(id:int,result:Dictionary):completed[id]=result)
	process_frame.connect(measured_frame)
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real current 3D HTTP server starts")
	var first_entry:=entry(path);var second_entry:=entry(second)
	check(service.native_texture_pool==null and not service.native_texture_preparer.is_valid() and service.ownership_tracker==null,"service uses the real native loader and ownership tracker")
	var discovery:=await receive_rpc(await send_rpc("tools/list"))
	check(["place_asset","undo","redo","save_world","open_world"].all(func(name_):return discovery.result.tools.any(func(tool):return tool.name==name_)),"HTTP discovery contains the unchanged placement/history/save tools")
	var before:=doc_state();await call_tool("place_asset",{"asset_id":path,"position":"invalid"},false)
	check(doc_state()==before,"invalid HTTP placement has no side effects")
	var produced:int=service.profile.producers
	var first:=await send_tool("place_asset",{"asset_id":path,"position":[0,0,0]})
	await pending_ready(1)
	check(doc_state()==before,"cold HTTP wait does not change document/history/UUID/dirty/view/body")
	check(first.peer.get_available_bytes()==0,"HTTP does not publish a pending response as final success")
	editor._asset_operations.set_process(true)
	var placed:=tool_result(await receive_rpc(first));check(placed.get("ok",false),"real HTTP cold placement commits successfully")
	if not placed.get("ok",false):release_ui();editor.free();original.free();finish();return
	var id:String=placed.ids[0];var initial:=identity(id)
	check(not initial.is_empty() and initial.active and initial["class"]=="StreamedTexture2D","committed model has a real READY streamed texture")
	check(editor._doc._undo.size()==1 and service.profile.producers==produced+1,"cold placement owns exactly one transaction and one producer")
	check(Assets._scenes.is_empty(),"private placement leaves the global scene cache empty")
	check(editor._bodies_by_uuid.has(id) and not editor._bodies_by_uuid[id].is_empty(),"real picking/collision bodies publish with the visual")
	await render_placed(id)
	var owner:WeakRef=weakref(ready_model(id).get_meta("_compiled_resource_owner"))
	await call_tool("undo");release_ui();await wait_clean("after_last_place_undo")
	check(owner.get_ref()==null and not service._private_models.values().any(func(row):return row.packed.get_ref()!=null),"true cold redo begins with no live PackedScene or weak-index owner")
	before=doc_state();var redo:=await send_tool("redo");await pending_ready(1)
	check(doc_state()==before,"cold HTTP redo has not consumed history while waiting")
	editor._asset_operations.set_process(true);var redone:=tool_result(await receive_rpc(redo))
	check(redone.get("ok",false) and ready_model(id)!=null,"true cold redo restores the exact record through actual preparation")
	check(identity(id).packed_id!=initial.packed_id and identity(id).id!=initial.id,"cold redo produces fresh packed and native texture identities")
	await ui_case(first_entry)
	await disconnected_case(second)
	await concurrent_case(second)
	await prefab_case_gpu(path,second)
	check(ground_snapshot()==retained_ground,"cold placement/history retain unrelated real merged visuals and collision body identities")
	check(Assets._scenes.is_empty(),"UI/HTTP placement and history never grow the global cache")
	report.before_save={"profile":editor._asset_operations.snapshot(),"service":service.snapshot(),"published":tracker.report()}
	var saved_records:Array=editor._doc.records.duplicate(true);var map_path:=folder.path_join("maps/placed/map.gltf")
	await call_tool("save_world",{"path":map_path})
	check(FileAccess.file_exists(map_path) and not FileAccess.file_exists(path) and not FileAccess.file_exists(second),"real atomic save succeeds with both source GLBs absent")
	var empty_path:=folder.path_join("maps/empty/map.gltf");check(Document.new().save(empty_path)==OK,"external empty map is available for real document switch")
	await call_tool("open_world",{"path":empty_path,"discard_changes":true})
	await call_tool("open_world",{"path":map_path})
	check(editor._doc.records==saved_records,"real HTTP reopen preserves exact records and instance identities")
	check(saved_records.filter(func(record):return record.kind=="asset").all(func(record):return ready_model(str(record.uuid))!=null),"actual LoadJob reopens every saved native instance without GLBs")
	report.frames={"all_max_us":frame_max_us,"operation_max_us":operation_frame_max_us,"scope":"synthetic functional sample, includes cold work and frame scheduling; not a city performance claim"}
	report.http=http_trace;report.final_operations=editor._asset_operations.snapshot()
	release_ui();var ledger:RefCounted=editor._shared_preparation_ledger;editor.free();editor=null;ui_host=null
	for item:String in owned_paths:Assets.evict_cached_scene(item)
	var deadline:=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		tracker.collect_retired(100)
		if ledger.count()==0 and tracker.report().entries==0 and int(Engine.get_singleton("TextureStreaming").call("get_memory_budget_bytes_used"))==0:break
		await process_frame
	check(ledger.count()==0 and ledger.reserved_bytes==0,"final editor exit drains the transient ledger")
	check(tracker.report().entries==0 and tracker.report().published_envelope_bytes==0,"all private published geometry retires after editor exit")
	check(int(Engine.get_singleton("TextureStreaming").call("get_memory_budget_bytes_used"))==0 and native_refs.all(func(ref_):return ref_.get_ref()==null),"final native texture owners and engine residency are zero")
	check(Assets._scenes.is_empty(),"only fixture-owned normal reopen cache entries are retired at teardown")
	original.free();original=null;session.world3d_editor_doc=null;session.world3d_editor_path="";finish()

func ui_case(spec:Dictionary)->void:
	editor._palette_items=[spec];editor._on_palette_selected(0)
	editor._camera.position=Vector3(8,8,12);editor._camera.look_at(Vector3(4,0,0))
	var serial_before:int=editor._asset_operations._serial;var count:int=editor._doc.records.size()
	editor._place(editor._camera.unproject_position(Vector3(7,0,0)),true)
	var request:int=editor._asset_operations._serial;var until:=Time.get_ticks_msec()+15000
	while not completed.has(request) and Time.get_ticks_msec()<until:await process_frame
	check(request>serial_before and completed.get(request,{}).get("ok",false) and editor._doc.records.size()==count+1,"actual palette selection and ray placement use the shared operation")
	release_ui()

func disconnected_case(path:String)->void:
	var before:=doc_state();var produced:int=service.profile.producers
	var gone:=await send_tool("place_asset",{"asset_id":path,"position":[12,0,0]});await pending_ready(1)
	var sibling:=await send_tool("place_asset",{"asset_id":path,"position":[15,0,0]});await pending_ready(2)
	check(service.profile.producers==produced+1,"two real HTTP consumers share one production")
	gone.peer.disconnect_from_host()
	for index:int in 4:await process_frame
	check(editor._asset_operations.snapshot().pending==1 and doc_state()==before,"HTTP disconnect cancels only its uncommitted operation with no side effect")
	editor._asset_operations.set_process(true);var result:=tool_result(await receive_rpc(sibling))
	check(result.get("ok",false) and editor._doc.records.size()==before.records.size()+1 and not service._closed,"connected sibling commits while shared service remains open")

func concurrent_case(path:String)->void:
	var before:=doc_state();var a:=await send_tool("place_asset",{"asset_id":path,"position":[18,0,0]});await pending_ready(1)
	var b:=await send_tool("place_asset",{"asset_id":path,"position":[21,0,0]});await pending_ready(2)
	editor._asset_operations.set_process(true)
	var left:=tool_result(await receive_rpc(a));var right:=tool_result(await receive_rpc(b))
	check(int(left.get("ok",false))+int(right.get("ok",false))==1 and editor._doc.records.size()==before.records.size()+1,"concurrent HTTP placements explicitly reject the sibling whose revision became stale")

func prefab_case_gpu(first:String,second:String)->void:
	var local:=Document.new();local.add_asset({"asset_path":first},Vector3.ZERO);local.add_asset({"asset_path":second},Vector3(3,0,0));local.add_box_silent("block",Vector3(6,1,0),Vector3.ONE)
	var path:=folder.path_join("assets/prefabs/placement_pair.json");write_json(path,{"format":"rmmo_prefab","version":1,"records":local.records,"building_instances":{}})
	var spec:={"prefab_path":path,"label":"native pair"};editor._assets.entries.append(spec)
	var count:int=editor._doc._undo.size();var result:=await call_tool("place_asset",{"asset_id":editor._mcp._ops.asset_id(spec),"position":[25,0,0]})
	check(result.get("ids",[]).size()==3 and editor._doc._undo.size()==count+1,"HTTP prefab publishes editable native/primitive members in one transaction")
	if result.get("ids",[]).size()==3:check(ready_model(result.ids[0])!=null and ready_model(result.ids[1])!=null,"both model members of the actual prefab are READY")
	await call_tool("undo")
	check(editor._place_prefab(spec,Vector3(25,0,0)),"real UI prefab entry accepts the same shared operation")
	var request:int=editor._asset_operations._serial;var deadline:=Time.get_ticks_msec()+15000
	while not completed.has(request) and Time.get_ticks_msec()<deadline:await process_frame
	check(completed.get(request,{}).get("ok",false),"real UI prefab operation finishes successfully")
