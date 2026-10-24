extends "res://tools/test_resumable_batch_collection.gd"
func run()->void:
	var host:=Node3D.new();root.add_child(host)
	var mesh:=Cpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD]);mesh.surfaces=[arrays];mesh.bounds=AABB(Vector3.ZERO,Vector3.ONE);mesh.materials=[StandardMaterial3D.new()]
	var nodes:Array=[]
	for i:int in 1000:nodes.append(add_source(host,mesh,"middle_%05d"%i))
	var batch:=CountingBatch.new();host.add_child(batch);batch.set_process(false)
	var began:=Time.get_ticks_usec();request(batch,nodes,true);collect(batch)
	for update:int in 16:
		for step:int in 64:batch._prepare_step(1)
		check(batch._preparation.phase=="prepare","new earlier names arrive during preparation")
		for i:int in 12:nodes.append(add_source(host,mesh,"early_%05d"%(update*12+i)))
		request(batch,nodes,true);collect(batch)
	drain(batch);var elapsed:=Time.get_ticks_usec()-began
	var oracle:=Batch.new();host.add_child(oracle);oracle.set_process(false);oracle.request_sync(nodes);drain(oracle)
	check(groups_of(batch)==groups_of(oracle),"interleaved insertions preserve every sorted bin, member and signature")
	check(batch.prepared==nodes.size(),"each surviving source is prepared once despite earlier-name insertions")
	print("INTERLEAVED_BATCH_PREPARATION ",JSON.stringify({"sources":nodes.size(),"prepared":batch.prepared,"collected":batch.collected,"us":elapsed,"failures":failures}))
	batch.clear(false);oracle.clear(false)
	request(batch,nodes,true)
	while batch._preparation.phase!="bin":batch._prepare_step(1)
	for i:int in 80:batch._prepare_step(1)
	nodes.append(add_source(host,mesh,"aaa_bin_insert"))
	var other:=Node3D.new();host.add_child(other)
	var replacement:=add_source(other,mesh,"middle_00002");replacement.position=Vector3(513,0,0);nodes.append(replacement)
	request(batch,nodes,true);drain(batch);oracle.request_sync(nodes);drain(oracle)
	check(groups_of(batch)==groups_of(oracle),"insertion and same-name replacement during bin packing retain exact cells and order")
	batch.clear(false);oracle.clear(false);host.free();quit(1 if failures else 0)
