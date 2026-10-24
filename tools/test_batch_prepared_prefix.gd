extends "res://tools/test_resumable_batch_collection.gd"
func run()->void:
	var host:=Node3D.new();root.add_child(host)
	var mesh:=Cpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD]);mesh.surfaces=[arrays];mesh.bounds=AABB(Vector3.ZERO,Vector3.ONE);mesh.materials=[StandardMaterial3D.new()]
	var nodes:Array=[]
	for i:int in 1144:nodes.append(add_source(host,mesh,"row_%05d"%i))
	var expected:Dictionary={};var trials:Array=[]
	for resume:bool in [false,true,true,false]:
		var batch:=CountingBatch.new();host.add_child(batch);batch.set_process(false)
		var began:=Time.get_ticks_usec();request(batch,nodes.slice(0,1000),resume);collect(batch)
		for update:int in 12:
			for step:int in 40:batch._prepare_step(1)
			check(batch._preparation.phase=="prepare","addition arrives during incomplete grouping")
			request(batch,nodes.slice(0,1000+(update+1)*12),resume);collect(batch)
		drain(batch);var elapsed:=Time.get_ticks_usec()-began
		var groups:=groups_of(batch)
		if expected.is_empty():expected=groups
		check(groups==expected,"ordered additions preserve exact bins and member order")
		trials.append({"resume":resume,"prepared":batch.prepared,"collected":batch.collected,"us":elapsed})
		if resume:check(batch.prepared==1144,"ordered append never repeats already prepared sources")
		batch.clear(false);batch.free()
	var batch:=CountingBatch.new();host.add_child(batch);batch.set_process(false)
	request(batch,nodes.slice(0,1000),true);collect(batch)
	for i:int in 80:batch._prepare_step(1)
	var other:=Node3D.new();host.add_child(other)
	var replacement:=add_source(other,mesh,"row_00001");replacement.position=Vector3(1,0,0)
	var appended:=nodes.slice(0,1000);appended.append(replacement)
	request(batch,appended,true);batch._prepare_step(1)
	appended.append(nodes[1000]);request(batch,appended,true);drain(batch)
	var oracle:=Batch.new();host.add_child(oracle);oracle.set_process(false);oracle.request_sync(appended);drain(oracle)
	check(groups_of(batch)==groups_of(oracle),"same-name replacement and a second append during collection restart stale prepared bins")
	check(batch.prepared>1001,"replacing a prepared node invalidates the prefix")
	batch.clear(false);oracle.clear(false);batch.free();oracle.free()
	host.free();print("BATCH_PREPARED_PREFIX ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)
