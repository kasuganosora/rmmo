extends "res://tools/test_editor_native_sequential_requests.gd"
## Real preparation and fresh runtime build, intercepted before Net/server/UI
## publication. Public start still rejects headless. Split upload is a stub.
const Stream=preload("res://scripts/world3d/world_stream.gd")
var playtest_observations:Array=[]

class Guard extends RefCounted:
	func guard()->Dictionary:return {"ok":true}
class TestEditor extends Node3D:
	var _shared_preparation_ledger=Admission.new()
	var _gameplay=Guard.new()
	var _status:=Label.new()
	var _doc:RefCounted
	var _path:="cpu_playtest_map"
	var _safety:RefCounted
	var _mcp:Node
	var finish_edits_calls:=0
	func _ready()->void:add_child(_status)
	func _finish_edits()->void:finish_edits_calls+=1

class ProbeDocument extends "res://scripts/world3d/world_document.gd":
	var builds:Array=[]
	var asset_uuid:String
	func build(effects:bool=true,prepared_assets:Dictionary={})->Node3D:
		var scene:Node3D=super.build(effects,prepared_assets)
		var holder:=scene.get_node_or_null(NodePath(asset_uuid))
		var model:Node=holder.get_child(0) if holder!=null and holder.get_child_count()>0 else null
		var packed:PackedScene=model.get_meta("_compiled_resource_owner") if model!=null and model.has_meta("_compiled_resource_owner") else null
		builds.append({"root_id":str(scene.get_instance_id()),"holder_id":str(holder.get_instance_id()) if holder!=null else "","model_id":str(model.get_instance_id()) if model!=null else "","packed_id":str(packed.get_instance_id()) if packed!=null else "","missing_asset":holder==null or holder.get_meta("missing_asset",false),"paint_error":holder.get_meta("paint_error","") if holder!=null else "missing holder","prepared_templates":prepared_assets.size()})
		return scene

class ProbeSession extends "res://scripts/world_editor/playtest_session.gd":
	var entered:=false
	var play_scene:Node3D
	var native_owners:Array=[]
	var stage_observations:Array=[]
	var probe_order:Array=[]
	func _probe_physics_ready(serial:int)->void:
		probe_order.append("physics")
		super._probe_physics_ready(serial)
	func _finish_probe(serial:int)->void:
		probe_order.append("process")
		super._finish_probe(serial)
	func _begin_probe(serial:int)->void:
		super._begin_probe(serial)
		_observe_stage()
	func _process(_delta:float)->void:
		super._process(_delta)
		_observe_stage()
	func _observe_stage()->void:
		if _stage!=null:
			var bodies:=_stage.find_children("*","StaticBody3D",true,false)
			var host:=_stage.get_child(0);var map_root:=host.get_child(0)
			stage_observations.append({"body_ids":bodies.map(func(body:Node):return str(body.get_instance_id())),"body_count":bodies.size(),"bodies_are_host_children":bodies.all(func(body:Node):return body.get_parent()==host),"physics_space":str(host.get_world_3d().space),"stream_bodies":map_root.get_meta("stream_bodies",{}).size(),"stream_library":map_root.get_meta("stream_library",[]).size(),"shape_ids":bodies.map(func(body:Node):return str(body.get_child(0).shape.get_instance_id()))})
	func _enter(_character:Dictionary,serial:int,clone:RefCounted)->void:
		for handle:Variant in _asset_handles.values():native_owners.append(weakref(handle.packed))
		play_scene=_build_play_scene(clone,serial)
		if play_scene!=null:entered=true;phase="probe_completed"
		set_process(false)

func delete_authoring_source(model:Dictionary)->Dictionary:
	var candidate:=Assets.native_candidate(model.path,content_root)
	var packed:PackedScene=ResourceLoader.load(candidate.product,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var scene:=packed.instantiate()
	var gltf:=GLTFDocument.new();var state:=GLTFState.new()
	check(gltf.append_from_scene(scene,state)==OK and gltf.write_to_filesystem(state,model.path)==OK,"create actual historical GLB fixture before deletion")
	scene.free()
	var source_sha:=FileAccess.get_sha256(model.path)
	var index:=Compiled.index_path(model.path,content_root)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(index));manifest.source_sha=source_sha
	write(index,JSON.stringify(manifest))
	var descriptor:=Footprint.descriptor_path(model.path,content_root)
	var wrapper:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(descriptor))
	var body:Dictionary=JSON.parse_string(wrapper.body);body.source_sha=source_sha
	wrapper.body=JSON.stringify(body);wrapper.sha256=str(wrapper.body).sha256_text();write(descriptor,JSON.stringify(wrapper))
	check(DirAccess.remove_absolute(model.path)==OK and not FileAccess.file_exists(model.path),"delete only this test's historical authoring GLB")
	check(not Assets.native_candidate(model.path,content_root).is_empty(),"published native remains valid with authoring GLB deleted")
	return {"source_sha":source_sha,"authoring_exists":false,"product":candidate.product}

func document_for(path:String)->ProbeDocument:
	var document:=ProbeDocument.new()
	document.add_box("ground",Vector3(0,-.1,0),Vector3(20,.2,20))
	document.asset_uuid=document.add_asset({"asset_path":path},Vector3(4,0,0))
	document.records[-1].collision="none"
	return document

func probe_prepare(editor:Node,document:ProbeDocument,label:String)->Dictionary:
	editor._doc=document
	var session:=ProbeSession.new();session.editor=editor;editor.add_child(session)
	var denied:Dictionary=session.start()
	check(not denied.get("ok",true) and str(denied.get("error","")).contains("图形"),label+": real public start explicitly rejects headless")
	var clone:=ProbeDocument.new();clone.apply_recovery(document.recovery_snapshot());clone.asset_uuid=document.asset_uuid
	session.phase="preparing";session._generation=1;session.spawn=Vector3.ZERO
	session.source_path=editor._path;session._source_document=weakref(document);session._source_revision=document.authoring_revision
	Trace.start()
	await run_preparation(session,clone)
	var result:={"label":label,"public_start":denied,"entered_boundary":session.entered,"phase":session.phase,"error":session.last_error,"builds":clone.builds.duplicate(true),"physics_stage":session.stage_observations.duplicate(true),"native_owners":session.native_owners}
	check(clone.builds.size()==2,label+": actual probe and production play builder execute two fresh builds")
	check(session._asset_handles.is_empty() and session._asset_templates.is_empty() and session._asset_request==0,label+": final scene owns the model after preparation handles are released")
	check(session.probe_order==["physics","process"],label+": a real physics frame precedes the process-frame spawn check")
	check(session.entered and session._stage==null,label+": actual spawn probe passes and destroys isolated physics stage before enter boundary")
	check(not session.stage_observations.is_empty() and session.stage_observations[0].body_count>0,label+": spawn probe actually creates physics bodies")
	var first_stage:Dictionary=session.stage_observations[-1]
	check(first_stage.bodies_are_host_children and first_stage.body_ids.all(func(id:String):return not is_instance_id_valid(int(id))),label+": derived bodies belong to probe host and are gone before enter")
	# The actual production _build_play_scene has already built this root and
	# released its handles. Keep the graphical/session publication intercepted.
	var second:Node3D=session.play_scene;session.play_scene=null
	result.second_build=clone.builds[-1].duplicate(true)
	check(clone.builds.size()==2 and clone.builds[0].root_id!=clone.builds[1].root_id and clone.builds[0].holder_id!=clone.builds[1].holder_id,label+": second build creates fresh nodes rather than transferring probe state")
	# Exercise the same Stream.sync boundary in a second isolated world. It is
	# deliberately not _enter or the gameplay scene's event initialization.
	var second_stage:=SubViewport.new();second_stage.own_world_3d=true;second_stage.disable_3d=true;root.add_child(second_stage)
	var host:=Node3D.new();second_stage.add_child(host);host.add_child(second)
	Stream.sync(second,host,Vector3(0,.9,0));await physics_frame;await process_frame
	var bodies:=second_stage.find_children("*","StaticBody3D",true,false)
	result.second_physics={"body_ids":bodies.map(func(body:Node):return str(body.get_instance_id())),"body_count":bodies.size(),"physics_space":str(host.get_world_3d().space),"shape_ids":bodies.map(func(body:Node):return str(body.get_child(0).shape.get_instance_id())),"stream_bodies":second.get_meta("stream_bodies",{}).size()}
	check(result.second_physics.body_count==first_stage.body_count and result.second_physics.physics_space!=first_stage.physics_space and result.second_physics.body_ids.all(func(id:String):return not first_stage.body_ids.has(id)),label+": second root derives new bodies in a distinct physics world")
	second_stage.free();second=null
	result.native_reads=native_reads(Trace.stop())
	result.document_unchanged=clone.recovery_snapshot().records==document.recovery_snapshot().records
	check(result.document_unchanged,label+": build/probe preserve authored records")
	session.free();await process_frame
	return result

func run_preparation(session:Node,clone:RefCounted)->void:
	session._prepare(clone,{},1)
	var deadline:=Time.get_ticks_msec()+5000
	while is_instance_valid(session) and session.phase=="preparing" and Time.get_ticks_msec()<deadline:await process_frame
	check(is_instance_valid(session) and session.phase!="preparing","preparation reaches a finite result")

func publish_existing_template(path:String,reference:WeakRef)->bool:
	var packed:PackedScene=reference.get_ref()
	var candidate:=Assets.native_candidate(path,content_root)
	return Assets.cache_packed(path,packed,candidate.source_sha,candidate)

func prepared_build(document:ProbeDocument,path:String,reference:WeakRef)->Dictionary:
	var scene:=private_document_view(document,path,reference)
	var result:Dictionary=document.builds[-1].duplicate(true)
	Drainer.dispose_scene(scene)
	return result

func private_document_view(document:ProbeDocument,path:String,reference:WeakRef)->Node3D:
	var packed:PackedScene=reference.get_ref()
	return document.build(true,{path:packed})

func split_playtest_cases()->void:
	var model:=fixture("playtest_split",true)
	var source:=delete_authoring_source(model)
	var editor:=TestEditor.new();root.add_child(editor)
	var consumer:=Node.new();editor.add_child(consumer)
	var service:Node=load(ServicePath).for_consumer(consumer)
	var pool:=ControlledPool.new();configure(service,pool)
	var first:=await capture_scene(service,consumer,editor,model.path)
	await quiet(service,pool)
	check(first.get("ok",false) and not Assets._scenes.has(model.path) and expired(first.handle),"private native scene outlives its handle without a global cache entry")
	var document:=document_for(model.path)
	var view:=private_document_view(document,model.path,first.packed);editor.add_child(view)
	Drainer.dispose_scene(first.scene);first.scene=view;view=null;await quiet(service,pool)
	check(not document.builds[-1].missing_asset and document.builds[-1].packed_id==first.packed_id and not expired(first.packed),"real WorldDocument view now owns the live native template after the service scene retires")
	var live:=await probe_prepare(editor,document,"private_live")
	live.source=source;live.service=service.snapshot()
	check(not live.builds[0].missing_asset and not live.second_build.missing_asset,"private live split appears correctly in both playtest roots")
	check(live.native_reads==0 and service.profile.producers==1,"private live playtest shares the existing allocation without native reads or another producer")
	check(live.entered_boundary and live.physics_stage[0].body_count==1,"playtest uses the authored collision-none model rather than a colliding placeholder")
	var before_live:int=service.profile.producers
	var borrowed:=await capture_scene(service,consumer,editor,model.path);await quiet(service,pool)
	check(borrowed.packed_id==first.packed_id and service.profile.producers==before_live and service.profile.private_reused==2,"playtest and another consumer both reuse the live private READY template")
	Drainer.dispose_scene(borrowed.scene);borrowed={};await quiet(service,pool)
	var explicit:=prepared_build(document,model.path,first.packed)
	check(not explicit.missing_asset and explicit.packed_id==first.packed_id and not Assets._scenes.has(model.path),"existing prepared_assets API builds correct private model without growing global cache")
	live.prepared_template_control=explicit;playtest_observations.append(live)
	check(publish_existing_template(model.path,first.packed),"same publication boundary used by LoadJob warms global native template")
	var cached:=await probe_prepare(editor,document,"global_warm")
	check(not cached.builds[0].missing_asset and not cached.second_build.missing_asset,"global cache source masks both cold split playtest failures")
	check(cached.builds[0].packed_id==first.packed_id and cached.second_build.packed_id==first.packed_id,"both warm playtest builds share existing native allocation but instantiate separate nodes")
	check(cached.native_reads==0,"global warm builds do not read geometry again")
	playtest_observations.append(cached)
	Assets.evict_cached_scene(model.path)
	var refs:Array=[first.packed,first.mesh];var scenes:Array=[first.scene];first={}
	clear_owned(scenes,[]);await quiet(service,pool);await retired(PublishedGeometry.for_tree(self),refs)
	check(refs.all(expired) and not Assets._scenes.has(model.path),"all original private and global native owners are gone before cold case")
	var cold_before:int=service.profile.producers
	var cold:=await probe_prepare(editor,document,"fully_cold")
	check(not cold.builds[0].missing_asset and not cold.second_build.missing_asset,"fully cold split builds both correct roots without GLB")
	check(cold.native_reads==1 and service.profile.producers==cold_before+1,"fully cold split reads and prepares once for both roots")
	await quiet(service,pool);await retired(PublishedGeometry.for_tree(self),cold.native_owners)
	check(cold.native_owners.all(expired),"cold playtest drops every template owner after its final scene retires")
	var before:int=service.profile.producers
	var next:=await capture_scene(service,consumer,editor,model.path);await quiet(service,pool)
	var recovered:=prepared_build(document,model.path,next.packed)
	check(service.profile.producers==before+1 and not recovered.missing_asset,"same shared service prepares expired model and existing private build API recovers it")
	cold.prepared_template_control=recovered;cold.service=service.snapshot();playtest_observations.append(cold)
	refs=[next.packed,next.mesh];scenes=[next.scene];next={}
	clear_owned(scenes,[]);await quiet(service,pool);await retired(PublishedGeometry.for_tree(self),refs)
	check(refs.all(expired) and service.ledger.reserved_bytes==0 and pool.snapshot().consumers==0 and PublishedGeometry.for_tree(self).report().entries==0,"final prepared control releases all private models and existing accounting owners")
	service.close();editor.free();await process_frame

func embedded_control()->void:
	var model:=fixture("playtest_embedded",false);var source:=delete_authoring_source(model)
	var editor:=TestEditor.new();root.add_child(editor)
	var service:Node=load(ServicePath).for_consumer(editor);var pool:=ControlledPool.new();configure(service,pool)
	var result:=await probe_prepare(editor,document_for(model.path),"embedded_cold")
	check(not result.builds[0].missing_asset and not result.second_build.missing_asset and not Assets._scenes.has(model.path),"ordinary embedded native also prepares privately without global cache growth")
	check(result.native_reads==1 and service.profile.producers==1,"embedded native reads once for both private roots")
	await quiet(service,pool);await retired(PublishedGeometry.for_tree(self),result.native_owners)
	result.source=source;playtest_observations.append(result)
	service.close();editor.free();await process_frame

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(75).timeout.connect(func():printerr("PLAYTEST_NATIVE_CPU watchdog");quit(2))
	await split_playtest_cases();await embedded_control()
	write(content_root.get_base_dir().path_join("observations.json"),JSON.stringify({"checks":checks,"failures":failures,"cases":playtest_observations},"\t"))
	print("PLAYTEST_NATIVE_CPU checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
