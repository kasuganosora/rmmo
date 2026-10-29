extends "res://tools/test_playtest_native_gpu.gd"
## Additional real-world lifecycle observation; no fake World3D implementation.
class LoadingSession extends SessionObserver:
	var loading_observer:Callable
	func _begin_loading_wait(generation:int)->void:
		super._begin_loading_wait(generation)
		if loading_observer.is_valid():loading_observer.call()

func run_session(label:String,via_ui:bool,expected:Dictionary={})->Dictionary:
	var result:=await super.run_session(label,via_ui,expected)
	if label=="cold_http":await stop_during_loading()
	return result

func stop_during_loading()->void:
	var source_server:Node=Net.server();var before:Dictionary=editor._doc.recovery_snapshot();var map_sha:=FileAccess.get_sha256(map_path)
	editor._playtest.free();editor._playtest=LoadingSession.new();editor._playtest.editor=editor;editor._playtest.observe=observed;editor.add_child(editor._playtest)
	var reached:={"loading":false,"world":WeakRef.new(),"temporary":""}
	editor._playtest.loading_observer=func():
		reached.loading=editor._playtest.phase=="loading" and not editor._playtest.world.is_world_ready()
		reached.world=weakref(editor._playtest.world);reached.temporary=editor._playtest.map_path
		editor._playtest.stop()
	await call_tool("start_playtest",{"position":[0,0,5]})
	await wait_phase("idle")
	for _frame:int in 4:await process_frame
	check(reached.loading,"real gameplay world was stopped during loading")
	check(reached.world.get_ref()==null and not FileAccess.file_exists(reached.temporary),"loading stop releases runtime world and temporary map")
	check(Net.server()==source_server and editor._doc.recovery_snapshot()==before and FileAccess.get_sha256(map_path)==map_sha,"loading stop restores source server and preserves authoring state")
	report.real_loading_stop={"reached_loading":reached.loading,"world_expired":reached.world.get_ref()==null}

func before_editor_free()->void:
	var source_server:Node=Net.server();var document:RefCounted=editor._doc;var before:Dictionary=document.recovery_snapshot();var map_sha:=FileAccess.get_sha256(map_path)
	var ledger:RefCounted=service.ledger;var service_ref:WeakRef=weakref(service)
	var reached:={"loading":false,"world":WeakRef.new(),"session":weakref(editor._playtest),"temporary":""}
	editor._playtest.loading_observer=func():
		reached.loading=editor._playtest.phase=="loading" and not editor._playtest.world.is_world_ready()
		reached.world=weakref(editor._playtest.world);reached.temporary=editor._playtest.map_path
		editor.queue_free()
	check(editor._playtest.start([0,0,5]).ok,"public start accepts owner-exit loading sample")
	var deadline:=Time.get_ticks_msec()+20000
	while is_instance_valid(editor) and Time.get_ticks_msec()<deadline:await process_frame
	for _frame:int in 4:await process_frame
	check(reached.loading and not is_instance_valid(editor),"actual editor owner exits during real gameplay loading")
	check(reached.world.get_ref()==null and reached.session.get_ref()==null and not FileAccess.file_exists(reached.temporary),"owner exit releases world/session and its private map")
	check(Net.server()==source_server and document.recovery_snapshot()==before and FileAccess.get_sha256(map_path)==map_sha,"owner exit preserves original server and authoring data")
	deadline=Time.get_ticks_msec()+20000
	var streaming:Object=Engine.get_singleton("TextureStreaming")
	while Time.get_ticks_msec()<deadline:
		tracker.collect_retired(100)
		if owned_refs.all(func(reference:WeakRef):return reference.get_ref()==null) and tracker.report().entries==0 and ledger.reserved_bytes==0 and streaming.call("get_memory_budget_bytes_used")==0:break
		await process_frame
	check(service_ref.get_ref()==null and owned_refs.all(func(reference:WeakRef):return reference.get_ref()==null),"editor exit releases its service and all native graph owners")
	check(tracker.report().entries==0 and ledger.reserved_bytes==0 and streaming.call("get_memory_budget_bytes_used")==0,"editor exit drains published/transient/engine accounting")
	report.real_loading_owner_exit={"reached_loading":reached.loading,"tracker":tracker.report(),"transient_bytes":ledger.reserved_bytes,"engine_bytes":streaming.call("get_memory_budget_bytes_used")}
	owned_refs.clear()
