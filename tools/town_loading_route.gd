extends RefCounted
## Fixed user-reported district, driven through the player's normal click route.
## Never assigns a transform or suppresses physics to make a waypoint pass.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const POINTS=[Vector2(292.9,151.4),Vector2(262.7,125.8),Vector2(292.9,151.4),Vector2(321.2,160.3)]

func run(world:Node,points:Array=POINTS,expected_start:Vector2=Vector2(321.2,160.3),leg_timeout_seconds:float=90.,diagnostic_motion:bool=false)->Dictionary:
	var result:={"ok":true,"legs":[],"reason":"","mode":"normal_click_navigation","note":"A short district revisit does not by itself prove far-region eviction."}
	var tree:SceneTree=world.get_tree();var player:Node=world._player
	var original:Vector3=player.global_position
	if Vector2(original.x,original.z).distance_to(expected_start)>1.:
		return {"ok":false,"reason":"route_requires_problem_spawn"}
	var deferred:Node=world._map_root.get_node_or_null("DeferredAssets")
	var had_profile:bool=player.has_meta("profile_frame");var old_profile:Variant=player.get_meta("profile_frame") if had_profile else null
	if diagnostic_motion:player.set_meta("profile_frame",true)
	for xz:Vector2 in points:
		var row:Dictionary={"target":[xz.x,xz.y],"frames_ms":[],"locked_ms":0.,"navigation_wait_ms":0.,"blocked":{},"reached":false}
		var start:=Time.get_ticks_usec();var previous:=start;var last_request:=-1000000;var destination:Variant=null
		while Time.get_ticks_usec()-start<int(leg_timeout_seconds*1000000):
			await tree.process_frame
			var now:=Time.get_ticks_usec();var ms:float=(now-previous)/1000.;previous=now
			row.frames_ms.append(ms)
			if player.input_locked or player.geometry_blocked:row.locked_ms+=ms
			if not world._navigation.ready_for_queries:row.navigation_wait_ms+=ms
			var feet:Vector3=player.global_position-Vector3.UP*.9
			if destination is Vector3 and feet.distance_to(destination)<.7:
				var support_ray:=PhysicsRayQueryParameters3D.create(feet+Vector3.UP*.1,feet-Vector3.UP*.4,player.collision_mask,[player.get_rid()])
				var support:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(support_ray)
				if not support.is_empty() and support.collider is StaticBody3D and support.normal.y>=.766:
					row.reached=true;break
			if now-last_request<500000:continue
			last_request=now
			# Only actual currently resident static support can choose a floor.
			# A normal navigation request also asks the game's existing provider
			# to prepare nearby path geometry; no benchmark-wide preload is used.
			# These points follow one outdoor street/bridge level. A nearby-height
			# ray cannot mistake a house roof high above the street for its floor.
			var ray:=PhysicsRayQueryParameters3D.create(Vector3(xz.x,feet.y+2.,xz.y),Vector3(xz.x,feet.y-6.,xz.y),player.collision_mask,[player.get_rid()])
			var hit:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty() or not hit.collider is StaticBody3D or hit.normal.y<.766:
				row.blocked.support=int(row.blocked.get("support",0))+1
				continue
			destination=hit.position
			var pending_same:bool=player._pending_click is Vector3 and player._pending_click.distance_to(destination)<.05 and player.path_status.get("reason","")=="pending"
			if player.click_target==null and not pending_same:
				var requested:Dictionary=player.set_click_target(destination,str(hit.collider.get_meta("surface_id","")))
				if not requested.get("ok",false):
					var reason:=str(requested.get("reason","navigation_pending"));row.blocked[reason]=int(row.blocked.get(reason,0))+1
		row.elapsed_ms=(Time.get_ticks_usec()-start)/1000.;row.destination=destination
		row.position=[player.global_position.x,player.global_position.y,player.global_position.z]
		var frames:Array=row.frames_ms;frames.sort();row.erase("frames_ms")
		row.frame_count=frames.size();row.frames=summary(frames)
		row.resident_specs=world._map_root.get_meta("stream_library",[]).size()
		row.collision_bodies=world._map_root.get_meta("stream_bodies",{}).size()
		row.deferred=deferred.profile.duplicate(true) if deferred!=null else {}
		row.navigation=world._navigation.capability_status()
		row.path_status=player.path_status.duplicate(true)
		row.pending_click=player._pending_click
		row.geometry_blocked=player.geometry_blocked
		row.motion={"velocity":player.velocity,"last_motion":player.get_last_motion(),"click_target":player.click_target,"route":player._route.duplicate(),"contacts":[]}
		if diagnostic_motion:row.motion.profile=player.get_meta("motion_timing",{}).duplicate(true)
		for contact_index in player.get_slide_collision_count():
			var contact:KinematicCollision3D=player.get_slide_collision(contact_index)
			var body:Object=contact.get_collider()
			var hit:Dictionary={"normal":contact.get_normal(),"position":contact.get_position(),"shape":str(contact.get_collider_shape()),"collider":str(body)}
			if body is CollisionObject3D:
				hit.uuid=preload("res://scripts/world3d/fortification_collision_batcher.gd").hit_uuid({"collider":body,"shape":contact.get_collider_shape()})
				var owner:Object=contact.get_collider_shape()
				if owner is CollisionShape3D:hit.shape_type=owner.shape.get_class();hit.shape_transform=owner.global_transform
			row.motion.contacts.append(hit)
		row.navigation_clips={"resident":world._navigation._local_clip,"initial":world._navigation._clip}
		row.frame_budget=preload("res://scripts/world3d/frame_work_budget.gd").report()
		if not row.reached and deferred!=null:
			row.deferred_diagnostic=deferred_snapshot(deferred,world._navigation)
		result.legs.append(row)
		if not row.reached:result.ok=false;result.reason="route_waypoint_timeout";break
	player.click_target=null;player._route.clear();player._pending_click=null
	if diagnostic_motion:
		if had_profile:player.set_meta("profile_frame",old_profile)
		else:player.remove_meta("profile_frame")
	result.final_position=[player.global_position.x,player.global_position.y,player.global_position.z]
	return result

static func deferred_snapshot(deferred:Node,navigation:Node)->Dictionary:
	var result:Dictionary={"jobs":[],"pending_clip":[],"demands":deferred._demands.duplicate(true),"prepared_paths":deferred._prepared_paths.size()}
	result.navigation_progress={"processing":navigation.is_processing(),"requested":navigation._nearby_request,"publish_wait":navigation._nearby_publish_wait}
	if navigation._nearby!=null:
		result.navigation_progress.worker={"clip":navigation._nearby.clip,"cursor":navigation._nearby.get("cursor"),"baking":navigation._nearby.baking,"complete":navigation._nearby.complete}
	for path:String in deferred._jobs:
		var job:Dictionary=deferred._jobs[path]
		var worker:Variant=job.get("worker")
		result.jobs.append({"path":path,"priority":deferred._path_priority(path),"cancelled":job.token.is_cancelled(),"worker_alive":worker!=null and worker.is_alive(),"prepared":deferred._prepared_paths.has(path),"stage":job.get("stage",""),"staged":job.get("staged",{}).size(),"publication_count":job.get("publication_ids",[]).size(),"publication_cursor":deferred._publication_queues.get(path,{}).get("cursor",0),"estimate_bytes":job.get("estimate",{}).get("estimated_bytes",0)})
	var clip:Variant=navigation.capability_status().get("foreground_clip")
	if clip is AABB:
		var pending:Array=deferred._in_clip(clip)
		result.pending_clip_count=pending.size()
		for item:Dictionary in pending.slice(0,80):
			result.pending_clip.append({"uuid":item.record.uuid,"path":item.path,"group":item.get("group_id",""),"priority":deferred._demanded_priority.get(item.record.uuid),"reference_prepared":item.get("reference_prepared",false),"instance_error":deferred.instance_errors.get(item.record.uuid,"")})
	return result

static func summary(sorted:Array)->Dictionary:
	if sorted.is_empty():return {}
	return {"p50":sorted[int((sorted.size()-1)*.50)],"p95":sorted[int((sorted.size()-1)*.95)],"p99":sorted[int((sorted.size()-1)*.99)],"max":sorted.back(),"over_50ms":sorted.filter(func(ms):return ms>50.).size(),"over_100ms":sorted.filter(func(ms):return ms>100.).size()}
