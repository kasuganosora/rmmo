extends "res://tools/test_resumable_batch_collection.gd"
## Reproduce publication bursts into unrelated buildings after binning began.
## New earlier names may reorder their own bucket, never unrelated buckets.
func building_source(host:Node3D,mesh:Mesh,id:String,building:String)->Node:
	var node:=add_source(host,mesh,id)
	var record:Dictionary=node.get_meta("ground_batch_record");record.building.id=building
	return node
func run()->void:
	var host:=Node3D.new();root.add_child(host)
	var mesh:=Cpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD]);mesh.surfaces=[arrays];mesh.bounds=AABB(Vector3.ZERO,Vector3.ONE);mesh.materials=[StandardMaterial3D.new()]
	var nodes:Array=[]
	for house:int in 20:
		for part:int in 64:nodes.append(building_source(host,mesh,"middle_%02d_%02d"%[house,part],"house_%02d"%house))
	var batch:=CountingBatch.new();host.add_child(batch);batch.set_process(false)
	var started:=Time.get_ticks_usec();request(batch,nodes,true)
	for update:int in 20:
		while batch._preparation.phase!="bin":batch._prepare_step(1)
		var advance:=maxi(1,(batch._preparation.items.size()-int(batch._preparation.cursor))*3/4)
		for step:int in advance:batch._prepare_step(1)
		check(batch._preparation.phase=="bin","publication arrives while bin packing is incomplete")
		# Alternate lexically earlier/later names and add to distinct buildings.
		var prefix:="early" if update%2==0 else "late"
		for part:int in 64:nodes.append(building_source(host,mesh,"%s_%02d_%02d"%[prefix,update,part],"new_house_%02d"%update))
		request(batch,nodes,true)
	drain(batch);var elapsed:=Time.get_ticks_usec()-started
	var oracle:=Batch.new();host.add_child(oracle);oracle.set_process(false);oracle.request_sync(nodes);drain(oracle)
	check(groups_of(batch)==groups_of(oracle),"all spatial bins and member order match complete deterministic rebuild")
	check(batch.prepared==nodes.size(),"source preparation stays once per source")
	if not "--expect-full" in OS.get_cmdline_user_args():check(batch.packed_source_visits<nodes.size()*2,"unrelated completed bins are not repacked for every publication")
	print("INCREMENTAL_BATCH_BINS ",JSON.stringify({"sources":nodes.size(),"prepared":batch.prepared,"packed":batch.packed_source_visits,"us":elapsed,"failures":failures}))
	batch.clear(false);oracle.clear(false)
	var fort:Array=[]
	for i:int in 16:fort.append(fort_source(host,mesh.materials[0],"zz_fort_%02d"%i,float(i+1)))
	request(batch,fort,true)
	while batch._preparation.phase!="bin":batch._prepare_step(1)
	for i:int in 12:batch._prepare_step(1)
	fort.append(fort_source(host,mesh.materials[0],"aa_fort_first",30.0))
	request(batch,fort,true);drain(batch);oracle.request_sync(fort);drain(oracle)
	check(groups_of(batch)==groups_of(oracle),"earlier unique fortification keeps complete-rebuild merge order across different base keys")
	batch.clear(false);oracle.clear(false);host.free();quit(1 if failures else 0)

func fort_source(host:Node3D,material:Material,id:String,size_:float)->Node:
	var mesh:=Cpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT*size_,Vector3.FORWARD]);mesh.surfaces=[arrays];mesh.bounds=AABB(Vector3.ZERO,Vector3.ONE);mesh.materials=[material]
	var node:=add_source(host,mesh,id);var record:Dictionary=node.get_meta("ground_batch_record")
	record.erase("building");record.fortification={}
	return node
