extends "res://tools/test_navigation_append_preparation.gd"
const Prep=preload("res://scripts/world3d/stream_index_preparation.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
func values(mesh:Mesh)->Array:
	var result:Array=[]
	for i:int in 2151:
		var value:=row("guild__part%d"%i,mesh,{"building":{"id":"guild"},"fixture":{"id":"fixture%d"%i,"kind":"door" if i%7==0 else "window","pivot":[0,0,0],"angle":90,"open":0.}})
		value.chunk_min=Vector2i.ZERO;value.chunk_max=Vector2i.ONE;value.closed_transform=value.transform;value.position=value.transform.origin
		result.append(value)
	return result
func run()->void:
	var mesh:=CountedMesh.new();var source:=values(mesh)
	var control:=fixture(Nav);var improved:=fixture(Nav)
	var prep:=Prep.new();prep.begin_runtime_owned(source)
	var slices:=0;var prep_began:=Time.get_ticks_usec()
	while not prep.advance(500):
		if slices==0:check(improved._spec_ids.is_empty(),"preparation yields without publishing navigation ownership")
		slices+=1
	var prep_us:=Time.get_ticks_usec()-prep_began
	check(slices>1 and prep.valid_runtime_owned(source) and prep.validation_snapshot.is_empty(),"large exclusively owned input prepares in slices without redundant snapshots")
	var initial:Array=[row("existing",mesh)];control.append_specs(initial);improved.append_specs(initial)
	check(control.append_specs(source).ok,"ordinary append supplies the exact reference result")
	var packet:RefCounted=prep.publication_packet;var index:=Index.build([])
	Trace.methods_enabled=true;Trace.method_labels={"method.spec_snapshot_validation.slice":true};Trace.start()
	var began:=Time.get_ticks_usec();var registered:Dictionary=Index.append(index,source,prep);var index_us:=Time.get_ticks_usec()-began
	var trace:=Trace.stop();Trace.methods_enabled=false;Trace.method_labels.clear()
	var scans:=0
	for stat:Dictionary in trace.stats:
		if stat.label=="method.spec_snapshot_validation.slice":scans+=stat.count
	check(registered.ok and scans==0 and index.stream_append_state.namespace_sizes.guild==2151,"atomic runtime index transfer starts no snapshot workers and preserves counts")
	var reused:Dictionary=Index.append(Index.build([]),source,prep)
	check(not reused.ok and reused.error=="stale_private_index","consumed transfer cannot reenter public snapshot validation or publish twice")
	mesh.reads=0;began=Time.get_ticks_usec();var result:Dictionary=improved.append_specs(source,packet);var nav_us:=Time.get_ticks_usec()-began
	check(result.ok and snapshot(control)==snapshot(improved) and mesh.reads==0,"prepared navigation matches exact IDs/order/doors/bounds/users with zero commit-time mesh getters")
	var unchanged:=snapshot(improved)
	check(not improved.append_specs(source,packet).ok and snapshot(improved)==unchanged,"duplicate callback rejects before all navigation writes")
	check(not packet.ready(source.duplicate()),"another array cannot consume this private transfer")
	residency_handoff(source,packet)
	prep.dispose();check(packet.ready(source),"signal-local metadata survives index cursor disposal")
	print("PRIVATE_PUBLICATION_PACKET ",JSON.stringify({"specs":2151,"prepare_us":prep_us,"slices":slices+1,"index_commit_us":index_us,"navigation_commit_us":nav_us,"snapshot_worker_scans":scans}))
	control.free();improved.free()
	await fixture_restart()
	print("PRIVATE_PUBLICATION_PACKET failures=",failures);quit(1 if failures else 0)
func fixture_restart()->void:
	var map_root:=Node3D.new();root.add_child(map_root)
	var initial_index:=Index.build([])
	for key:String in initial_index:map_root.set_meta(key,initial_index[key])
	map_root.set_meta("stream_library",[]);map_root.set_meta("extras",{"rmmo_records":[]})
	var queue:=Deferred.new();map_root.add_child(queue);queue._map=map_root;queue.set_process(false)
	var source:=values(BoxMesh.new());var item:Dictionary={"record":{"uuid":"guild","kind":"asset","asset_path":"test"},"path":"test","model_verified":true}
	# The publication gate now reads live demand membership. Build the same
	# admitted state as the loader instead of accidentally testing an early exit.
	queue.pending=[item];queue._demanded=[item];queue._demanded_by_id={"guild":item};queue._demanded_rank={"guild":0};queue._demanded_by_path={"test":[item]}
	queue._jobs.test={"accepted":true,"token":preload("res://scripts/world3d/asset_worker_drainer.gd").CancelToken.new()}
	check(not queue._publish_items([item],source),"first large publication yields before commit")
	var staged:Dictionary=queue._jobs.test.collision_staged.guild
	var prep:RefCounted=staged.index_preparation
	while not prep.advance(500):pass
	queue.runtime_fixture_states.guild=1.
	check(not queue._publish_items([item],source) and map_root.get_meta("stream_library").is_empty(),"late fixture change restarts private metadata before any index publication")
	check(queue.profile.index_preparation_restarts==1,"fixture writer invalidates exactly the staged packet")
	var nav:=fixture(Nav);var callbacks:Array=[]
	queue.published.connect(func(rows:Array):callbacks.append(nav.append_specs(rows,queue.publication_metadata)))
	var count:=0
	while not queue._publish_items([item],source) and count<1000:count+=1
	check(count<1000 and callbacks.size()==1 and callbacks[0].ok and map_root.get_meta("stream_library").size()==2151,"fresh fixture pose commits once with the same prepared navigation metadata")
	check(source[0].extras.fixture.open==1. and queue.publication_metadata==null,"final pose is current and signal metadata releases immediately")
	queue._jobs.clear();nav.free();map_root.free()

func residency_handoff(source:Array,packet:RefCounted)->void:
	var times:Array=[];var snapshots:Array=[]
	# Supports/envelopes are live after index append and may include ground
	# published while the private cursor was preparing.
	var support:={"uuid":"ground__part","ground_batch_record":{"uuid":"ground"}}
	for part:Dictionary in source:part.render_supports=[support]
	for prepared:bool in [false,true]:
		var map_root:=Node3D.new();root.add_child(map_root)
		var queue:=Deferred.new();map_root.add_child(queue)
		var ordinary:=preload("res://scripts/world3d/asset_residency.gd").new();ordinary.name="AssetResidency";map_root.add_child(ordinary)
		var native:=preload("res://scripts/world3d/native_residency.gd").new();map_root.add_child(native)
		ordinary._map=map_root;ordinary._deferred=queue;ordinary._record_paths.guild="shared.glb";ordinary._record_pins.guild="";ordinary._catalog.guild={}
		var entry:={"compact_record":{"uuid":"guild"},"bounds":AABB(Vector3.ZERO,Vector3.ONE),"asset_path":"shared.glb"}
		native._map=map_root;native._queue=queue;native._model_entries.guild=entry
		queue.publication_metadata=packet if prepared else null
		var began:=Time.get_ticks_usec();ordinary.observe(source);native.observe(source);times.append({"prepared":prepared,"elapsed_us":Time.get_ticks_usec()-began})
		var state:={"source_ids":ordinary._spec_namespaces.duplicate(),"namespaces":ordinary._namespace_specs.duplicate(true),"models":ordinary._model_namespaces.duplicate(true),"native":native._resident.duplicate(true),"bounds":native._units["asset:guild"].bounds,"supports":native._units["asset:guild"].support_ids.duplicate()}
		snapshots.append(state)
		check(ordinary._resident.is_empty() and ordinary.model_in_use("shared.glb") and native._resident["asset:guild"].ids.size()==2151,"bulk callback retains one shared-model lease and all building IDs")
		check(native._units["asset:guild"].support_ids.has("ground"),"prepared observation reads newly bound live terrain support")
		ordinary.observe(source);native.observe(source)
		check(native._resident["asset:guild"].ids.size()==2151 and ordinary._namespace_specs.guild.size()==2151,"duplicate observation never doubles IDs or model usage")
		ordinary.forget_specs(packet.ids.keys())
		check(not ordinary.model_in_use("shared.glb") and ordinary._spec_namespaces.is_empty(),"bulk model ownership releases without a hidden resource owner")
		queue.publication_metadata=null;map_root.free()
	check(snapshots[0]==snapshots[1],"prepared residency exactly matches incremental IDs, bounds, support and shared-model ownership")
	print("PRIVATE_RESIDENCY_CALLBACKS ",JSON.stringify(times))
