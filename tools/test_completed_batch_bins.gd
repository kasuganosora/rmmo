extends "res://tools/test_incremental_batch_bins.gd"
## Separate completed publication rounds must reuse unaffected bins, while live
## visibility, pose, exclusions, removal and editor invalidation still win.
func compare(batch:Node,oracle:Node,nodes:Array,label:String,excluded:Array=[])->void:
	request(batch,nodes,true,excluded);drain(batch)
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
		var began:=Time.get_ticks_usec();request(batch,nodes,true);drain(batch);elapsed+=Time.get_ticks_usec()-began
		oracle.request_sync(nodes);drain(oracle)
		check(groups_of(batch)==groups_of(oracle),"completed round %d matches rebuild"%house)
	var packed:int=batch.packed_source_visits
	var prepared:int=batch.prepared_source_visits
	var raw_only:=true
	for group:Dictionary in batch._residency_bins.get("desired",{}).values():raw_only=raw_only and not group.has("generation") and not group.has("exit_callback") and not group.has("data")
	check(raw_only,"raw bin cache never retains live group callbacks or renderer data")
	if "--expect-full" not in OS.get_cmdline_user_args():check(packed==nodes.size(),"completed unrelated bins are packed once per source")
	# Mutation and removal must be observed even when the root prefix survives.
	nodes[0].hide();compare(batch,oracle,nodes,"hidden singleton/member leaves cached bin")
	nodes[0].show();compare(batch,oracle,nodes,"visible source returns to cached bin")
	nodes[1].position.x+=300;compare(batch,oracle,nodes,"changed pose changes spatial bin")
	compare(batch,oracle,nodes,"selection excludes exactly its source",[str(nodes[2].name)])
	compare(batch,oracle,nodes,"selection release restores source")
	nodes[3].free();nodes.remove_at(3);compare(batch,oracle,nodes,"freed source and root removal retire old membership")
	nodes[4].transparency=.5;compare(batch,oracle,nodes,"dynamic ineligibility removes previous descriptor")
	nodes[4].transparency=0;compare(batch,oracle,nodes,"eligible source restores descriptor")
	batch.invalidate_source(nodes[5]);compare(batch,oracle,nodes,"explicit invalidation recaptures source")
	batch.clear(false);oracle.clear(false)
	var fort:Array=[]
	for i:int in 12:fort.append(fort_source(host,mesh.materials[0],"zz_fort_%02d"%i,float(i+1)))
	compare(batch,oracle,fort,"initial fortification unique merge")
	fort.append(fort_source(host,mesh.materials[0],"aa_fort_early",30.0))
	compare(batch,oracle,fort,"completed singleton bins preserve unique merge order")
	compare(batch,oracle,fort,"repeated round does not mutate raw singleton bins")
	batch.clear(false);oracle.clear(false)
	var late:Array=nodes.slice(0,128)
	request(batch,late,true)
	while batch._preparation.phase!="unique":batch._prepare_step(1)
	late.append(nodes[128]);request(batch,late,true)
	late.append(nodes[129]);request(batch,late,true)
	drain(batch);oracle.request_sync(late);drain(oracle)
	check(groups_of(batch)==groups_of(oracle),"append during finalization keeps latest request and completes exact bins")
	check(batch._next_residency.is_empty(),"finalization consumes queued residency request")
	batch.clear(false);oracle.clear(false);host.free()
	print("COMPLETED_BATCH_BINS ",JSON.stringify({"sources":2560,"packed":packed,"prepared":prepared,"us":elapsed,"failures":failures}));quit(1 if failures else 0)
