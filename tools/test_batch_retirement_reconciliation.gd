extends "res://tools/test_incremental_batch_bins.gd"
## Fixed source departures after completed immutable residency, plus a fresh
## sorted oracle. Counts real prepare/pack visits; no frame-time thresholds.
var reports:Array=[]
func fixture(houses:int=32,parts:int=32)->Dictionary:
	var host:=Node3D.new();root.add_child(host)
	var mesh:=Cpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD]);mesh.surfaces=[arrays];mesh.bounds=AABB(Vector3.ZERO,Vector3.ONE);mesh.materials=[StandardMaterial3D.new()]
	var batch:=CountingBatch.new();host.add_child(batch);batch.set_process(false)
	var oracle:=Batch.new();host.add_child(oracle);oracle.set_process(false)
	var nodes:Array=[]
	for house:int in houses:
		for part:int in parts:nodes.append(building_source(host,mesh,"house_%02d_part_%02d"%[house,part],"house_%02d"%house))
	batch.request_residency_sync(nodes,[],true);drain(batch)
	return {"host":host,"mesh":mesh,"batch":batch,"oracle":oracle,"nodes":nodes}
func compare(f:Dictionary,label:String)->void:
	var started:=Time.get_ticks_usec()
	f.batch.request_residency_sync(f.nodes,[],true);drain(f.batch)
	f.last_reconcile_us=Time.get_ticks_usec()-started
	f.oracle.request_sync(f.nodes);drain(f.oracle)
	check(groups_of(f.batch)==groups_of(f.oracle),label+": exact fresh sorted membership")
	var safe:=true
	for key:String in f.batch.groups:
		var a:Dictionary=f.batch.groups[key];var b:Dictionary=f.oracle.groups[key]
		safe=safe and a.signature==b.signature and a.vertices==b.vertices and a.keys==b.keys and a.origin==b.origin
	check(safe,label+": transforms, vertices, material keys and origins match")
	if "--gpu" in OS.get_cmdline_user_args():
		f.batch.flush();f.oracle.flush()
		var equal:bool=f.batch.groups.size()==f.oracle.groups.size()
		for key:String in f.batch.groups:
			var a:Mesh=f.batch.groups[key].data.mesh;var b:Mesh=f.oracle.groups[key].data.mesh
			equal=equal and a.get_surface_count()==b.get_surface_count()
			for slot:int in a.get_surface_count():
				equal=equal and a.surface_get_arrays(slot)==b.surface_get_arrays(slot) and a.surface_get_material(slot)==b.surface_get_material(slot)
		check(equal,label+": actual GPU mesh channels and materials equal full rebuild")
func retire(f:Dictionary,node:Node)->void:
	f.batch.retire_sources([node]);f.nodes.erase(node);node.free()
func finish(f:Dictionary,label:String,began:int,prepared:int,packed:int)->void:
	reports.append({"case":label,"with_oracle_us":Time.get_ticks_usec()-began,"reconcile_us":f.last_reconcile_us,"prepare_delta":f.batch.prepared_source_visits-prepared,"pack_delta":f.batch.packed_source_visits-packed,"remaining":f.nodes.size()})
	f.batch.clear(false);f.oracle.clear(false);f.host.free()
func stress_retirement()->void:
	var expected:Dictionary={}
	for fast:bool in [false,true,true,false]:
		Batch.incremental_source_retirement_enabled=fast
		var f:=fixture(64,64);var late:Array=[]
		for i:int in 3:
			var node:=building_source(f.host,f.mesh,"stress_lod_%d"%i,"lods");node.transparency=.5
			late.append(node);f.nodes.append(node)
		f.batch.request_residency_sync(f.nodes,[],true);drain(f.batch)
		var prepared:int=f.batch.prepared_source_visits;var packed:int=f.batch.packed_source_visits
		var began:=Time.get_ticks_usec()
		for node:Node in late:retire(f,node)
		f.batch.request_residency_sync(f.nodes,[],true);drain(f.batch)
		var elapsed:=Time.get_ticks_usec()-began;var groups:=groups_of(f.batch)
		if expected.is_empty():expected=groups
		check(groups==expected,"4096-source stress preserves exact memberships across ABBA")
		check(f.batch.prepared_source_visits-prepared==(0 if fast else 4096) and f.batch.packed_source_visits-packed==(0 if fast else 4096),"4096-source stress executes the requested legacy/new work contract")
		reports.append({"case":"stress","incremental":fast,"sources":4096,"retire_reconcile_us":elapsed,"prepare_delta":f.batch.prepared_source_visits-prepared,"pack_delta":f.batch.packed_source_visits-packed})
		f.batch.clear(false);f.oracle.clear(false);f.host.free()
	Batch.incremental_source_retirement_enabled=true
func prune_arrival()->void:
	var f:=fixture();var prepared:int=f.batch.prepared_source_visits;var packed:int=f.batch.packed_source_visits;var began:=Time.get_ticks_usec()
	retire(f,f.nodes[-1]);f.batch.request_residency_sync(f.nodes,[],true)
	var guard:=0
	while not f.batch._preparation.is_empty() and f.batch._preparation.phase!="prune" and guard<100000:
		f.batch._prepare_step(1);guard+=1
	check(f.batch._preparation.get("phase","")=="prune","arrive at a bounded retirement prune cursor")
	f.nodes.append(building_source(f.host,f.mesh,"late_after_retirement","late"))
	f.batch.request_residency_sync(f.nodes,[],true)
	compare(f,"new arrival during retirement reconciliation")
	check(f.batch.prepared_source_visits-prepared==1,"arrival during prune never discards the retained prepared owners")
	finish(f,"arrival_during_prune",began,prepared,packed)
func unrelated_departure()->void:
	# The real departure trace also retires sources that never entered this
	# batcher's completed demand. They must not revoke unrelated owners.
	for fast:bool in [false,true]:
		Batch.incremental_source_retirement_enabled=fast
		var f:=fixture();var prepared:int=f.batch.prepared_source_visits;var packed:int=f.batch.packed_source_visits;var began:=Time.get_ticks_usec()
		var outside:=building_source(f.host,f.mesh,"outside_current_batch","outside")
		retire(f,outside);compare(f,"unregistered source departs, incremental="+str(fast))
		var expected:=0 if fast else 1024
		check(f.batch.prepared_source_visits-prepared==expected and f.batch.packed_source_visits-packed==expected,"unrelated departure executes old full rebuild or preserves unchanged completion")
		finish(f,"unregistered_departure_"+str(fast),began,prepared,packed)
	Batch.incremental_source_retirement_enabled=true
func run()->void:
	if "--prune-only" in OS.get_cmdline_user_args():
		prune_arrival();print("PRUNE_ARRIVAL ",JSON.stringify({"cases":reports,"failures":failures}));quit(1 if failures else 0);return
	var f:=fixture()
	var late:Array=[]
	for i:int in 3:
		var node:=building_source(f.host,f.mesh,"late_lod_%d"%i,"late_lods");node.transparency=.5
		late.append(node);f.nodes.append(node)
	compare(f,"three ineligible late roots")
	var prepared:int=f.batch.prepared_source_visits;var packed:int=f.batch.packed_source_visits;var began:=Time.get_ticks_usec()
	for node:Node in late:retire(f,node)
	compare(f,"late roots depart")
	check(f.batch.prepared_source_visits==prepared,"retiring ineligible roots never prepares unchanged sources again")
	check(f.batch.packed_source_visits==packed,"retiring ineligible roots never repacks unrelated bins")
	finish(f,"late_lod_departure",began,prepared,packed)
	f=fixture();prepared=f.batch.prepared_source_visits;packed=f.batch.packed_source_visits;began=Time.get_ticks_usec()
	var gone:Array=[f.nodes[0],f.nodes[517],f.nodes[-1]]
	for node:Node in gone:retire(f,node)
	var incoming:=building_source(f.host,f.mesh,"house_16_part_early","house_16");f.nodes.append(incoming)
	compare(f,"head middle tail departures and earlier same-bin arrival")
	check(f.batch.prepared_source_visits-prepared==1,"only the new source needs preparation")
	check(f.batch.packed_source_visits-packed==94,"only three changed building buckets repack with exact member limits")
	finish(f,"mixed_departure",began,prepared,packed)
	f=fixture();prepared=f.batch.prepared_source_visits;packed=f.batch.packed_source_visits;began=Time.get_ticks_usec()
	retire(f,f.nodes[-1])
	var old:Node=f.nodes[10];var name_:=str(old.name)
	f.batch.retire_sources([old]);f.nodes.erase(old);old.free()
	var replacement:=building_source(f.host,f.mesh,name_,"house_00");replacement.position.x=20;f.nodes.append(replacement)
	compare(f,"same UUID returns with a different node and transform")
	check(f.batch.prepared_source_visits-prepared==1,"returned identity is prepared exactly once without scanning other sources")
	finish(f,"replacement",began,prepared,packed)
	f=fixture();prepared=f.batch.prepared_source_visits;packed=f.batch.packed_source_visits;began=Time.get_ticks_usec()
	f.batch.retire_sources([]);compare(f,"empty logical retirement")
	check(f.batch.prepared_source_visits==prepared and f.batch.packed_source_visits==packed,"empty retirement changes no completed work")
	f.batch.request_residency_sync(f.nodes+ [building_source(f.host,f.mesh,"pending","pending")],[],true)
	var state:Dictionary=f.batch._preparation
	var phase:String=state.phase
	f.batch.retire_sources([])
	check(is_same(state,f.batch._preparation) and f.batch._preparation.get("phase","")==phase,"empty retirement does not cancel an unfinished cursor")
	finish(f,"empty_retirement",began,prepared,packed)
	f=fixture();prepared=f.batch.prepared_source_visits;packed=f.batch.packed_source_visits;began=Time.get_ticks_usec()
	retire(f,f.nodes[-1])
	f.nodes[1].position.x+=1;f.batch.invalidate_source(f.nodes[1])
	compare(f,"explicit edit revokes retained retirement snapshot")
	check(f.batch.retirement_prepares_avoided==0,"editor invalidation cannot reuse the immutable retirement promise")
	finish(f,"editor_invalidation",began,prepared,packed)
	f=fixture();prepared=f.batch.prepared_source_visits;packed=f.batch.packed_source_visits;began=Time.get_ticks_usec()
	f.nodes.append(building_source(f.host,f.mesh,"partial_add","partial"))
	f.batch.request_residency_sync(f.nodes,[],true);f.batch._prepare_step(1)
	retire(f,f.nodes[0]);compare(f,"departure during unfinished preparation")
	finish(f,"partial_fallback",began,prepared,packed)
	unrelated_departure()
	prune_arrival()
	if "--gpu" not in OS.get_cmdline_user_args():stress_retirement()
	print("BATCH_RETIREMENT_RECONCILIATION ",JSON.stringify({"cases":reports,"failures":failures}));quit(1 if failures else 0)
