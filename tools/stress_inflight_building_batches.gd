extends SceneTree
## Complete the same independent house groups while the first result has not
## been joined. Even finished-but-unjoined tasks must not cause duplicate work.
## --groups=12 --output=...; no map or asset package is required.
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
var count:=12
var output:=""
var failures:=0
var rows:Array=[]
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--groups="):count=clampi(arg.get_slice("=",1).to_int(),3,48)
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	Engine.max_fps=0
	for cancel:String in ["none","owner","follower","queued_follower","published_owner","different","reparent"]:
		var host:=Node3D.new();root.add_child(host)
		var batch:=Batch.new();host.add_child(batch);batch.set_process(false)
		var nodes:Array=[];var source:=BoxMesh.new()
		for group:int in count:
			for part:int in 3:
				var node:=MeshInstance3D.new();node.mesh=source;node.name="h%03d_p%d"%[group,part]
				if cancel=="different" and group==count-1 and part==0:
					node.mesh=BoxMesh.new();node.mesh.size=Vector3(2,1,1)
				node.position=Vector3(group*32+part,0,0)
				node.set_meta("ground_batch_record",{"kind":"box","size":[1,1,1],"building":{"id":"h%d"%group,"floor":0,"part":str(node.name),"role":"wall"}})
				host.add_child(node);nodes.append(node)
		batch.request_sync(nodes)
		while not batch._preparation.is_empty():batch._prepare_step(0)
		check(batch.pending.size()==count,"independent house groups retained")
		var keys:Array=batch.pending.duplicate()
		var began:=Time.get_ticks_usec()
		# Intentionally pressure dispatch beyond the normal three-worker limit.
		# Workload is fixed by group count, never multiplied by worker count.
		while not batch.pending.is_empty():batch._build_next(true)
		var started:int=batch._workers.size()
		check(started==(2 if cancel=="different" else 1),"only distinct geometry builds for %d house groups (%s)"%[count,cancel])
		if cancel in ["owner","follower"]:
			var key:String=keys[0 if cancel=="owner" else count-1]
			batch._invalidate_group(key,batch.groups[key].generation)
		if cancel=="reparent":
			host.remove_child(batch);host.add_child(batch);batch.set_process(false)
			while preload("res://scripts/world3d/cpu_worker_retirement.gd").pending(batch._retired_leases)>0:await process_frame
			check(batch.pending.size()==count,"reparent retains every uncommitted follower")
		while not batch._workers.is_empty():
			if batch._workers[0].thread.is_alive():await process_frame
			else:batch._finish_worker(0)
		if cancel in ["queued_follower","published_owner"]:
			check(not batch.pending.is_empty(),"followers remain visible to ordinary pending-work/readiness checks")
			var key:String=keys[count-1 if cancel=="queued_follower" else 0]
			batch._invalidate_group(key,batch.groups[key].generation)
		batch.flush()
		var elapsed:=Time.get_ticks_usec()-began
		var meshes:Dictionary={};var exact:=true
		for group:Dictionary in batch.groups.values():
			exact=exact and is_instance_valid(group.get("visual"))
			if not is_instance_valid(group.get("visual")):continue
			meshes[group.visual.mesh.get_instance_id()]=true
			var expected:=PackedVector3Array()
			for node:MeshInstance3D in group.members:expected.append_array(node.global_transform*node.mesh.get_faces())
			var actual:PackedVector3Array=group.visual.global_transform*group.visual.mesh.get_faces()
			exact=exact and expected.size()==actual.size()
			for i:int in mini(expected.size(),actual.size()):
				if expected[i].distance_to(actual[i])>.0002:exact=false;break
		check(exact,"every surviving group keeps exact world triangles (%s)"%cancel)
		check(meshes.size()==(2 if cancel=="different" else 1),"only distinct final GPU meshes remain (%s)"%cancel)
		check(batch.stats().pending_groups==0,"shared publications completely drain (%s)"%cancel)
		rows.append({"groups":count,"cancel":cancel,"worker_builds":started,"gpu_meshes":meshes.size(),"wall_us":elapsed,"surviving_groups":batch.groups.size()})
		host.free();await process_frame
	var report:={"rows":rows,"failures":failures}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("INFLIGHT_BUILDING_STRESS ",JSON.stringify(report));quit(1 if failures else 0)
