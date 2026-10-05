extends RefCounted
static func vec(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
static func arr(v:Vector3)->Array:return [v.x,v.y,v.z]

static func target_room(plan:Dictionary,o:Dictionary)->Dictionary:
	var adjacent:Array=[]
	var axis:=2 if o.axis=="x" else 0
	for room:Dictionary in plan.rooms:
		if absf(float(room.center[1])-float(o.floor_y))>.01:continue
		var b:Array=room.bounds
		var low:float=b[1] if axis==2 else b[0];var high:float=b[3] if axis==2 else b[2]
		var u0:float=b[0] if axis==2 else b[1];var u1:float=b[2] if axis==2 else b[3]
		if o.u>=u0 and o.u<=u1 and minf(absf(o.fixed-low),absf(o.fixed-high))<.31:adjacent.append(room)
	var known:bool=o.wall.contains("partition") or o.wall.ends_with("/interior")
	if not known and adjacent.size()<2:return {}
	# A connected wing is a room off the main hall, not an exterior entrance.
	for room:Dictionary in adjacent:
		if str(room.id).begins_with("wing"):return room
	for room:Dictionary in adjacent:
		if room.id==o.room:return room
	return {}

static func apply(plan:Dictionary)->void:
	plan.interior_door_replacements=[]
	for o:Dictionary in plan.openings:
		if o.type!="door":continue
		var room:=target_room(plan,o)
		if room.is_empty():continue
		var prefix:String=o.wall+"/"+o.id;var fixture_id:=prefix+"/door"
		var old:Array=plan.records.filter(func(r):return r.building.part.begins_with(prefix+"/") and (r.building.part.contains("/door/") or r.building.part.get_slice("/",r.building.part.get_slice_count("/")-1) in ["jamb-1","jamb1","head"]))
		var leaves:Array=old.filter(func(r):return r.get("fixture",{}).get("id")==fixture_id)
		if leaves.size()!=1:continue
		var leaf:Dictionary=leaves[0].duplicate(true)
		var width:float=o.width-.10;var height:float=o.height-.055
		var axis:=2 if o.axis=="x" else 0;var inward:=Vector3.ZERO
		inward[axis]=signf(float(room.center[axis])-float(o.fixed))
		var yaw:float=rad_to_deg(atan2(inward.x,inward.z))
		leaf.size=[width,height,.075];leaf.rotation=[0,yaw,0];leaf.building_shape="interior_door"
		leaf.fixture={"id":fixture_id,"kind":"door","pivot":[-width/2,0,0],"angle":-90.0,"open":leaves[0].fixture.open}
		var frame:Dictionary=leaf.duplicate(true);frame.erase("fixture")
		frame.building.part=prefix+"/frame";frame.building.role="frame";frame.uuid=frame.building.part.replace("/","_");frame.editor_name=frame.building.part
		frame.building_shape="interior_door_frame";frame.size=[width*1.428/1.2,height*2.32/2.2,.27]
		frame.position=arr(vec(leaf.position)+Vector3(0,.054*height/2.2,0))
		plan.records=plan.records.filter(func(r):return not old.has(r))
		plan.records.append(frame);plan.records.append(leaf)
		plan.interior_door_replacements.append({"id":fixture_id,"old":old,"leaf":leaf,"frame":frame,"room":room.id,"inward":arr(inward)})
