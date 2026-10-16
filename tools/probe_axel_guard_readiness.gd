extends "res://tools/probe_axel_guard_approach.gd"
## Passive blockers only. No extra demands, scheduler flags or readiness bypass.
const StreamProbe=preload("res://scripts/world3d/world_stream.gd")
const DeferredProbe=preload("res://scripts/world3d/deferred_asset_loader.gd")

func simple_fields(value:Dictionary)->Dictionary:
	var result:Dictionary={}
	for key in value:
		var item:Variant=value[key]
		if item==null or item is String or item is bool or item is int or item is float:result[str(key)]=item
	return result

func readiness_snapshot()->Dictionary:
	var map:Node=world._map_root;var origin:Vector3=world._player.global_position
	var clip:=AABB(Vector3(origin.x-2,-100000,origin.z-2),Vector3(4,200000,4))
	var queue:Node=map.get_node_or_null("DeferredAssets")
	var result:={"collision_first_world":world._collision_first(map),"collision_first_loader":DeferredProbe.collision_first_enabled,"clip":[xyz(clip.position),xyz(clip.size)],"stream_chunk":str(map.get_meta("stream_chunk","unsettled")),"stream_target":str(map.get_meta("stream_target","unplanned")),"player_chunk":str(StreamProbe.chunk_key(origin)),"geometry_wait_locked":world._geometry_wait_locked,"status":str(world._status.text),"stream_cursor":map.get_meta("stream_cursor",0),"stream_job_count":map.get_meta("stream_jobs",[]).size(),"navigation":world._navigation.capability_status(),"pending":[],"jobs":[],"missing_bodies":[]}
	if queue!=null:
		result.queue_profile=simple_fields(queue.profile);result.admission=queue._admission.snapshot();result.demand_scope=queue._demand_scope.keys()
		for item:Dictionary in queue._in_clip(clip):
			var row:=simple_fields(item);var record:Dictionary=item.record
			row.uuid=record.uuid;row.asset_path=record.get("asset_path","");row.reference=simple_fields(item.get("reference_entry",{}));row.bounds=[xyz(item.bounds.position),xyz(item.bounds.size)]
			row.rank=queue._demanded_rank.get(record.uuid,-1);row.priority=queue._demanded_priority.get(record.uuid,999)
			result.pending.append(row)
		for path:String in queue._jobs:
			var job:Dictionary=queue._jobs[path];var row:=simple_fields(job);row.path=path;row.keys=job.keys();row.priority=queue._path_priority(path);row.rank=queue._path_rank(path)
			row.admission=queue._admission._entries.get(path,{})
			if job.get("worker") is Thread:row.worker_complete=not job.worker.is_alive()
			result.jobs.append(row)
	var seen:Dictionary={};var bodies:Dictionary=map.get_meta("stream_bodies",{});var batched:Dictionary=map.get_meta("fortification_collision_sources",{})
	var low:=StreamProbe.chunk_key(clip.position);var high:=StreamProbe.chunk_key(clip.end)
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			for spec:Dictionary in map.get_meta("stream_collision_index",{}).get(Vector2i(x,z),[]):
				if seen.has(spec.uuid):continue
				seen[spec.uuid]=true
				var extra:Dictionary=spec.get("extras",{})
				if spec.get("native_visual",false) or extra.get("hostile",false) or extra.get("ally",false) or extra.get("rmmo_collision","")=="none":continue
				var bounds:AABB=spec.transform*spec.mesh.get_aabb()
				if not DeferredProbe._intersects(clip,bounds):continue
				if not batched.has(spec.uuid) and not is_instance_valid(bodies.get(spec.uuid)):result.missing_bodies.append({"uuid":spec.uuid,"bounds":[xyz(bounds.position),xyz(bounds.size)],"record":simple_fields(spec.get("ground_batch_record",{}))})
	return result

func observe_motion(tick:int)->Dictionary:
	var result:=super.observe_motion(tick)
	result.readiness=readiness_snapshot()
	if not report.has("executed_source_sha256"):
		report.executed_source_sha256={}
		for path:String in ["res://tools/probe_axel_guard_readiness.gd","res://tools/probe_axel_guard_approach.gd","res://scripts/world3d/world_3d.gd","res://scripts/world3d/world_stream.gd","res://scripts/world3d/deferred_asset_loader.gd"]:report.executed_source_sha256[path]=FileAccess.get_sha256(path)
	return result
