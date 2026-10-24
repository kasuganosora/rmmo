extends "res://tools/test_incremental_batch_bins.gd"
func append_request(batch:Node,nodes:Array,excluded:Array=[])->void:
	if "--baseline" in OS.get_cmdline_user_args():batch.request_residency_sync(nodes,excluded)
	else:batch.request_residency_sync(nodes,excluded,true)
func compare_full(batch:Node,oracle:Node,nodes:Array,label:String,excluded:Array=[])->void:
	append_request(batch,nodes,excluded);drain(batch)
	oracle.request_sync(nodes,excluded);drain(oracle)
	check(groups_of(batch)==groups_of(oracle),label)
func run()->void:
	var host:=Node3D.new();root.add_child(host)
	var mesh:=Cpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD]);mesh.surfaces=[arrays];mesh.bounds=AABB(Vector3.ZERO,Vector3.ONE);mesh.materials=[StandardMaterial3D.new()]
	var batch:=CountingBatch.new();host.add_child(batch);batch.set_process(false)
	var oracle:=Batch.new();host.add_child(oracle);oracle.set_process(false)
	var nodes:Array=[];var elapsed:=0
	for house:int in 20:
		for part:int in 128:nodes.append(building_source(host,mesh,"row_%02d_%03d"%[house,part],"house_%02d"%house))
		var began:=Time.get_ticks_usec();append_request(batch,nodes);drain(batch);elapsed+=Time.get_ticks_usec()-began
		oracle.request_sync(nodes);drain(oracle)
		check(groups_of(batch)==groups_of(oracle),"complete append %d exact bins/order"%house)
	var prepared:=batch.prepared_source_visits;var collected:=batch.collected
	if "--baseline" not in OS.get_cmdline_user_args():check(prepared==nodes.size() and collected==nodes.size(),"completed immutable appends collect/prepare each source once")
	# Real mutation paths explicitly invalidate source state; removal and changed
	# exclusion/enable state invalidate the prefix without trusting old descriptors.
	nodes[0].position.x+=300;batch.invalidate_source(nodes[0]);compare_full(batch,oracle,nodes,"explicit pose invalidation")
	nodes[1].hide();batch.release_sources([nodes[1]]);compare_full(batch,oracle,nodes,"hidden source after editor release")
	nodes[1].show();batch.invalidate_source(nodes[1]);compare_full(batch,oracle,nodes,"shown source after invalidation")
	compare_full(batch,oracle,nodes,"exclusion change",[str(nodes[2].name)])
	compare_full(batch,oracle,nodes,"exclusion removal")
	nodes[3].free();nodes.remove_at(3);compare_full(batch,oracle,nodes,"freed source/removal")
	var earlier:=building_source(host,mesh,"aaa_late","house_00");nodes.append(earlier)
	compare_full(batch,oracle,nodes,"lexically earlier addition repacks only affected bins")
	batch.clear(false);oracle.clear(false)
	append_request(batch,nodes.slice(0,128))
	while batch._preparation.phase!="unique":batch._prepare_step(1)
	append_request(batch,nodes.slice(0,256));append_request(batch,nodes.slice(0,384));drain(batch)
	oracle.request_sync(nodes.slice(0,384));drain(oracle)
	check(groups_of(batch)==groups_of(oracle),"queued finalization preserves immutable append mode and latest source set")
	check(batch._next_residency.is_empty(),"queued finalization drains")
	batch.retire_sources(nodes.slice(0,128));check(batch._residency_bins.is_empty(),"retirement clears completed prefix owners")
	batch.clear(false);oracle.clear(false);host.free()
	print("COMPLETED_IMMUTABLE_APPEND ",JSON.stringify({"prepared":prepared,"collected":collected,"sources":2560,"us":elapsed,"failures":failures}));quit(1 if failures else 0)
