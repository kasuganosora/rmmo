extends "res://tools/test_stream_index_append.gd"
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
class Errors extends Logger:
	var errors:Array[String]=[]
	func _log_error(function:String,_file:String,_line:int,code:String,rationale:String,_editor_notify:bool,_type:int,_backtraces:Array)->void:
		errors.append(function+": "+code+" "+rationale)
class PendingCollision extends Node:
	# Selection and commit preflight are distinct gates. A ready selection may
	# race with an installer before Stream.append_specs asks to promote it.
	var selection_pending:=false
	var pending:=true
	var committed:=0
	var preflights:=0
	func has_instances()->bool:return true
	func publication_status(_uuid:String)->Dictionary:
		return {"owned":true,"pending":selection_pending,"error":""}
	func preflight_promotion(_values:Array)->Dictionary:
		preflights+=1
		return {"ok":false,"error":"promotion_collision_pending"} if pending else {"ok":true,"token":{}}
	func commit_promotion(_token:Dictionary)->void:committed+=1
func fixture(native:bool=true)->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	map.set_meta("stream_library",[])
	var data:=Index.build([])
	for key:String in data:map.set_meta(key,data[key])
	var queue:=Deferred.new();map.add_child(queue);queue._map=map;queue.set_process(false)
	var item:Dictionary={"path":"private-fixture","record":{"uuid":"large","kind":"asset"},"native_reference":native,"model_verified":true}
	queue.pending=[item];queue._demanded=[item];queue._demanded_by_id={"large":item};queue._demanded_rank={"large":0};queue._demanded_by_path={"private-fixture":[item]}
	queue._admission.reserve(item.path,{"estimated_bytes":1048576,"exclusive":false});queue._admission.park(item.path)
	queue._jobs[item.path]={"token":Drainer.CancelToken.new(),"result":{}}
	var specs:Array=[];var mesh:=BoxMesh.new()
	for i:int in 600:
		var value:=spec("large__part%d"%i,Vector2i.ZERO,Vector2i.ZERO,{}, {"building":{"id":"building"}})
		value.mesh=mesh;specs.append(value)
	return {"map":map,"queue":queue,"item":item,"specs":specs}
func empty_publication(map:Node)->bool:
	for key:String in ["stream_library","stream_by_id","stream_known","stream_index","stream_prop_index","stream_collision_index","stream_building_groups"]:
		if not map.get_meta(key).is_empty():return false
	return map.get_meta("stream_append_pending",[]).is_empty() and map.get_meta("stream_building_count")==0
func original_identities(map:Node,source:Array)->bool:
	var registered:Dictionary=map.get_meta("stream_by_id")
	if registered.size()!=source.size() or map.get_meta("stream_library").size()!=source.size():return false
	for value:Dictionary in source:
		if not is_same(registered.get(value.uuid),value):return false
	return true
func unannotated(source:Array)->bool:
	for value:Dictionary in source:
		for field:String in ["render_building","render_bounds","render_supports","render_dependents"]:
			if value.has(field):return false
	return true
func ready_cursor(cursor:RefCounted,source:Array)->bool:
	return cursor.valid_runtime_owned(source) if cursor.runtime_owned else cursor.valid_for(source)
func fixture_leaf(source:Array)->void:
	var leaf:Dictionary=source[0]
	leaf.closed_transform=leaf.transform;leaf.position=leaf.transform.origin
	leaf.extras.fixture={"id":"door","kind":"door","pivot":[1.,0.,0.],"angle":90.,"open":0.}
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var original_private_mode:bool=Deferred.private_publication_packet_enabled
	var fixture_:Dictionary=fixture();var queue:Node=fixture_.queue;var map:Node=fixture_.map
	var source:Array=fixture_.specs;var item:Dictionary=fixture_.item
	var emissions:Dictionary={"count":0,"size":0}
	queue.published.connect(func(values:Array):emissions.count+=1;emissions.size=values.size())
	check(not queue._publish_items([item],source) and not item.get("published",false) and map.get_meta("stream_library").is_empty(),"large actual publication first yields with no visible partial namespace")
	var calls:=1
	while not item.get("published",false) and calls<10000:
		queue._publish_items([item],source);calls+=1
	check(item.get("published",false) and calls>1 and emissions.count==1 and emissions.size==600,"all prepared parts publish exactly once through the actual queue")
	check(map.get_meta("stream_library").size()==600 and queue.pending.is_empty() and queue._jobs[item.path].collision_staged.is_empty(),"successful append transfers every identity and clears only staging ownership")
	check(queue._admission.reserved_bytes==1048576,"private preparation never releases the admitted job reservation")
	queue._discard_job(item.path);check(queue._admission.reserved_bytes==0,"normal post-publication discard releases its original reservation")
	map.free();fixture_={};source=[];item={}
	fixture_=fixture();queue=fixture_.queue;map=fixture_.map;item=fixture_.item;source=fixture_.specs
	queue._publish_items([item],source)
	var packet:Dictionary=queue._jobs[item.path].collision_staged[item.record.uuid]
	while not packet.index_preparation.advance(100):pass
	source[0].transform.origin+=Vector3.RIGHT
	check(not queue._publish_items([item],source) and queue.profile.get("index_preparation_restarts",0)==1 and queue.instance_errors.is_empty() and map.get_meta("stream_library").is_empty(),"pose mutation after preparation retries without failing the owner or touching the public index")
	var passes:=0
	while not item.get("published",false) and passes<10000:queue._publish_items([item],source);passes+=1
	check(item.get("published",false) and map.get_meta("stream_by_id")[source[0].uuid].transform==source[0].transform,"retry publishes the latest pose under the original complete namespace")
	map.free();fixture_={};source=[];item={};packet={}
	fixture_=fixture();queue=fixture_.queue;map=fixture_.map;item=fixture_.item;source=fixture_.specs
	Index.build(source)
	check(queue._publish_items([item],source) and item.published and map.get_meta("stream_library").size()==600,"already-derived input retains the ordinary validated append path instead of donating an unsafe fragment")
	map.free();fixture_={};source=[];item={}
	fixture_=fixture();queue=fixture_.queue;map=fixture_.map;item=fixture_.item;source=fixture_.specs
	queue._publish_items([item],source)
	var watch:WeakRef=weakref(source[0].mesh);var ledger:RefCounted=queue._admission
	fixture_={};source=[];item={};map.free()
	check(watch.get_ref()==null and ledger.reserved_bytes==0,"map exit disposes the partially built index, private specs and their admission lease")
	for private_mode:bool in [false,true]:
		Deferred.private_publication_packet_enabled=private_mode
		var label:="private packet" if private_mode else "owned snapshot"
		for cancel:bool in [false,true]:
			fixture_=fixture(false);queue=fixture_.queue;map=fixture_.map;item=fixture_.item;source=fixture_.specs
			if private_mode:fixture_leaf(source)
			emissions={"count":0,"size":0}
			queue.published.connect(func(values:Array):emissions.count+=1;emissions.size=values.size())
			queue._publish_items([item],source);packet=queue._jobs[item.path].collision_staged[item.record.uuid]
			while not packet.index_preparation.advance(100):pass
			var previous_cursor:RefCounted=packet.index_preparation
			check(previous_cursor.owns_projection and previous_cursor.runtime_owned==private_mode and ready_cursor(previous_cursor,source),label+" uses the intended valid, exclusively owned cursor")
			if cancel:
				queue._discard_job(item.path)
				check(unannotated(source) and queue._admission.reserved_bytes==0 and empty_publication(map) and emissions.count==0,label+" cancellation clears every private annotation and lease while an external packet alias remains")
			else:
				# The public snapshot path supports arbitrary caller pose mutation.
				# The private runtime contract has one pose writer: fixture state.
				# Exercise that actual writer instead of mutating its private array.
				if private_mode:queue.runtime_fixture_states.large=1.
				else:source[0].transform.origin+=Vector3.RIGHT
				check(not queue._publish_items([item],source) and unannotated(source) and not packet.has("index_preparation") and queue.profile.get("index_preparation_restarts",0)==1 and empty_publication(map) and emissions.count==0,label+" stale retry disposes the original cursor without exposing any partial namespace")
				check(not previous_cursor.owns_projection and queue.instance_errors.is_empty() and queue._admission.reserved_bytes==1048576,label+" retry retains its job lease without failing the instance")
				passes=0
				while not item.get("published",false) and passes<10000:queue._publish_items([item],source);passes+=1
				check(item.get("published",false) and source[0].has("render_building") and original_identities(map,source) and emissions.count==1 and emissions.size==600,label+" retry publishes all 600 original runtime identities exactly once")
				if private_mode:
					var leaf:Dictionary=source[0]
					check(leaf.extras.fixture.open==1. and leaf.transform==Fixtures.pose(leaf.closed_transform,leaf.extras.fixture,1.) and leaf.transform!=leaf.closed_transform,label+" retry commits the actual latest fixture pose")
			map.free();fixture_={};source=[];item={};packet={};previous_cursor=null
		fixture_=fixture(false);queue=fixture_.queue;map=fixture_.map;item=fixture_.item;source=fixture_.specs
		emissions={"count":0,"size":0}
		queue.published.connect(func(values:Array):emissions.count+=1;emissions.size=values.size())
		var collision:=PendingCollision.new();collision.name="CollisionInstanceResidency";map.add_child(collision)
		collision.selection_pending=true
		check(not queue._publish_items([item],source) and collision.preflights==0 and empty_publication(map),label+" pending collision selection cannot start index preparation or commit")
		packet=queue._jobs[item.path].collision_staged[item.record.uuid]
		check(not packet.has("index_preparation") and queue._admission.reserved_bytes==1048576,label+" selection wait retains the original source packet and reservation")
		collision.selection_pending=false
		queue._publish_items([item],source)
		while not packet.index_preparation.advance(100):pass
		var owned_cursor:RefCounted=packet.index_preparation
		var before_preflights:int=collision.preflights
		var before_instances:int=queue.profile.index_preparation_instances
		for attempt:int in 3:
			check(not queue._publish_items([item],source) and is_same(packet.index_preparation,owned_cursor) and ready_cursor(owned_cursor,source) and empty_publication(map) and collision.committed==0 and emissions.count==0,label+" collision promotion wait retains the same ready cursor without a partial namespace")
		check(collision.preflights==before_preflights+3 and queue.profile.index_preparation_instances==before_instances and queue._admission.reserved_bytes==1048576,label+" commit gate is retried without rebuilding the index or releasing its lease")
		collision.pending=false
		check(queue._publish_items([item],source) and collision.committed==1 and not owned_cursor.owns_projection and original_identities(map,source) and emissions.count==1 and emissions.size==600,label+" resolved collision promotion transfers all original identities once")
		check(not queue._publish_items([item],source) and collision.committed==1 and emissions.count==1,label+" repeated publication cannot commit collision or emit twice")
		map.free();fixture_={};source=[];item={};packet={};owned_cursor=null
	Deferred.private_publication_packet_enabled=original_private_mode
	OS.remove_logger(logger)
	check(logger.errors.is_empty(),"zero engine or script errors across both publication modes")
	for message:String in logger.errors:print("CAPTURED_ERROR ",message)
	print("DEFERRED_INDEX_PREPARATION failures=",failures);quit(1 if failures else 0)
