extends SceneTree
const Arrivals=preload("res://scripts/world3d/stream_batch_arrivals.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
class Receiver extends Node:
	var requests:Array=[]
	func request_residency_sync(nodes:Array,_excluded:Array,immutable:bool)->void:
		assert(immutable);requests.append(nodes.duplicate())
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func add_group(owner:String,count:int,meshes:Dictionary,groups:Dictionary,by_id:Dictionary)->WeakRef:
	var lifetime:=RefCounted.new();groups[owner]=[]
	for i:int in count:
		var id:="%s_%d"%[owner,i];var record:={"uuid":id,"kind":"box","building":{"id":owner}}
		var node:=MeshInstance3D.new();node.name=id;root.add_child(node);node.set_meta("ground_batch_record",record)
		var spec:={"uuid":id,"ground_batch_record":record,"render_building":owner,"index_only_lifetime":lifetime}
		meshes[id]=node;by_id[id]=spec;groups[owner].append(spec)
	return weakref(lifetime)
func release_nodes(meshes:Dictionary)->void:
	for node:Node in meshes.values():node.free()
	meshes.clear()
func run()->void:
	var meshes:Dictionary={};var groups:Dictionary={};var by_id:Dictionary={}
	add_group("a",4,meshes,groups,by_id);add_group("b",4,meshes,groups,by_id)
	var ledger:=Arrivals.new();var receiver:=Receiver.new()
	for id:String in ["a_0","a_1","a_2","b_0"]:ledger.arrived(by_id[id],meshes[id],groups)
	ledger.arrived(by_id.a_0,meshes.a_0,groups);ledger.dispatch(receiver,meshes,groups,by_id)
	check(receiver.requests.is_empty() and ledger.profile.arrivals==4,"partial closure and duplicate event cannot submit or add work")
	ledger.arrived(by_id.a_3,meshes.a_3,groups);ledger.dispatch(receiver,meshes,groups,by_id)
	check(receiver.requests.size()==1 and receiver.requests[0].size()==4 and ledger.unsubmitted.size()==1,"complete A submits while incomplete B stays outside preparation")
	var prefix:Array=receiver.requests[0]
	for id:String in ["b_1","b_2","b_3"]:ledger.arrived(by_id[id],meshes[id],groups)
	ledger.dispatch(receiver,meshes,groups,by_id)
	var full:=ledger.all_sources(meshes)
	check(full.size()==8 and full.slice(0,4)==prefix and receiver.requests[1]==full,"later full reconciliation preserves exact submitted prefix without duplicate roots")
	ledger.invalidate();check(ledger.needs_full and ledger.roots.is_empty() and ledger.pending.is_empty(),"removal invalidation releases all transient handles and requires reconciliation")
	release_nodes(meshes);groups.clear();by_id.clear();ledger.all_sources(meshes)
	add_group("a",4,meshes,groups,by_id)
	for id:String in meshes:ledger.arrived(by_id[id],meshes[id],groups)
	ledger.dispatch(receiver,meshes,groups,by_id)
	check(receiver.requests.size()==3 and receiver.requests[2].size()==4,"same UUIDs return as new nodes after an empty residency plan")
	release_nodes(meshes);groups.clear();by_id.clear()
	ledger=Arrivals.new();var index_owner:=add_group("stale",4,meshes,groups,by_id)
	for id:String in meshes:ledger.arrived(by_id[id],meshes[id],groups)
	var before:=receiver.requests.size();by_id.stale_0.ground_batch_record=by_id.stale_0.ground_batch_record.duplicate(true)
	ledger.dispatch(receiver,meshes,groups,by_id)
	check(receiver.requests.size()==before and ledger.all_sources(meshes).size()==4,"replaced authoring identity rejects stale early closure and retains full fallback")
	release_nodes(meshes);groups.clear();by_id.clear()
	check(index_owner.get_ref()==null,"ledger never retains index/spec resource owners even before its own invalidation")
	add_group("seed",2,meshes,groups,by_id);ledger=Arrivals.new(meshes)
	for id:String in meshes:ledger.arrived(by_id[id],meshes[id],groups)
	ledger.dispatch(receiver,meshes,groups,by_id)
	check(receiver.requests.size()==before and ledger.all_sources(meshes).size()==2,"pre-existing adopted sources require one ordinary reconciliation")
	ledger=Arrivals.new();ledger.invalidate(true)
	check(ledger.needs_full and ledger.all_sources(meshes).size()==2,"adoption after an initially empty ledger cannot omit unobserved live sources")
	var probe_map:=Node3D.new();root.add_child(probe_map)
	var probe_receiver:=Receiver.new();probe_receiver.name="GroundRenderBatches";probe_map.add_child(probe_receiver)
	var probe_ledger:=Arrivals.new()
	for id:String in meshes:probe_ledger.arrived(by_id[id],meshes[id],groups)
	probe_map.set_meta(Stream.BATCH_ARRIVALS,probe_ledger);probe_map.set_meta("stream_meshes",meshes)
	probe_map.set_meta("stream_building_groups",groups);probe_map.set_meta("stream_by_id",by_id)
	probe_map.set_meta("stream_children",probe_map.get_child_count(true))
	var saved_enabled:=Stream.closed_building_arrivals_enabled;var saved_native:=Controls.native_geometry_only
	Stream.closed_building_arrivals_enabled=true;Controls.native_geometry_only=true
	Stream._dispatch_batch_arrivals(probe_map,Stream.FRAME_BUDGET)
	Stream.closed_building_arrivals_enabled=saved_enabled;Controls.native_geometry_only=saved_native
	check(probe_receiver.requests.size()==1,"closed arrivals can dispatch without an optional incremental-adoption service")
	probe_map.free()
	ledger.invalidate();ledger.all_sources({});ledger=Arrivals.new()
	for id:String in meshes:ledger.arrived(by_id[id],meshes[id],groups)
	groups.seed=[];ledger.dispatch(receiver,meshes,groups,by_id)
	check(receiver.requests.size()==before,"removed indexed closure cannot publish queued nodes")
	release_nodes(meshes);groups.clear();by_id.clear();receiver.free()
	var report:={"checks":checks,"failures":failures}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			var file:=FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
	print("STREAM_BATCH_ARRIVALS ",JSON.stringify(report));quit(1 if failures else 0)
