extends RefCounted
## Bounded movement/known-route prediction. Tickets use the ordinary shared
## scheduler; they grant no collision, navigation or entry authority.
static var enabled:=true
static var predictive_enabled:=true # Old single-box control for measurements.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const DEMAND="building_approach"
const MAX_TICKETS=10
const MAX_ROUTE_POINTS=64
const STOP_HOLD_MSEC=1500
var profile:Dictionary={"updates":0,"active":false,"tickets":0,"turns":0,"teleports":0,"max_update_us":0}
var _owner:WeakRef
var _tickets:Dictionary={}
var _velocity:=Vector3.ZERO
var _last_position:=Vector3.ZERO
var _last_msec:=-1
var _moving_msec:=-1

func update(queue:Node,feet:Vector3,velocity:Vector3,route:PackedVector3Array=PackedVector3Array(),now_msec:int=-1)->void:
	var started:=Time.get_ticks_usec()
	var previous:Node=_owner.get_ref() if _owner!=null else null
	if previous!=queue:release(previous)
	if not is_instance_valid(queue) or not enabled or not feet.is_finite() or not velocity.is_finite():release(queue);return
	_owner=weakref(queue)
	if now_msec<0:now_msec=Time.get_ticks_msec()
	var flat:=Vector3(velocity.x,0,velocity.z);var speed:=flat.length()
	var dt:=maxf(.001,(now_msec-_last_msec)/1000.) if _last_msec>=0 else .25
	if _last_msec>=0 and feet.distance_to(_last_position)>maxf(64.,maxf(speed,_velocity.length())*dt*4.):
		profile.teleports+=1;release(queue);_owner=weakref(queue)
	_last_position=feet;_last_msec=now_msec
	if not predictive_enabled:
		if speed<.25 or queue._reference_index.is_empty():release(queue);return
		var cell:=Stream.chunk_key(feet+flat.normalized()*clampf(speed*6.,160.,256.))
		_apply(queue,{DEMAND:_clip(cell)},"building")
	elif speed<.25:
		# Brief stops must not cancel and re-read sources on the next step.
		# Explicit cancellation/transfer bypasses this short hold.
		if _moving_msec<0 or now_msec-_moving_msec>=STOP_HOLD_MSEC:release(queue)
	else:
		_moving_msec=now_msec
		if _velocity.length_squared()<.0625 or _velocity.normalized().dot(flat.normalized())<.5:
			if _velocity.length_squared()>=.0625:profile.turns+=1
			_velocity=flat
		else:_velocity=_velocity.lerp(flat,1.-exp(-dt/.35))
		# Reach beyond the 128 m live ring. Observed dispatch-to-publication
		# latency can extend the lead, with a hard 256 m cap.
		var seconds:=clampf(float(queue.profile.get("preparation_p90_seconds",6.))+2.,6.,30.)
		var distance:=clampf(speed*seconds,160.,256.)
		var points:=route
		if points.is_empty():points=PackedVector3Array([feet+_velocity.normalized()*distance])
		_apply(queue,_corridor(feet,points,distance),"all")
		profile.lead_seconds=seconds;profile.distance_m=distance;profile.known_route=not route.is_empty()
	profile.updates+=1;profile.max_update_us=maxi(profile.max_update_us,Time.get_ticks_usec()-started)

func _corridor(feet:Vector3,route:PackedVector3Array,distance:float)->Dictionary:
	var plan:Dictionary={};var cursor:=feet;var remaining:=distance
	# Sample segments and corners; never cut straight to the final click goal
	# or extend beyond the navigation-approved route.
	for i:int in mini(route.size(),MAX_ROUTE_POINTS):
		if not route[i].is_finite():break
		var end:=Vector3(route[i].x,feet.y,route[i].z)
		var length:=cursor.distance_to(end)
		if length<.001:continue
		var direction:=(end-cursor)/length;var travel:=minf(length,remaining)
		var progress:=minf(Stream.CHUNK_M,travel)
		while true:
			var cell:=Stream.chunk_key(cursor+direction*progress)
			plan[DEMAND+"/%d/%d"%[cell.x,cell.y]]=_clip(cell)
			if plan.size()>=MAX_TICKETS:return plan
			if progress>=travel:break
			progress=minf(progress+Stream.CHUNK_M,travel)
		remaining-=travel
		if remaining<=.001:break
		cursor=end
	return plan

func _clip(cell:Vector2i)->AABB:
	var centre:=Vector3((cell.x+.5)*Stream.CHUNK_M,0,(cell.y+.5)*Stream.CHUNK_M)
	return AABB(centre-Vector3(48,100000,48),Vector3(96,200000,96))

func _apply(queue:Node,plan:Dictionary,kind:String)->void:
	if kind=="all":plan=_coalesce(plan)
	for id:String in _tickets:
		if not plan.has(id):queue.release_demand(id)
	for id:String in plan:queue.set_demand(id,plan[id],2,kind,kind=="all")
	_tickets=plan
	profile.active=not plan.is_empty();profile.tickets=plan.size()

func _coalesce(plan:Dictionary)->Dictionary:
	# Adjacent samples overlap heavily. Merge only exact rectangular unions,
	# avoiding repeated candidate scans without filling in a route's corner.
	var clips:Array=plan.values();var changed:=true
	while changed:
		changed=false
		for i:int in clips.size():
			for j:int in range(i+1,clips.size()):
				var a:AABB=clips[i];var b:AABB=clips[j]
				var same_x:=a.position.x==b.position.x and a.end.x==b.end.x
				var same_z:=a.position.z==b.position.z and a.end.z==b.end.z
				if not a.encloses(b) and not b.encloses(a) and not (same_x and a.position.z<=b.end.z and b.position.z<=a.end.z) and not (same_z and a.position.x<=b.end.x and b.position.x<=a.end.x):continue
				clips[i]=a.merge(b);clips.remove_at(j);changed=true;break
			if changed:break
	var result:Dictionary={}
	for clip:AABB in clips:
		result[DEMAND+"/rect/%d/%d/%d/%d"%[clip.position.x,clip.position.z,clip.end.x,clip.end.z]]=clip
	return result

func release(queue:Node=null)->void:
	var owner:Node=_owner.get_ref() if _owner!=null else null
	for target:Node in [owner,queue]:
		if not is_instance_valid(target):continue
		for id:String in _tickets:target.release_demand(id)
		target.release_demand(DEMAND)
	_tickets.clear();_owner=null;_velocity=Vector3.ZERO;_last_msec=-1;_moving_msec=-1
	profile.active=false;profile.tickets=0
