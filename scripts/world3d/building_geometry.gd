extends RefCounted
## Geometry primitives shared by versioned building layouts.
const WALL := .2
const SLAB := .22
static var _unit_cylinder:Mesh
const Fixtures = preload("res://scripts/world3d/building_fixtures.gd")

static func vec(v: Array) -> Vector3: return Vector3(v[0],v[1],v[2])
static func arr(v: Vector3) -> Array: return [v.x,v.y,v.z]

static func box(plan: Dictionary, key: String, position: Vector3, size: Vector3, color: Array, floor_: int, role: String, rotation := Vector3.ZERO) -> void:
	plan.records.append({"uuid":key.replace("/","_"),"kind":"box","surface_id":"ground" if role=="floor" else "block","position":arr(position),"size":arr(size),"rotation":arr(rotation),"color":color.duplicate(),"editor_name":key,"building":{"part":key,"floor":floor_,"role":role,"floor_y":0.0}})

	if role in ["beam","bracket","stone_trim"]:plan.records.back().collision="none"

static func slab(plan: Dictionary, key: String, x0: float, x1: float, z0: float, z1: float, y: float, color: Array, floor_: int) -> void:
	# Finished boards/paving sit above the structural storey datum. Otherwise
	# the lower wall's cap and the finished floor occupy exactly the same plane.
	const FINISH:=.018
	if x1-x0>.001 and z1-z0>.001: box(plan,key,Vector3((x0+x1)/2,y+(FINISH-SLAB)/2,(z0+z1)/2),Vector3(x1-x0,SLAB+FINISH,z1-z0),color,floor_,"floor")

static func wall(plan: Dictionary, key: String, axis: String, fixed: float, start: float, end: float, y: float, height: float, openings: Array, colors: Dictionary, floor_: int) -> void:
	for opening in openings:
		if plan.parameters.get("window_style","casement")!="casement":load("res://scripts/world3d/house_window_styles.gd").prepare(plan,opening,height)
		if opening.type=="door":
			opening.height=plan.parameters.get("door_height",2.2)
			opening.width=maxf(opening.width,plan.parameters.get("door_width",1.3))
	var us: Array = [start,end]; var vs: Array = [0.0,height]
	for opening in openings:
		us.append(opening.u-opening.width/2); us.append(opening.u+opening.width/2)
		vs.append(opening.bottom); vs.append(opening.bottom+opening.height)
	us.sort(); vs.sort()
	var grid:=preload("res://scripts/world3d/house_wall_mesh.gd").grid(us,vs,openings,start,end,height)
	wall_box(plan,key+"/solid",axis,fixed,(start+end)/2,y+height/2,end-start,height,WALL,colors.wall,floor_,"wall")
	plan.records.back().building_shape="wall_grid"
	grid.axis=axis;plan.records.back().wall_grid=grid
	for opening in openings:
		var o: Dictionary = opening.duplicate(true); o.wall = key; o.axis = axis; o.fixed = fixed; o.floor_y = y
		plan.openings.append(o)
		if o.type=="window" and plan.parameters.get("window_style","casement")!="casement":
			load("res://scripts/world3d/house_window_styles.gd").build(plan,key,axis,fixed,o,y,colors,floor_)
			continue
		var prefix := key+"/"+str(o.id)
		# Seat the jamb over the opening edge. A flush inner face coincides with
		# the wall reveal and flickers once the two receive different materials.
		for side in [-1,1]: wall_box(plan,prefix+"/jamb%d"%side,axis,fixed,o.u+side*(o.width/2-.015),y+o.bottom+o.height/2,.07,o.height+.14,WALL+.07,colors.trim,floor_,"frame")
		wall_box(plan,prefix+"/head",axis,fixed,o.u,y+o.bottom+o.height-.015,o.width+.14,.07,WALL+.07,colors.trim,floor_,"frame")
		if o.type=="shopfront":
			wall_box(plan,prefix+"/counter",axis,fixed-.13,o.u,y+o.bottom-.05,o.width+.24,.14,.65,colors.trim,floor_,"counter")
			wall_box(plan,prefix+"/sign",axis,fixed-WALL/2-.09,o.u,y+o.bottom+o.height+.40,o.width*.85,.38,.10,colors.trim,floor_,"shop_sign")
			for side in [-1,1]:iron(plan,prefix+"/sign_hanger"+str(side),axis,fixed-WALL/2-.09,o.u+side*o.width*.3,y+o.bottom+o.height+.67,.04,.19,.04,floor_)
		elif o.type=="window":
			wall_box(plan,prefix+"/sill",axis,fixed,o.u,y+o.bottom+.015,o.width+.14,.07,WALL+.14,colors.trim,floor_,"frame")
			wall_box(plan,prefix+"/mullion",axis,fixed,o.u,y+o.bottom+o.height/2,.075,o.height,.07,colors.trim,floor_,"frame")
			for side in [-1,1]:
				var leaf: String=prefix+"/casement"+str(side)
				var hinge_u:float=o.u+side*(o.width/2-.04)
				window_hinges(plan,leaf,axis,fixed,hinge_u,y+o.bottom+o.height/2,o.height,side,floor_,false)
				var first: int=plan.records.size()
				var width: float=o.width/2-.055; var h: float=o.height-.09
				var u: float=o.u+side*(o.width/4-.015); var center: float=y+o.bottom+o.height/2
				wall_box(plan,leaf+"/glass",axis,fixed,u,center,width-.08,h-.08,.025,colors.glass,floor_,"window")
				for edge in [-1,1]:
					wall_box(plan,leaf+"/stile"+str(edge),axis,fixed,u+edge*(width/2-.025),center,.05,h,.07,colors.trim,floor_,"frame")
					wall_box(plan,leaf+"/rail"+str(edge),axis,fixed,u,center+edge*(h/2-.025),width,.05,.07,colors.trim,floor_,"frame")
				for level in [-1,1]: wall_box(plan,leaf+"/bar"+str(level),axis,fixed,u,center+level*h/6,width,.032,.04,colors.trim,floor_,"frame")
				window_hinges(plan,leaf,axis,fixed,hinge_u,center,o.height,side,floor_,true)
				# A small latch sits on the meeting stile, never on the glass pane.
				var latch_u:float=u-side*(width/2-.025)
				for face in [-1,1]:
					iron(plan,leaf+"/handle%d/base"%face,axis,fixed+face*.039,latch_u,center,.04,.14,.012,floor_)
					iron(plan,leaf+"/handle%d/grip"%face,axis,fixed+face*.055,latch_u,center,.018,.085,.025,floor_)
				var pivot:=wall_position(axis,fixed,hinge_u,center)
				Fixtures.attach(plan,first,leaf,"window",pivot,hinge_sign(key,axis,side)*95,0)
			curtains(plan,key+"/"+str(o.id),axis,fixed,o,y,colors,floor_)
		else:
			var h: float=o.height-.055
			var width: float=o.width-.10; var center: float=y+o.bottom+.025+h/2
			var hinge_side:=1 if o.id=="balcony_door" else -1
			hinges(plan,prefix+"/door",axis,fixed,o.u+hinge_side*width/2,center,h,hinge_side,floor_,false)
			var first:int=plan.records.size()
			var leaf_yaw:=0.0 if axis=="x" else -90.0
			if hinge_side==1:leaf_yaw+=180.0
			box(plan,prefix+"/door/leaf",wall_position(axis,fixed,o.u,center),Vector3(width,h,.065),colors.trim,floor_,"door",Vector3(0,leaf_yaw,0))
			plan.records.back().building_shape="timber_door"
			var turn:=hinge_sign(key,axis,hinge_side)*90
			# Exterior leaves open into the room, keeping steps and balconies clear.
			if key.get_slice("/",key.get_slice_count("/")-1) in ["north","south","east","west"] or o.id in ["balcony_door","living_side"]:turn=-turn
			Fixtures.attach(plan,first,prefix+"/door","door",wall_position(axis,fixed,o.u+hinge_side*width/2,center),turn,1)

static func wall_position(axis: String, fixed: float, u: float, y: float) -> Vector3:
	return Vector3(u,y,fixed) if axis=="x" else Vector3(fixed,y,u)

static func iron(plan: Dictionary,key: String,axis: String,fixed: float,u: float,y: float,w: float,h: float,d: float,f: int,cylinder:=false) -> void:
	wall_box(plan,key,axis,fixed,u,y,w,h,d,[.12,.13,.14],f,"hardware")
	plan.records.back().collision="none"
	if cylinder: plan.records.back().building_shape="cylinder"

static func hinges(plan: Dictionary,key: String,axis: String,fixed: float,pivot_u: float,center: float,height: float,side: int,f: int,moving: bool) -> void:
	for level in [-1,1]:
		var y:float=center+level*height*.33
		var k:=key+"/hinge%d/"%level
		if moving:
			iron(plan,k+"strap",axis,fixed-.044,pivot_u-side*.18,y,.36,.055,.023,f)
			iron(plan,k+"knuckle",axis,fixed,pivot_u,y,.085,.10,.085,f,true)
		else:
			iron(plan,k+"pin",axis,fixed,pivot_u,y,.035,.20,.035,f,true)
			iron(plan,k+"socket",axis,fixed,pivot_u,y-.075,.09,.045,.09,f,true)
			iron(plan,k+"plate",axis,fixed,pivot_u+side*.045,y,.09,.22,.10,f)

static func handles(plan: Dictionary,key: String,axis: String,fixed: float,u: float,y: float,thickness: float,f: int) -> void:
	for side in [-1,1]:
		var face:float=fixed+side*thickness/2
		iron(plan,key+"/handle%d/base"%side,axis,face+side*.009,u,y,.085,.23,.022,f)
		for level in [-1,1]: iron(plan,key+"/handle%d/stem%d"%[side,level],axis,face+side*.035,u,y+level*.065,.035,.035,.065,f)
		iron(plan,key+"/handle%d/grip"%side,axis,face+side*.065,u,y,.036,.16,.035,f)

static func window_hinges(plan:Dictionary,key:String,axis:String,fixed:float,pivot_u:float,center:float,height:float,side:int,f:int,moving:bool)->void:
	for level in [-1,1]:
		var y:float=center+level*(height/2-.07)
		var k:=key+"/hinge%d/"%level
		if moving:
			iron(plan,k+"leaf",axis,fixed-.04,pivot_u-side*.035,y,.065,.035,.012,f)
			iron(plan,k+"knuckle",axis,fixed,pivot_u,y,.032,.065,.032,f,true)
		else:
			iron(plan,k+"pin",axis,fixed,pivot_u,y,.015,.085,.015,f,true)
			iron(plan,k+"plate",axis,fixed-.04,pivot_u+side*.022,y,.045,.05,.012,f)

static func curtains(plan: Dictionary,key: String,axis: String,fixed: float,o: Dictionary,y: float,colors: Dictionary,f: int) -> void:
	if not plan.parameters.get("curtains",false): return
	var exterior:=key.contains("/north/") or key.contains("/west/")
	var inside:=1.0 if exterior else -1.0
	var plane:=fixed+inside*(WALL/2+.18)
	var top:float=y+o.bottom+o.height+.18
	# A horizontal pole sits in wall-mounted cradles; the pocket front faces
	# into the room on all four elevations, not always toward world +Z/+X.
	box(plan,key+"/curtain/rod",wall_position(axis,plane,o.u,top),Vector3(.045,o.width+.65,.045),colors.trim,f,"curtain_rod",Vector3(0,0,90) if axis=="x" else Vector3(90,0,0))
	plan.records.back().merge({"collision":"none","building_shape":"cylinder"})
	for end in [-1,1]:
		var mount_u:float=o.u+end*(o.width/2+.25)
		var wall_face:=fixed+inside*WALL/2
		iron(plan,key+"/curtain/support%d/plate"%end,axis,wall_face+inside*.006,mount_u,top-.055,.075,.18,.025,f)
		iron(plan,key+"/curtain/support%d/arm"%end,axis,(wall_face+plane)/2+inside*.015,mount_u,top-.037,.055,.03,.21,f)
		for lip in [-1,1]:
			iron(plan,key+"/curtain/support%d/lip%d"%[end,lip],axis,plane+lip*.029,mount_u,top-.01,.055,.04,.014,f)
	for side in [-1,1]:
		var u:float=o.u+side*(o.width/2-.025)
		wall_box(plan,key+"/curtain/panel%d"%side,axis,plane,u,top-(o.height+.36)/2,.44,o.height+.36,.16,[.78,.73,.62],f,"curtain")
		plan.records.back().merge({"collision":"none","building_shape":"draped_cloth","cloth":{"axis":axis,"side":side}})
		if inside<0:
			plan.records.back().rotation=[0,180,0]
			plan.records.back().cloth.side=-side # Preserve the pair's mirrored folds.

static func hinge_sign(key: String, axis: String, side: int) -> float:
	# Room doors on the west side of a hall swing into the room, so an open
	# leaf never consumes the shared corridor's designed clearance.
	var outward := -1.0 if key.ends_with("west") or key.ends_with("north") or key.ends_with("interior") else 1.0
	return side*outward*(1.0 if axis=="x" else -1.0)

static func finish_plan(plan: Dictionary) -> Dictionary:
	if not plan.get("ok",false): return plan
	if plan.has("roof_modules"):
		var solved:=preload("res://scripts/world3d/roof_plan.gd").solve(plan.roof_modules,plan.get("roof_openings",[]))
		if not solved.ok: return solved
		plan.roof_plan=solved
		plan.records.append_array(preload("res://scripts/world3d/roof_mesh.gd").generate(solved))
		plan.erase("roof_modules"); plan.erase("roof_openings")
	preload("res://scripts/world3d/joined_box_mesh.gd").apply(plan)
	# Raise the complete interior, including articulated pivots (which are local),
	# before extending foundations down to the terrain datum.
	var raised:float=plan.parameters.get("base_height",0.0) if plan.parameters.get("layout") in ["townhouse","hall"] else 0.0
	if raised>0:
		for record in plan.records:
			record.position[1]+=raised;record.building.floor_y+=raised
		for room_ in plan.rooms: room_.center[1]+=raised
		for o in plan.openings: o.floor_y+=raised
		for stair in plan.stairs:
			stair.bottom[1]+=raised;stair.top[1]+=raised
			# Endpoints can alias the route entries.
			if stair.has("waypoints"):
				for i in range(1,stair.waypoints.size()-1):stair.waypoints[i][1]+=raised
		for joint in plan.get("frame_joints",[]):joint.start[1]+=raised;joint.end[1]+=raised
		for volume in plan.get("volumes",[]):volume.top+=raised
		for o in plan.openings:
			if o.type!="door" or not o.wall.ends_with("north") or o.floor_y>raised+.01:continue
			if not o.id in ["entrance","entry"]:continue
			var count:=ceili(raised/.15)
			for i in count:
				var top:=raised*(count-i)/count
				wall_box(plan,o.wall+"/entry_step%d"%i,o.axis,o.fixed-WALL/2-.18-i*.38,o.u,top/2,o.width+.65,top,.38,[.5,.47,.40],0,"entry_step")
		# The courtyard is also a raised floor. Its open street edge needs the
		# same walkable connection as a front door, rather than a .45 m cliff.
		if plan.parameters.get("compound")=="courtyard":
			var p:Dictionary=plan.parameters
			var edge:float=p.depth/2+p.annex_depth
			var width:float=p.width-2*p.annex_width
			var count:=ceili(raised/.15)
			for i in count:
				var top:=raised*(count-i)/count
				box(plan,"yard/entry_step%d"%i,Vector3(0,top/2,edge+.19+i*.38),Vector3(width,top,.38),[.5,.47,.40],0,"entry_step")
		plan.size[1]+=raised
	# One metre below terrain, not merely below the raised slab.
	# Each ground slab owns its foundation, so annexes and split footprints match.
	var depth: float=plan.parameters.get("foundation_depth",1.0)
	if depth>0:
		var slabs: Array=plan.records.filter(func(r):return r.building.floor==0 and r.building.role=="floor")
		for record in slabs:
			var size:=vec(record.size); var at:=vec(record.position)
			# A half-storey stair landing may also be tagged floor 0; it is not
			# a ground slab and must not acquire a suspended block of foundation.
			if at.y-size.y/2>float(record.building.floor_y)+.05:continue
			var total:=depth+raised
			at.y-=size.y/2+total/2; size.y=total
			box(plan,record.building.part+"/foundation",at,size,[.43,.42,.36],0,"foundation",vec(record.rotation))
			plan.records.back().building.floor_y=record.building.floor_y
	preload("res://scripts/world3d/house_candle_layout.gd").add_to_plan(plan)
	preload("res://scripts/world3d/interior_door_layout.gd").apply(plan)
	plan.version=8
	return plan

static func wall_box(plan: Dictionary, key: String, axis: String, fixed: float, u: float, y: float, width: float, height: float, depth: float, color: Array, floor_: int, role: String) -> void:
	box(plan,key,Vector3(u,y,fixed) if axis=="x" else Vector3(fixed,y,u),Vector3(width,height,depth) if axis=="x" else Vector3(depth,height,width),color,floor_,role)

static func gable_mesh(size: Vector3, material: Material) -> ArrayMesh:
	var vertices := [Vector3(-size.x/2,-size.y/2,-size.z/2),Vector3(size.x/2,-size.y/2,-size.z/2),Vector3(0,size.y/2,-size.z/2),Vector3(-size.x/2,-size.y/2,size.z/2),Vector3(size.x/2,-size.y/2,size.z/2),Vector3(0,size.y/2,size.z/2)]
	var mesh := SurfaceTool.new(); mesh.begin(Mesh.PRIMITIVE_TRIANGLES); mesh.set_material(material)
	for index in [0,1,2,5,4,3,0,3,4,0,4,1,0,2,5,0,5,3,2,1,4,2,4,5]:
		var point: Vector3 = vertices[index]; mesh.set_uv(Vector2(point.x,point.y)); mesh.add_vertex(point)
	mesh.generate_normals(); return mesh.commit()

static func cylinder_mesh(size: Vector3, material: Material) -> ArrayMesh:
	if _unit_cylinder==null:
		var cylinder:=CylinderMesh.new();cylinder.top_radius=.5;cylinder.bottom_radius=.5;cylinder.height=1;cylinder.radial_segments=16
		_unit_cylinder=preload("res://scripts/world3d/ground_cpu_mesh.gd").capture(cylinder)
	var surface:=SurfaceTool.new();surface.append_from(_unit_cylinder,0,Transform3D(Basis.from_scale(size),Vector3.ZERO))
	var arrays:=surface.commit_to_arrays();var result:=ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.surface_set_material(0,material)
	preload("res://scripts/world3d/ground_cpu_mesh.gd").remember(result,[arrays])
	return result
