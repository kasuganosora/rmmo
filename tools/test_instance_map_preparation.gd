extends SceneTree
const Real=preload("res://scripts/net/real_server.gd")
const Net=preload("res://scripts/net/net.gd")
const Loading=preload("res://scripts/ui/loading_screen.gd")
const World=preload("res://scripts/world3d/world_3d.gd")
var failures:=0

class Server extends Real:
	signal release_read
	var delay_read:=false
	var descriptor:Dictionary={}
	var resources:Dictionary={"test/root":"/tmp/root.gltf","test/child":"/tmp/child.gltf","test/world":"/tmp/world.gltf"}
	var reads:=0
	var ready_calls:=0
	func request_api(_path:String,_method:int=HTTPClient.METHOD_GET,_body:Dictionary={})->Dictionary:
		reads+=1
		var response:={"ok":true,"body":descriptor.duplicate(true)}
		if delay_read:await release_read
		return response
	func resolve_map(reference:String)->String:return str(resources.get(reference,""))
	func rpc_call(_operation:String,_body:Dictionary={})->Dictionary:return {"ok":true}
	func confirm_world_ready(_map_ref:String)->Dictionary:
		ready_calls+=1;return {"ok":true}

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func runtime(resource:String,nonce:String,root_resource:String="")->String:
	return "_instance/"+resource.to_utf8_buffer().hex_encode()+"_"+nonce+("_"+root_resource.to_utf8_buffer().hex_encode() if not root_resource.is_empty() else "")
func scope(server:Node,reference:String,generation:int=1)->void:
	server.world_session={"boot_id":"map-test","session_epoch":1,"map_generation":generation,"map_ref":reference}
	server.self_actor={"id":"42","generation":generation,"location":{"map_ref":reference,"position_m":{"x":0,"y":0,"z":0}}}
func capture(server:Node,result:Dictionary)->void:
	result.value=await server.prepare_authoritative_map();result.done=true

func run()->void:
	var server:=Server.new();root.add_child(server);Net._server_override=server
	var nonce:="a".repeat(32)
	var root_run:=runtime("test/root",nonce)
	scope(server,root_run)
	server.descriptor={"template_map":"test/root","current":{"instance_id":root_run,"template_map":"test/root"}}
	var result:Dictionary=await server.prepare_authoritative_map()
	check(result.ok and server._map_path=="/tmp/root.gltf" and server.world_session.map_ref==root_run,"root instance resolves authority template without changing runtime identity")
	var child_run:=runtime("test/child",nonce,"test/root")
	scope(server,child_run,2);server.descriptor.template_map="test/child"
	result=await server.prepare_authoritative_map()
	check(result.ok and server.prepared_resource_map()=="test/child" and server._map_path=="/tmp/child.gltf","annex uses top-level child template and matching three-part runtime identity")
	var loading:=Loading.new();loading._capture_remote_load_context()
	var scene:=Node3D.new();scene.set_meta("extras",{"map_ref":"test/child"})
	check(loading._accept_remote_loaded_map(scene,"/tmp/child.gltf"),"actual loading-screen gate accepts and stamps prepared instance resource")
	var world:=World.new();world._map_root=scene;world._map_path="/tmp/child.gltf";world._remote_entry_context=server.context()
	check(world._remote_entry_map_matches(),"world Ready gate accepts loader-stamped matching context and connection")
	var other:=Node3D.new();other.set_meta("extras",{"map_ref":"test/root"})
	check(not loading._accept_remote_loaded_map(other,"/tmp/root.gltf"),"loader rejects root resource when current instance room is annex")
	other.set_meta("extras",{})
	check(not loading._accept_remote_loaded_map(other,"/tmp/child.gltf"),"instance resource must carry the authoritative template identity")
	var next_root:=runtime("test/root","b".repeat(32))
	scope(server,runtime("test/child","b".repeat(32),"test/root"),3);server.descriptor.current.instance_id=next_root
	result=await server.prepare_authoritative_map();world._remote_entry_context=server.context()
	check(result.ok and not world._remote_entry_map_matches(),"late world entry cannot relabel an old scene as a different run of the same template")
	loading._capture_remote_load_context()
	check(loading._accept_remote_loaded_map(scene,"/tmp/child.gltf") and world._remote_entry_map_matches(),"fresh loader validation stamps the new instance context")
	server.descriptor.current.instance_id=root_run
	result=await server.prepare_authoritative_map()
	check(not result.ok and server.prepared_resource_map().is_empty() and not loading._accept_remote_loaded_map(scene,"/tmp/child.gltf"),"wrong instance nonce invalidates prior preparation and blocks loading")
	server.descriptor.current.instance_id=next_root;server.descriptor.erase("current")
	result=await server.prepare_authoritative_map()
	check(not result.ok and server.prepared_resource_map().is_empty(),"missing authoritative current instance is rejected")
	server.descriptor.current={"instance_id":next_root,"template_map":"test/root"};server.resources.erase("test/child")
	result=await server.prepare_authoritative_map()
	check(not result.ok and server.prepared_resource_map().is_empty() and server.ready_calls==0,"missing local template cannot publish preparation or send Ready")
	server.resources["test/child"]="/tmp/child.gltf";server.delay_read=true
	var previous:String=Net.session().world3d_map_path
	var pending:={"done":false};capture(server,pending)
	scope(server,"test/world",4);server.release_read.emit();await process_frame
	check(pending.done and not pending.value.ok and Net.session().world3d_map_path==previous,"late instance HTTP after context change cannot overwrite GameSession resource")
	scope(server,child_run,5);server.descriptor.current.instance_id=root_run
	pending={"done":false};capture(server,pending)
	server._connection_revision+=1;server.release_read.emit();await process_frame
	check(pending.done and not pending.value.ok and Net.session().world3d_map_path==previous,"late instance HTTP after connection replacement cannot publish a map")
	server.descriptor.erase("current");pending={"done":false};capture(server,pending)
	server.delay_read=false;server.descriptor.current={"instance_id":root_run,"template_map":"test/root"}
	result=await server.prepare_authoritative_map();server.release_read.emit();await process_frame
	check(result.ok and pending.done and not pending.value.ok and server.prepared_resource_map()=="test/child","late failed preparation preserves a newer successful proof")
	scope(server,"test/world",6);result=await server.prepare_authoritative_map();loading._capture_remote_load_context()
	other.set_meta("extras",{"map_ref":"test/world"})
	check(result.ok and loading._accept_remote_loaded_map(other,"/tmp/world.gltf"),"ordinary authored maps retain their exact identity gate")
	other.set_meta("extras",{})
	check(loading._accept_remote_loaded_map(other,"/tmp/world.gltf") and not loading._accept_remote_loaded_map(other,"/tmp/other.gltf"),"unlabelled legacy world maps retain compatibility only for the prepared file")
	server._connection_revision+=1;result=await server.prepare_authoritative_map()
	check(result.ok and not loading._accept_remote_loaded_map(other,"/tmp/world.gltf"),"old loader cannot stamp a replaced connection even when context matches")
	loading._capture_remote_load_context()
	check(loading._accept_remote_loaded_map(other,"/tmp/world.gltf"),"fresh loading pass accepts the new connection")
	scope(server,"test/world",7)
	check(not loading._accept_remote_loaded_map(other,"/tmp/world.gltf") and server.prepared_resource_map().is_empty(),"ordinary legacy maps still reject unprepared or changed context")
	server.self_actor.location.map_ref="test/root"
	result=await server.prepare_authoritative_map()
	check(not result.ok and server.prepared_resource_map().is_empty(),"old actor position cannot prepare a new authoritative map")
	scope(server,child_run,8);server.delay_read=true
	var notices:Array=[]
	loading.status_label=Label.new();loading.add_child(loading.status_label)
	loading.bar=ProgressBar.new();loading.add_child(loading.bar)
	server.enter_world_ready.connect(loading._on_enter_ready)
	server.enter_world_ready.connect(func(ok:bool,_message:String,_spawn:Dictionary):notices.append(ok))
	server.enter_world3d(42)
	check(server._enter_inflight,"instance admission awaits authoritative template read")
	scope(server,"test/world",9);server.release_read.emit();await process_frame
	check(not server._enter_inflight and notices==[false],"same-connection context change releases enter and notifies its waiter exactly once")
	check(not loading.bar.visible and loading.has_node("FailActions") and loading.status_label.text=="服务器世界已变更，请重新进入","loading screen receives cancellation and offers return instead of waiting forever")
	scope(server,child_run,10);server.enter_world3d(42)
	server._connection_revision+=1
	server.release_read.emit();await process_frame
	check(server._enter_inflight and notices==[false],"late enter from replaced connection cannot clear a new guard or notify the new session")
	server._enter_inflight=false
	world.free();scene.free();other.free();loading.free();Net.clear_server_override();server.queue_free()
	print("INSTANCE_MAP_PREPARATION_TESTS failures=",failures);quit(0 if failures==0 else 1)
