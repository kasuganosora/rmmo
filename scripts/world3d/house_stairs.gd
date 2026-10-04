extends "res://scripts/world3d/building_geometry.gd"
## Closed risers and continuous joinery; dimensions are in metres.

static func rail(plan: Dictionary, key: String, a: Vector3, b: Vector3, colors: Dictionary, f: int, start_post:bool=true, end_post:bool=true) -> void:
	var delta:=b-a
	var count:=maxi(1,ceili(Vector2(delta.x,delta.z).length()/.24))
	for i in count+1:
		if (i==0 and not start_post) or (i==count and not end_post):continue
		var foot:=a.lerp(b,float(i)/count)
		var newel:bool=i==0 or i==count
		var thickness:=.14 if newel else .045
		var post_height:=1.12 if newel else 1.08
		box(plan,key+"/post%d"%i,foot+Vector3.UP*(post_height/2-.04),Vector3(thickness,post_height,thickness),colors.trim,f,"rail")
		if not newel:plan.records.back().collision="none"
	var beam:=preload("res://scripts/world3d/roof_mesh.gd").beam(key+"/handrail",a+Vector3.UP*1.04,b+Vector3.UP*1.04,.11,.10,colors.trim,f,f*plan.parameters.floor_height)
	beam.building.role="rail"; plan.records.append(beam)
	var lower:=preload("res://scripts/world3d/roof_mesh.gd").beam(key+"/lower",a+Vector3.UP*.28,b+Vector3.UP*.28,.055,.065,colors.trim,f,f*plan.parameters.floor_height)
	lower.building.role="rail"; plan.records.append(lower)

static func flight(plan: Dictionary,key: String,left: float,right: float,z0: float,z1: float,y: float,h: float,n: int,colors: Dictionary,f: int) -> void:
	var tread: float=(z1-z0)/n
	var rise:=h/n
	for i in n:
		# The riser extends below the preceding tread: no see-through strips.
		box(plan,key+"/step%d"%i,Vector3((left+right)/2,y+(i+1)*rise-(rise+.035)/2,z0+(i+.5)*tread),Vector3(right-left,rise+.035,absf(tread)),colors.floor,f,"stairs")
	for side in [0,1]:
		var x: float=left-.045 if side==0 else right+.045
		var a:=Vector3(x,y,z0);var b:=Vector3(x,y+h,z1)
		if not (side==1 and near_wall(plan,x)):rail(plan,key+"/guard%d"%side,a,b,colors,f)
		var beam:=preload("res://scripts/world3d/roof_mesh.gd").beam(key+"/stringer%d"%side,a-Vector3.UP*.18,b-Vector3.UP*.18,.10,.28,colors.trim,f,f*plan.parameters.floor_height)
		beam.building.role="stairs";plan.records.append(beam)

static func near_wall(plan:Dictionary,x:float)->bool:
	return absf(float(plan.parameters.width)/2-WALL-x)<.3

static func build(plan: Dictionary,key: String,left: float,right: float,z0: float,z1: float,y: float,h: float,steps: int,colors: Dictionary,f: int) -> void:
	if plan.parameters.get("stair_layout","straight")=="straight":
		flight(plan,key,left,right,z0,z1,y,h,steps,colors,f)
		plan.stairs.append({"floor":f,"hole":[left-.10,z0,right+.10,z1],"bottom":[(left+right)/2,y,z0-.6],"top":[(left+right)/2,y+h,z1+.6]})
		return
	var width:float=plan.parameters.stair_width
	var landing:float=plan.parameters.stair_landing
	var end:=z1-landing
	var middle:=(left+right)/2
	flight(plan,key+"/lower",left,left+width,z0,end,y,h/2,steps/2,colors,f)
	flight(plan,key+"/upper",right-width,right,end,z0,y+h/2,h/2,steps/2,colors,f)
	slab(plan,key+"/turn",left-.1,right+.1,end,z1,y+h/2,colors.floor,f)
	plan.records.back().building.role="stairs"
	# The two flights arrive at one supported landing. Join each outside rake
	# to its level return rail, and close the far edge without blocking the turn.
	for side in [0,1]:
		var x:float=left-.045 if side==0 else right+.045
		if not (side==1 and near_wall(plan,x)):rail(plan,key+"/return%d"%side,Vector3(x,y+h/2,end),Vector3(x,y+h/2,z1-.05),colors,f,false)
		for at in [end+.12,z1-.14]:
			box(plan,key+"/support%d_%s"%[side,str(at)],Vector3(x,y+h/4-.09,at),Vector3(.16,h/2-.18,.16),colors.trim,f,"stairs")
		box(plan,key+"/landing_beam%d"%side,Vector3(x,y+h/2-.27,(end+z1)/2),Vector3(.18,.22,z1-end),colors.trim,f,"stairs")
	rail(plan,key+"/turn_guard",Vector3(left-.045,y+h/2,z1-.05),Vector3(right+.045,y+h/2,z1-.05),colors,f,false,false)
	# The inner rakes meet a shared central newel rather than dangling apart.
	box(plan,key+"/turn_newel",Vector3(middle,y+h/2+.56,end),Vector3(.22,1.16,.16),colors.trim,f,"rail")
	var route: Array=[[left+width/2,y,z0-.6],[left+width/2,y+h/2,end+.6],[right-width/2,y+h/2,end+.6],[right-width/2,y+h,z0-.6]]
	plan.stairs.append({"floor":f,"hole":[left-.1,z0,right+.1,z1],"bottom":route[0],"top":route[3],"waypoints":route})

static func well_guard(plan: Dictionary,key: String,left: float,right: float,z0: float,z1: float,y: float,colors: Dictionary,f: int) -> void:
	for side in [0,1]:
		var x:float=left-.1 if side==0 else right+.1
		if side==1 and near_wall(plan,x):continue
		rail(plan,key+"/side%d"%side,Vector3(x,y,z0),Vector3(x,y,z1),colors,f)
	if plan.parameters.get("stair_layout","straight")=="straight":
		rail(plan,key+"/end",Vector3(left,y,z0),Vector3(right,y,z0),colors,f)
	else:
		rail(plan,key+"/end",Vector3(left,y,z1),Vector3(right,y,z1),colors,f)
		# Only the returning upper flight is an entrance. Close the other half
		# of the near edge, where stepping forward would drop onto the lower run.
		rail(plan,key+"/front",Vector3(left-.1,y,z0),Vector3(right-float(plan.parameters.stair_width)-.045,y,z0),colors,f,false,false)
