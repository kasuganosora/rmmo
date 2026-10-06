extends RefCounted
## One wall bracket per room. This is an automatic placement rule, not a manual placement ban.
const Sconce=preload("res://scripts/world3d/candle_sconce_mesh.gd")
const CLEARANCE:=1.0
static func v(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
static func bounds(r:Dictionary)->AABB:
	var b:=Basis.from_euler(v(r.get("rotation",[0,0,0]))*PI/180.0)
	return Transform3D(b,v(r.position))*AABB(-v(r.size)/2,v(r.size))
static func distance(a:AABB,b:AABB)->float:
	var separation:=Vector3.ZERO
	for i in 3:separation[i]=maxf(0,maxf(a.position[i]-b.end[i],b.position[i]-a.end[i]))
	return separation.length()
static func add_to_plan(plan:Dictionary)->void:
	if plan.parameters.get("layout")=="urban_village":return
	var walls:Array=plan.records.filter(func(r):return r.get("building_shape")=="wall_grid")
	var curtains:Array=plan.records.filter(func(r):return r.building.role=="curtain")
	var placed:Array=[]
	for room in plan.rooms:
		var center:=v(room.center);var rect:Array=room.bounds;var candidates:Array=[]
		for wall in walls:
			if wall.building.floor!=room.floor:continue
			var axis:int=0 if wall.wall_grid.axis=="x" else 2;var normal_axis:int=2 if axis==0 else 0
			var at:=v(wall.position);var size:=v(wall.size)
			# A real wall must bound this room, not a distant facade across a hall.
			var low:float=rect[0] if normal_axis==0 else rect[1];var high:float=rect[2] if normal_axis==0 else rect[3]
			if minf(absf(at[normal_axis]-low),absf(at[normal_axis]-high))>.25:continue
			var sign_:float=1.0 if center[normal_axis]>at[normal_axis] else -1.0
			var u0:float=maxf(at[axis]-size[axis]/2+.5,rect[0 if axis==0 else 1]+.5)
			var u1:float=minf(at[axis]+size[axis]/2-.5,rect[2 if axis==0 else 3]-.5)
			var u:float=u0
			while u<=u1:
				var p:=at;p[axis]=u;p.y=center.y+2.15;p[normal_axis]+=sign_*(size[normal_axis]/2+.205)
				var rotation:float=0.0 if normal_axis==2 and sign_>0 else (180.0 if normal_axis==2 else (90.0 if sign_>0 else -90.0))
				var record:Dictionary={"position":[p.x,p.y,p.z],"size":[.26,.54,.46],"rotation":[0,rotation,0]}
				var box_:=bounds(record);var safe:=true
				for cloth in curtains:
					if distance(box_,bounds(cloth))<CLEARANCE:safe=false;break
				# Keep the entire bracket on masonry and clear of door/window reveals.
				for o in plan.openings:
					if o.wall!=wall.building.part.trim_suffix("/solid"):continue
					if absf(u-o.u)<o.width/2+.3:safe=false;break
				for previous in placed:
					if p.distance_to(previous)<2.0:safe=false
				if safe:candidates.append({"record":record,"score":absf(u-center[axis]),"wall":wall})
				u+=.4
		if candidates.is_empty():continue
		candidates.sort_custom(func(a,b):return a.score<b.score)
		var chosen:Dictionary=candidates[0];var record:Dictionary=chosen.record
		var key:String=room.id+"/candle_sconce"
		record.merge({"uuid":key.replace("/","_"),"kind":"box","surface_id":"block","color":[.1,.08,.06],"editor_name":key,"collision":"none","building_shape":"candle_sconce","building":{"part":key,"floor":room.floor,"floor_y":center.y,"role":"light_sconce"}})
		plan.records.append(record);placed.append(v(record.position))
