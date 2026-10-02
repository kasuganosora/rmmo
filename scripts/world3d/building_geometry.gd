extends RefCounted
## Geometry primitives shared by versioned building layouts.
const WALL := .2
const SLAB := .22
const Fixtures = preload("res://scripts/world3d/building_fixtures.gd")

static func vec(v: Array) -> Vector3: return Vector3(v[0],v[1],v[2])
static func arr(v: Vector3) -> Array: return [v.x,v.y,v.z]

static func box(plan: Dictionary, key: String, position: Vector3, size: Vector3, color: Array, floor_: int, role: String, rotation := Vector3.ZERO) -> void:
	plan.records.append({"uuid":key.replace("/","_"),"kind":"box","surface_id":"ground" if role=="floor" else "block","position":arr(position),"size":arr(size),"rotation":arr(rotation),"color":color.duplicate(),"editor_name":key,"building":{"part":key,"floor":floor_,"role":role,"floor_y":0.0}})

static func slab(plan: Dictionary, key: String, x0: float, x1: float, z0: float, z1: float, y: float, color: Array, floor_: int) -> void:
	if x1-x0>.001 and z1-z0>.001: box(plan,key,Vector3((x0+x1)/2,y-SLAB/2,(z0+z1)/2),Vector3(x1-x0,SLAB,z1-z0),color,floor_,"floor")

static func wall(plan: Dictionary, key: String, axis: String, fixed: float, start: float, end: float, y: float, height: float, openings: Array, colors: Dictionary, floor_: int) -> void:
	for opening in openings:
		if opening.type=="door":
			opening.height=plan.parameters.get("door_height",2.2)
			opening.width=maxf(opening.width,plan.parameters.get("door_width",1.3))
	var us: Array = [start,end]; var vs: Array = [0.0,height]
	for opening in openings:
		us.append(opening.u-opening.width/2); us.append(opening.u+opening.width/2)
		vs.append(opening.bottom); vs.append(opening.bottom+opening.height)
	us.sort(); vs.sort()
	for i in us.size()-1:
		for j in vs.size()-1:
			var a := float(us[i]); var b := float(us[i+1]); var c := float(vs[j]); var d := float(vs[j+1])
			if b-a<.001 or d-c<.001: continue
			var u := (a+b)/2; var v := (c+d)/2
			if openings.any(func(o): return absf(u-o.u)<o.width/2 and v>o.bottom and v<o.bottom+o.height): continue
			wall_box(plan,key+"/solid%d_%d"%[i,j],axis,fixed,u,y+v,b-a,d-c,WALL,colors.wall,floor_,"wall")
	for opening in openings:
		var o: Dictionary = opening.duplicate(true); o.wall = key; o.axis = axis; o.fixed = fixed; o.floor_y = y
		plan.openings.append(o)
		var prefix := key+"/"+str(o.id)
		# Seat the jamb over the opening edge. A flush inner face coincides with
		# the wall reveal and flickers once the two receive different materials.
		for side in [-1,1]: wall_box(plan,prefix+"/jamb%d"%side,axis,fixed,o.u+side*(o.width/2-.015),y+o.bottom+o.height/2,.07,o.height+.14,WALL+.07,colors.trim,floor_,"frame")
		wall_box(plan,prefix+"/head",axis,fixed,o.u,y+o.bottom+o.height-.015,o.width+.14,.07,WALL+.07,colors.trim,floor_,"frame")
		if o.type=="window":
			wall_box(plan,prefix+"/sill",axis,fixed,o.u,y+o.bottom+.015,o.width+.14,.07,WALL+.14,colors.trim,floor_,"frame")
			wall_box(plan,prefix+"/mullion",axis,fixed,o.u,y+o.bottom+o.height/2,.075,o.height,.07,colors.trim,floor_,"frame")
			for side in [-1,1]:
				var leaf: String=prefix+"/casement"+str(side)
				var first: int=plan.records.size()
				var width: float=o.width/2-.055; var h: float=o.height-.09
				var u: float=o.u+side*(o.width/4-.015); var center: float=y+o.bottom+o.height/2
				wall_box(plan,leaf+"/glass",axis,fixed,u,center,width-.08,h-.08,.025,colors.glass,floor_,"window")
				for edge in [-1,1]:
					wall_box(plan,leaf+"/stile"+str(edge),axis,fixed,u+edge*(width/2-.025),center,.05,h,.07,colors.trim,floor_,"frame")
					wall_box(plan,leaf+"/rail"+str(edge),axis,fixed,u,center+edge*(h/2-.025),width,.05,.07,colors.trim,floor_,"frame")
				for level in [-1,1]: wall_box(plan,leaf+"/bar"+str(level),axis,fixed,u,center+level*h/6,width,.032,.04,colors.trim,floor_,"frame")
				var pivot:=wall_position(axis,fixed,o.u+side*(o.width/2-.04),center)
				Fixtures.attach(plan,first,leaf,"window",pivot,hinge_sign(key,axis,side)*95,0)
		else:
			var first: int=plan.records.size(); var h: float=o.height-.055
			var width: float=o.width-.10; var center: float=y+o.bottom+.025+h/2
			var hinge_side:=1 if o.id=="balcony_door" else -1
			wall_box(plan,prefix+"/door/leaf",axis,fixed,o.u,center,width,h,.065,colors.trim,floor_,"door")
			for level in [-1,1]: wall_box(plan,prefix+"/door/rail"+str(level),axis,fixed-.05,o.u,center+level*h*.32,width-.08,.12,.045,colors.trim,floor_,"door")
			wall_box(plan,prefix+"/door/handle",axis,fixed-.085,o.u-hinge_side*width*.35,y+o.bottom+1.05,.045,.16,.06,[.17,.14,.1],floor_,"hardware")
			var turn:=hinge_sign(key,axis,hinge_side)*90
			# A leaf opening across a shallow balcony can seal its entire width.
			if o.id in ["balcony_door","living_side"]:turn=-turn
			Fixtures.attach(plan,first,prefix+"/door","door",wall_position(axis,fixed,o.u+hinge_side*width/2,center),turn,1)

static func wall_position(axis: String, fixed: float, u: float, y: float) -> Vector3:
	return Vector3(u,y,fixed) if axis=="x" else Vector3(fixed,y,u)

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
	# Extend one metre below the existing slab underside, without raising rooms.
	# Each ground slab owns its foundation, so annexes and split footprints match.
	var depth: float=plan.parameters.get("foundation_depth",1.0)
	if depth>0:
		var slabs: Array=plan.records.filter(func(r):return r.building.floor==0 and r.building.role=="floor")
		for record in slabs:
			var size:=vec(record.size); var at:=vec(record.position)
			at.y-=size.y/2+depth/2; size.y=depth
			box(plan,record.building.part+"/foundation",at,size,[.43,.42,.36],0,"foundation",vec(record.rotation))
			plan.records.back().building.floor_y=record.building.floor_y
	plan.version=7
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
	var cylinder := CylinderMesh.new(); cylinder.top_radius=.5; cylinder.bottom_radius=.5; cylinder.height=1; cylinder.radial_segments=16; cylinder.material=material
	var surface := SurfaceTool.new(); surface.append_from(cylinder,0,Transform3D(Basis.from_scale(size),Vector3.ZERO)); surface.set_material(material)
	return surface.commit()
