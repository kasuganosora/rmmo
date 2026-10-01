extends RefCounted
## Geometry primitives shared by versioned building layouts.
const WALL := .2
const SLAB := .22

static func vec(v: Array) -> Vector3: return Vector3(v[0],v[1],v[2])
static func arr(v: Vector3) -> Array: return [v.x,v.y,v.z]

static func box(plan: Dictionary, key: String, position: Vector3, size: Vector3, color: Array, floor_: int, role: String, rotation := Vector3.ZERO) -> void:
	plan.records.append({"uuid":key.replace("/","_"),"kind":"box","surface_id":"ground" if role=="floor" else "block","position":arr(position),"size":arr(size),"rotation":arr(rotation),"color":color.duplicate(),"editor_name":key,"building":{"part":key,"floor":floor_,"role":role,"floor_y":0.0}})

static func slab(plan: Dictionary, key: String, x0: float, x1: float, z0: float, z1: float, y: float, color: Array, floor_: int) -> void:
	if x1-x0>.001 and z1-z0>.001: box(plan,key,Vector3((x0+x1)/2,y-SLAB/2,(z0+z1)/2),Vector3(x1-x0,SLAB,z1-z0),color,floor_,"floor")

static func wall(plan: Dictionary, key: String, axis: String, fixed: float, start: float, end: float, y: float, height: float, openings: Array, colors: Dictionary, floor_: int) -> void:
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
		for side in [-1,1]: wall_box(plan,prefix+"/jamb%d"%side,axis,fixed,o.u+side*(o.width/2+.035),y+o.bottom+o.height/2,.07,o.height+.14,WALL+.07,colors.trim,floor_,"frame")
		wall_box(plan,prefix+"/head",axis,fixed,o.u,y+o.bottom+o.height+.035,o.width+.14,.07,WALL+.07,colors.trim,floor_,"frame")
		if o.type=="window":
			wall_box(plan,prefix+"/sill",axis,fixed,o.u,y+o.bottom-.035,o.width+.14,.07,WALL+.14,colors.trim,floor_,"frame")
			wall_box(plan,prefix+"/glass",axis,fixed,o.u,y+o.bottom+o.height/2,o.width,o.height,.025,colors.glass,floor_,"window")
			wall_box(plan,prefix+"/mullion",axis,fixed,o.u,y+o.bottom+o.height/2,.055,o.height,.05,colors.trim,floor_,"frame")

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
