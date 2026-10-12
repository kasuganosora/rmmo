extends RefCounted
## Optional local query diagnosis, after the formal playable-frame monitor.
## Usage: await preload("res://tools/profile_collision_query_pair.gd").new().run(world)
## Keeps gameplay/physics/rendering/queues running. Each synchronous group uses
## one map and one real player footprint; publication may continue between groups.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Physical=preload("res://scripts/world3d/physical_traversal.gd")
const GROUPS:=16
var _running:=false
var _cancelled:=false

func cancel()->void:_cancelled=true

func run(world:Node)->Dictionary:
	if _running:return {"ok":false,"error":"probe_already_running"}
	if not is_instance_valid(world) or not world.is_inside_tree():return {"ok":false,"error":"world_missing"}
	var map_root:Node=world.get("_map_root")
	var player:CharacterBody3D=world.get("_player")
	if not _alive(world,map_root,player):return {"ok":false,"error":"loaded_world_required"}
	if not bool(world.get("_ready_for_play")) or bool(world.get("_transfer_pending")):
		return {"ok":false,"error":"playable_world_required"}
	var collider:=player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider==null or not collider.shape is CapsuleShape3D:return {"ok":false,"error":"player_capsule_required"}
	_running=true;_cancelled=false
	var saved_cache:=Stream.collision_candidate_cache_enabled
	var saved_profile:=Stream.collision_readiness_profile_enabled
	var began:=Time.get_ticks_usec()
	var tree:=world.get_tree()
	var report:Dictionary={"ok":false,"error":"","phase":"post_monitor_collision_query_pair","groups_requested":GROUPS,
		"groups":[],"checks":0,"failures":0,"assertions":[],"began_us":began,"map_instance_id":map_root.get_instance_id(),
		"order":["off","on","on","off"],"warmup_per_group":["off","on"],
		"saved_flags":{"candidate_cache":saved_cache,"readiness_profile":saved_profile},
		"clip_policy":"Recompute Physical.motion_bounds(player, Vector3.ZERO, 1/60, false) once per group; all six calls share that exact clip.",
		"note":"Local collision_readiness query timings only, outside the formal monitor. They do not demonstrate whole-frame improvement. Queues and gameplay remain active between groups; no body, render, readiness, navigation or input state is changed."}
	var off:Array=[];var on:Array=[];var ratios:Array=[]
	for group in GROUPS:
		await tree.process_frame
		if _cancelled:report.error="cancelled";break
		if not _alive(world,map_root,player):report.error="world_changed_or_removed";break
		if bool(world.get("_transfer_pending")):report.error="transfer_started";break
		var clip:=Physical.motion_bounds(player,Vector3.ZERO,1.0/60.0,false)
		if not clip.position.is_finite() or not clip.size.is_finite() or clip.size.x<=0 or clip.size.y<=0 or clip.size.z<=0:
			report.error="invalid_motion_bounds";break
		# No await, callback dispatch, queue pause or other scene mutation occurs
		# from warmup through the fourth measurement and flag restoration.
		var row:=_measure(map_root,clip)
		row.group=group;row.clip=_box(clip);row.player_position=_vec(player.global_position)
		if group==0:report.clip=row.clip
		report.groups.append(row)
		_check(report,row.receipts_equal,"group %d complete off/on/on/off receipts match"%group)
		_check(report,row.same_frame_and_revision,"group %d stayed in one frame and membership revision"%group)
		for index in [0,3]:off.append(row.elapsed_us[index])
		for index in [1,2]:on.append(row.elapsed_us[index])
		if row.ratio_on_over_off!=null:ratios.append(row.ratio_on_over_off)
		if not row.receipts_equal or not row.same_frame_and_revision:report.error="paired_query_mismatch";break
	# Also cover cancellation/map removal between groups. _measure already
	# restores these flags before yielding to normal gameplay on every frame.
	Stream.collision_candidate_cache_enabled=saved_cache
	Stream.collision_readiness_profile_enabled=saved_profile
	report.ended_us=Time.get_ticks_usec();report.wall_ms=(report.ended_us-began)/1000.0
	report.summary={"groups":report.groups.size(),"samples_per_mode":off.size(),"off_us":_distribution(off),"on_us":_distribution(on),"paired_ratio_on_over_off":_distribution(ratios)}
	var off_median:float=report.summary.off_us.p50
	report.summary.median_ratio_on_over_off=report.summary.on_us.p50/off_median if off_median>0 else null
	report.flags_restored=Stream.collision_candidate_cache_enabled==saved_cache and Stream.collision_readiness_profile_enabled==saved_profile
	_check(report,report.groups.size()==GROUPS,"all 16 paired groups completed")
	_check(report,report.flags_restored,"both static flags restored")
	if is_instance_valid(map_root):report.cache_stats=Stream.collision_candidate_cache_stats(map_root)
	report.ok=str(report.error).is_empty() and report.failures==0
	_running=false
	return report

func _measure(map_root:Node,clip:AABB)->Dictionary:
	var saved_cache:=Stream.collision_candidate_cache_enabled
	var saved_profile:=Stream.collision_readiness_profile_enabled
	Stream.collision_readiness_profile_enabled=false
	var process_before:=Engine.get_process_frames();var physics_before:=Engine.get_physics_frames()
	var revision_before:=int(map_root.get_meta("stream_collision_revision",-1))
	Stream.collision_candidate_cache_enabled=false
	var warm_off:=Stream.collision_readiness(map_root,clip)
	Stream.collision_candidate_cache_enabled=true
	var warm_on:=Stream.collision_readiness(map_root,clip)
	var elapsed:Array=[];var receipts:Array=[]
	for enabled:bool in [false,true,true,false]:
		Stream.collision_candidate_cache_enabled=enabled
		var began:=Time.get_ticks_usec()
		var receipt:=Stream.collision_readiness(map_root,clip)
		elapsed.append(Time.get_ticks_usec()-began)
		receipts.append(receipt)
	Stream.collision_candidate_cache_enabled=saved_cache
	Stream.collision_readiness_profile_enabled=saved_profile
	var equal:=warm_off==warm_on
	for receipt:Dictionary in receipts:equal=equal and receipt==warm_off
	var off_total:float=elapsed[0]+elapsed[3];var on_total:float=elapsed[1]+elapsed[2]
	return {"process_frame":process_before,"physics_frame":physics_before,"membership_revision":revision_before,
		"elapsed_us":elapsed,"receipts":receipts,"warmup_receipts_equal":warm_off==warm_on,"receipts_equal":equal,
		"off_mean_us":off_total*.5,"on_mean_us":on_total*.5,"ratio_on_over_off":on_total/off_total if off_total>0 else null,
		"same_frame_and_revision":process_before==Engine.get_process_frames() and physics_before==Engine.get_physics_frames() and revision_before==int(map_root.get_meta("stream_collision_revision",-1))}

static func _alive(world:Node,map_root:Node,player:CharacterBody3D)->bool:
	return is_instance_valid(world) and world.is_inside_tree() and is_instance_valid(map_root) and map_root.is_inside_tree() and is_instance_valid(player) and player.is_inside_tree() and world.get("_map_root")==map_root and world.get("_player")==player

static func _check(report:Dictionary,value:bool,label:String)->void:
	report.checks+=1
	if not value:report.failures+=1
	report.assertions.append({"ok":value,"label":label})

static func _distribution(values:Array)->Dictionary:
	if values.is_empty():return {"count":0,"min":0.0,"p50":0.0,"max":0.0,"mean":0.0}
	var sorted:=values.duplicate();sorted.sort()
	var total:=0.0
	for value:Variant in sorted:total+=float(value)
	var middle:=sorted.size()/2
	var median:=float(sorted[middle]) if sorted.size()%2==1 else (float(sorted[middle-1])+float(sorted[middle]))*.5
	return {"count":sorted.size(),"min":sorted[0],"p50":median,"max":sorted[-1],"mean":total/sorted.size()}

static func _vec(value:Vector3)->Array:return [value.x,value.y,value.z]
static func _box(value:AABB)->Dictionary:return {"position":_vec(value.position),"size":_vec(value.size)}
