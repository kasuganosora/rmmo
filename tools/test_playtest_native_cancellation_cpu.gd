extends "res://tools/test_playtest_native_templates_cpu.gd"
## Real shared request / worker cancellation. Texture registration is the
## existing protocol stub; Net/server/graphical publication remains intercepted.
var sibling_results:Dictionary={}
var cancellation_observations:Array=[]

class Safety extends RefCounted:
	var closing:=false
	func state()->Dictionary:return {"close_pending":closing}

class MutatingDocument extends ProbeDocument:
	var first_build:Callable
	func build(effects:bool=true,templates:Dictionary={})->Node3D:
		var scene:Node3D=super.build(effects,templates)
		if builds.size()==1 and first_build.is_valid():first_build.call()
		return scene

class MutatingSession extends ProbeSession:
	var enter_hook:Callable
	var probe_hook:Callable
	func _begin_probe(serial:int)->void:
		super._begin_probe(serial)
		if probe_hook.is_valid():probe_hook.call()
	func _enter(character:Dictionary,serial:int,clone:RefCounted)->void:
		if enter_hook.is_valid():enter_hook.call()
		super._enter(character,serial,clone)

class LoadingWorld extends Node3D:
	var ready_for_play:=false
	var _camera:Node
	var _player:Node
	func is_world_ready()->bool:return ready_for_play
	func preparation_state()->Dictionary:return {}

func sibling_ready(id:int,result:Dictionary)->void:
	sibling_results[id]={"ok":result.get("ok",false)}

func make_context(label:String,hold:bool)->Dictionary:
	var model:=fixture(label,true);var document:=document_for(model.path)
	var file:=content_root.path_join("maps/"+label+"/map.gltf")
	check(document.save(file)==OK,label+": save isolated authoring map before preparation")
	var editor:=TestEditor.new();editor._doc=document;editor._path=file;editor._safety=Safety.new();root.add_child(editor)
	var service:Node=load(ServicePath).for_consumer(editor);var pool:=ControlledPool.new();pool.hold=hold;configure(service,pool)
	var session:=MutatingSession.new();session.editor=editor;editor.add_child(session)
	session.phase="preparing";session._generation=1;session.spawn=Vector3.ZERO
	session.source_path=file;session._source_document=weakref(document);session._source_revision=document.authoring_revision
	var clone:=MutatingDocument.new();clone.apply_recovery(document.recovery_snapshot());clone.asset_uuid=document.asset_uuid
	return {"model":model,"document":document,"editor":editor,"service":service,"pool":pool,"session":session,"clone":clone,"file":file,"sha":FileAccess.get_sha256(file)}

func wait_condition(condition:Callable,label:String)->void:
	var deadline:=Time.get_ticks_msec()+5000
	while not condition.call() and Time.get_ticks_msec()<deadline:await process_frame
	check(condition.call(),label)

func waiting_case(kind:String)->void:
	sibling_results.clear()
	var context:=make_context("wait_"+kind,true)
	var session:Node=context.session;var editor:Node=context.editor;var service:Node=context.service;var pool:ControlledPool=context.pool
	session._prepare.call_deferred(context.clone,{},1)
	await wait_condition(pool.has_entered,kind+": preparation worker is actually blocked")
	var subscriber:=Node.new();editor.add_child(subscriber)
	var sibling:int=service.request_many([context.model.path],subscriber,sibling_ready)
	var old_request:int=session._asset_request
	var began:=Time.get_ticks_msec()
	match kind:
		"cancel":session.stop()
		"exit":editor.remove_child(session);session.free();session=null;context.session=null
		"revision":context.document.checkpoint_recovery()
		"replacement":editor._doc=Doc.new()
		"path":editor._path+=".changed"
		"close_pending":editor._safety.closing=true
		"native_identity":change_candidate(context.model.path)
	var expected:Dictionary=context.document.recovery_snapshot();var history:int=context.document._undo.size()
	if kind!="native_identity":
		await wait_condition(func():return not is_instance_valid(session) or session._asset_request==0,kind+": this session releases its request without joining the worker")
		check(Time.get_ticks_msec()-began<1000,kind+": cancellation remains nonblocking")
		check(service.ledger.reserved_bytes>0 and not sibling_results.has(sibling),kind+": shared worker stays charged for its other consumer")
	pool.gate.post()
	await wait_condition(func():return sibling_results.has(sibling),kind+": independent consumer gets its own completion")
	await quiet(service,pool)
	if is_instance_valid(session):
		await wait_condition(func():return session.phase in ["idle","failed"],kind+": obsolete playtest leaves preparation")
		# A real late delivery cannot resurrect a stopped generation. The result
		# is deliberately incomplete: the stale guard must reject it first.
		session._assets_prepared(old_request,{"ok":true},1)
		check(not session.entered and session._stage==null and session._asset_handles.is_empty() and session._asset_templates.is_empty(),kind+": no late scene/handles/publication survive")
	check(context.clone.builds.is_empty(),kind+": invalid preparation never constructs a probe or runtime scene")
	check(sibling_results[sibling].ok==(kind!="native_identity") and not service._closed,kind+": session cancellation does not close the shared service")
	check(context.document.recovery_snapshot()==expected and context.document._undo.size()==history and FileAccess.get_sha256(context.file)==context.sha,kind+": source document/history/file remain unchanged")
	check(service.ledger.reserved_bytes==0 and pool.snapshot().consumers==0 and pool.snapshot().outputs==0 and not Assets._scenes.has(context.model.path),kind+": finite accounting retires without a global cache entry")
	cancellation_observations.append({"case":kind,"profile":service.profile.duplicate(),"phase":session.phase if is_instance_valid(session) else "destroyed","native_builds":context.clone.builds.size(),"source_sha":context.sha})
	service.close();editor.free();context={};await process_frame

func late_case(kind:String)->void:
	var context:=make_context("late_"+kind,false)
	if kind=="probe_identity":context.clone.first_build=change_candidate.bind(context.model.path)
	elif kind=="enter_identity":context.session.enter_hook=change_candidate.bind(context.model.path)
	elif kind=="probe_revision":context.clone.first_build=context.document.checkpoint_recovery
	else:context.clone.records[0].position[1]=-10
	var expected:Dictionary=context.document.recovery_snapshot()
	await run_preparation(context.session,context.clone)
	check(context.session.phase=="failed" and not context.session.entered and context.session.play_scene==null,kind+": late invalidation never publishes the play scene")
	check(context.clone.builds.size()==1 and not context.clone.builds[0].missing_asset,kind+": first probe was fully prepared and final build is refused")
	check(context.session._stage==null and context.session._asset_handles.is_empty() and context.session._asset_templates.is_empty(),kind+": failed probe drops scene and template owners")
	await quiet(context.service,context.pool);await retired(PublishedGeometry.for_tree(self),context.session.native_owners)
	check(context.document.recovery_snapshot()==expected and FileAccess.get_sha256(context.file)==context.sha,kind+": no authoring or formal file publication")
	check(not Assets._scenes.has(context.model.path) and context.service.ledger.reserved_bytes==0,kind+": no global cache or transient lease remains")
	cancellation_observations.append({"case":kind,"phase":context.session.phase,"builds":context.clone.builds.duplicate(true),"error":context.session.last_error})
	context.service.close();context.editor.free();context={};await process_frame

func dedup_and_procedural()->void:
	var context:=make_context("dedup",false)
	var original:String=context.model.path
	context.clone.add_asset({"asset_path":original.replace("/assets/","/assets/../assets/")},Vector3(7,0,0))
	context.clone.records[-1].collision="none"
	await run_preparation(context.session,context.clone)
	check(context.session.entered and context.service.profile.requests==1 and context.service.profile.producers==1,"Dictionary path dedup requests one model for two differently spelled references")
	check(context.clone.builds[0].prepared_templates==2 and context.clone.builds[1].prepared_templates==2,"both original document spellings map to the same ready template")
	var first:Node=context.session.play_scene.get_node(NodePath(context.clone.asset_uuid)).get_child(0)
	var second:Node=context.session.play_scene.get_node(NodePath(context.clone.records[-1].uuid)).get_child(0)
	check(first.get_meta("_compiled_resource_owner")==second.get_meta("_compiled_resource_owner"),"distinct authored instances share one PackedScene allocation")
	Drainer.dispose_scene(context.session.play_scene);context.session.play_scene=null
	await quiet(context.service,context.pool);await retired(PublishedGeometry.for_tree(self),context.session.native_owners)
	context.service.close();context.editor.free();context={};await process_frame
	var document:=Doc.new();document.add_box("ground",Vector3(0,-.1,0),Vector3(20,.2,20))
	var editor:=TestEditor.new();editor._doc=document;root.add_child(editor)
	var session:=ProbeSession.new();session.editor=editor;editor.add_child(session)
	session.phase="preparing";session._generation=1;session._source_document=weakref(document);session._source_revision=document.authoring_revision;session.source_path=editor._path
	await run_preparation(session,document)
	check(session.entered and editor.get_node_or_null("EditorAssetPreparation")==null,"procedural-only playtest retains its direct build path without creating a model service")
	Drainer.dispose_scene(session.play_scene);session.play_scene=null;editor.free();await process_frame

func interrupt_probe(context:Dictionary,kind:String)->void:
	if kind=="stop":context.session.stop()
	elif kind=="session_exit":context.session.queue_free()
	else:context.editor.queue_free()

func probe_exit_case(kind:String)->void:
	var context:=make_context("probe_"+kind,false)
	var ledger:RefCounted=context.service.ledger;var pool:ControlledPool=context.pool
	context.session.probe_hook=interrupt_probe.bind(context,kind)
	context.session._prepare(context.clone,{},1)
	await wait_condition(func():return not is_instance_valid(context.session) or context.session.phase=="idle",kind+": stop/exit completes during the physics wait")
	await settle(ledger,pool)
	check(context.clone.builds.size()==1,kind+": cancelled physics wait never builds the runtime root")
	check(FileAccess.get_sha256(context.file)==context.sha,kind+": cancelled physics wait preserves the formal map")
	if is_instance_valid(context.editor):context.editor.free()
	context={};await physics_frame;await process_frame

func loading_case(kind:String)->void:
	var net=preload("res://scripts/net/net.gd")
	var original_server:Node=net.server();var original_override:Node=net._server_override
	var original_mode:int=original_server.process_mode;var original_path:String=net.session().world3d_map_path
	var editor:=TestEditor.new();root.add_child(editor)
	var session:=ProbeSession.new();session.editor=editor;editor.add_child(session)
	var world:=LoadingWorld.new();session.add_child(world);session.world=world
	world._player=Node3D.new();world.add_child(world._player)
	session._source_server=original_server;session._source_mode=original_mode;session._override_before=original_override
	session._editor_mode=editor.process_mode;session._session_before={"world3d_map_path":original_path}
	session.server=Node.new();session.add_child(session.server);net._server_override=session.server
	net.session().world3d_map_path="private_loading_fixture";net.session().editor_playtest=session
	original_server.process_mode=Node.PROCESS_MODE_DISABLED;editor.process_mode=Node.PROCESS_MODE_DISABLED
	var directory:=Binding.Paths.cache_directory("playtests").path_join("cpu_loading_"+kind+"_"+str(OS.get_process_id()))
	write(directory.path_join("map.gltf"),"{}");session.directory=directory;session.map_path=directory.path_join("map.gltf")
	session.phase="loading";session._generation=1;session._begin_loading_wait(1)
	check(session.is_processing() and session.phase=="loading",kind+": actual loading readiness poll is active")
	if kind=="ready":
		world.ready_for_play=true
		await wait_condition(func():return session.phase=="running",kind+": ready world reaches running")
		check(not session.is_processing(),"completed loading stops its process poll")
		session.stop()
	elif kind=="stop":session.stop()
	elif kind=="timeout":session._loading_deadline=0
	elif kind=="missing_world":world.free();session.world=null
	elif kind=="session_exit":session.queue_free()
	else:editor.queue_free()
	await wait_condition(func():return net.session().editor_playtest==null,kind+": loading stop/exit restores the real session")
	check(net._server_override==original_override and original_server.process_mode==original_mode and net.session().world3d_map_path==original_path,kind+": original server mode and map survive loading shutdown")
	check(not DirAccess.dir_exists_absolute(directory),kind+": owned temporary play map is removed on stop/exit")
	if is_instance_valid(session):check(not session.is_processing() and session.phase in ["idle","failed"],kind+": no late loading publication is possible")
	if is_instance_valid(editor):editor.free()
	await physics_frame;await process_frame

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(120).timeout.connect(func():printerr("PLAYTEST_NATIVE_CANCEL watchdog");quit(2))
	for kind:String in ["cancel","exit","revision","replacement","path","close_pending","native_identity"]:await waiting_case(kind)
	for kind:String in ["probe_identity","enter_identity","probe_revision","unsupported_spawn"]:await late_case(kind)
	await dedup_and_procedural()
	for kind:String in ["stop","session_exit","editor_exit"]:await probe_exit_case(kind)
	for kind:String in ["ready","stop","timeout","missing_world","session_exit","editor_exit"]:await loading_case(kind)
	write(content_root.get_base_dir().path_join("observations.json"),JSON.stringify({"checks":checks,"failures":failures,"cases":cancellation_observations},"\t"))
	print("PLAYTEST_NATIVE_CANCEL checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
