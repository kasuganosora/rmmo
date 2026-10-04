extends SceneTree
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failed:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failed+=1
func sources(host:Node3D)->Array:
	var result:Array=[]
	var mesh:=BoxMesh.new()
	for i in 3:
		var node:=MeshInstance3D.new();node.name="part%d"%i;node.mesh=mesh;node.position=Vector3(2+i,1,2)
		node.set_meta("ground_batch_record",{"uuid":str(node.name),"kind":"box","size":[1,1,1],"building":{"id":"house","floor":0,"part":str(node.name),"role":"wall"}})
		host.add_child(node);result.append(node)
	return result
func run()->void:
	var host:=Node3D.new();root.add_child(host)
	var batch:=Batch.new();host.add_child(batch);batch.set_process(false)
	for removed in [0,1,2]:
		var nodes:=sources(host);batch.sync(nodes);batch.flush()
		check(batch.groups.size()==1,"build one combined group")
		var visual:Node=batch.groups.values()[0].visual
		nodes[removed].free()
		check(batch.groups.is_empty() and batch.pending.is_empty() and batch._member_groups.is_empty() and not is_instance_valid(visual),"deleting source %d clears group, visual and identity cache immediately"%removed)
		batch._process(0)
		for node in nodes:
			if is_instance_valid(node):check(not node.mesh is Cpu,"surviving source restored")
		batch.sync(nodes);batch.flush() # Caller may still hold the freed node.
		check(batch.groups.size()==1,"remaining sources can rebuild with stale input filtered")
		batch.clear()
		for node in nodes:
			if is_instance_valid(node):
				check(node.tree_exiting.get_connections().is_empty(),"clear disconnects lifetime callbacks")
				node.free()
	# Reproduce an already-existing stale cache (before watcher registration).
	var stale:=sources(host);batch.sync(stale);batch.flush()
	var group:Dictionary=batch.groups.values()[0]
	for node in stale:node.tree_exiting.disconnect(group.exit_callback)
	stale[0].free();batch._process(0)
	check(batch.groups.is_empty(),"freed first source checked before typed assignment")
	for node in stale:
		if is_instance_valid(node):node.free()
	# Source destruction during worker execution must not commit the old geometry,
	# even if replacement nodes use the same UUIDs and group key.
	batch._building_meshes.clear() # Force the worker path, rather than a warm shared mesh hit.
	var old:=sources(host);batch.sync(old);batch._build_next(true)
	check(batch._workers.size()==1,"asynchronous build started")
	for node in old:node.free()
	var replacement:=sources(host);batch.sync(replacement)
	batch._finish_worker(0)
	check(batch.groups.size()==1 and not batch.groups.values()[0].has("visual"),"stale worker cannot publish into replacement generation")
	batch.flush();check(batch.groups.values()[0].members[0]==replacement[0],"replacement generation builds normally")
	replacement[1].queue_free();await process_frame;await process_frame
	batch._process(0);check(batch.groups.is_empty(),"queued deletion invalidates before next process")
	host.free();print("GROUND_BATCH_LIFETIME ","PASS" if failed==0 else "FAIL");quit(0 if failed==0 else 1)
