extends "res://tools/probe_axel_scene_visibility.gd"
## Passive half-second samples of production queues. Keep normal budgets,
## demanded sources, worker admission and readiness; no forced publications.
var next_sample_ms:=0
var region_samples:Array=[]
var profile_source_sha:Dictionary={}
func run()->void:
	for path:String in ["res://scripts/world3d/world_stream.gd","res://scripts/world3d/deferred_asset_loader.gd","res://scripts/world3d/frame_work_budget.gd","res://tools/profile_axel_region_loading.gd","res://tools/probe_axel_scene_visibility.gd","res://tools/review_axel_town_roads.gd"]:profile_source_sha[path]=FileAccess.get_sha256(path)
	await super.run()
func _process(_delta:float)->bool:
	if finished or not is_instance_valid(world) or not world.has_method("is_world_ready"):return false
	var map:Node=world.get("_map_root")
	var now:=Time.get_ticks_msec()
	if map==null or now<next_sample_ms:return false
	next_sample_ms=now+500
	var jobs:Array=map.get_meta("stream_jobs",[]);var cursor:int=map.get_meta("stream_cursor",0)
	var queue:Node=map.get_node_or_null("DeferredAssets")
	var row:={"at_ms":now-started_ms,"phase":report.get("phase",""),"stream_jobs":jobs.size(),"stream_cursor":cursor,"append_pending":map.get_meta("stream_append_pending",[]).size(),"stream_settled":map.has_meta("stream_chunk"),"meshes":map.get_meta("stream_meshes",{}).size(),"bodies":map.get_meta("stream_bodies",{}).size()}
	if cursor<jobs.size():
		var spec:Dictionary=jobs[cursor]
		row.head={"id":spec.get("uuid",""),"collision":spec.get("collision",""),"kind":spec.get("ground_batch_record",{}).get("kind","asset"),"prepared_shape":spec.has("shape"),"prepared_body":spec.has("prepared_body")}
	if queue!=null:
		row.pending=queue.pending.size();row.demanded=queue._demanded_by_id.size()
		row.actual_unpublished_demand=queue.pending.filter(func(item):return queue._demanded_by_id.has(item.record.uuid)).size()
		row.jobs=[]
		for path:String in queue._jobs:
			var job:Dictionary=queue._jobs[path];var worker:Thread=job.get("worker")
			row.jobs.append({"path":path,"stage":job.get("stage",""),"alive":worker!=null and worker.is_alive(),"ready_result":job.has("result"),"age_ms":(Time.get_ticks_usec()-int(job.get("dispatch_us",Time.get_ticks_usec())))/1000.,"native":job.get("native",false)})
		row.admission=queue._admission.snapshot();row.queue_profile=queue.profile.duplicate(true)
	var preparer:Node=map.get_node_or_null("StreamCollisionPreparer")
	if preparer!=null:
		row.collision_worker=preparer._thread!=null and preparer._thread.is_alive()
		row.terrain={"id":preparer._terrain._spec.get("uuid",""),"cursor":preparer._terrain._cursor,"faces":preparer._terrain._faces.size(),"worker":preparer._terrain._thread!=null and preparer._terrain._thread.is_alive()}
	region_samples.append(row)
	return false
func finish(code:int=-1)->void:
	if finished:return
	report.region_samples=region_samples;report.profile_sources=profile_source_sha
	report.profile_limits="Single fresh process with existing derived/OS caches. 500ms passive queue samples and existing cumulative counters; intervals overlap and are not summed as wall-clock CPU/GPU work. Reservation bytes are estimates, never RSS/VRAM."
	for path:String in profile_source_sha:check(FileAccess.get_sha256(path)==profile_source_sha[path],"profiling source unchanged "+path)
	super.finish(code)
