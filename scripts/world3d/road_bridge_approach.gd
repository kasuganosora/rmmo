extends RefCounted
## A bridge's broad bounds include the open space between its wing walls.
## Refine only that outside-deck approach space against frozen collision faces;
## the bridge body keeps the ordinary conservative occupancy protection.
const City=preload("res://scripts/world3d/city_layout.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const EPS:=.005

static func clip(poly:Array,normal:Vector3,constant:float)->Array:
	var result:Array=[]
	for i in poly.size():
		var a:Vector3=poly[i];var b:Vector3=poly[(i+1)%poly.size()]
		var da:=normal.dot(a)+constant;var db:=normal.dot(b)+constant
		if da>=0:result.append(a)
		if (da>=0)!=(db>=0):result.append(a.lerp(b,da/(da-db)))
	return result

static func collision_faces(bridge:Dictionary)->Dictionary:
	if not bridge.has("house_prefab"):return {"known":false}
	var data:=Frozen.decode(bridge.house_prefab)
	# StructurePrefab.bridge packs one already bridge-local mesh at path [0].
	# Unknown frozen layouts must keep conservative bounds protection.
	if data.is_empty() or data.entries.size()!=1 or data.entries[0][0]!=[0]:return {"known":false}
	# Use the full frozen collision source, never a rendering LOD or a newly
	# regenerated recipe which could differ from the saved authoring model.
	var source:Dictionary=data.meshes[data.entries[0][1][1]]
	var surfaces:Array=source.surfaces
	if source.box_size!=Vector3.ZERO:
		var box:=BoxMesh.new();box.size=source.box_size
		surfaces=[preload("res://scripts/world3d/ground_cpu_mesh.gd").primitive_arrays(box,0)]
	var pose:=Transform3D(Basis.from_euler(City.vec(bridge.rotation)*PI/180.).scaled(City.vec(bridge.size)),City.vec(bridge.position))
	var half:float=bridge.bridge_mesh.length*.5;var faces:Array=[]
	for surface:Array in surfaces:
		var vertices:PackedVector3Array=surface[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=surface[Mesh.ARRAY_INDEX] if surface[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for index in vertices.size():indices.append(index)
		for at in range(0,indices.size(),3):
			var a:Vector3=vertices[indices[at]];var b:Vector3=vertices[indices[at+1]];var c:Vector3=vertices[indices[at+2]]
			if minf(a.x,minf(b.x,c.x))>-half+EPS and maxf(a.x,maxf(b.x,c.x))<half-EPS:continue
			a=pose*a;b=pose*b;c=pose*c
			faces.append({"points":[a,b,c],"bounds":AABB(a,Vector3.ZERO).expand(b).expand(c).grow(.0001)})
	return {"known":true,"faces":faces}

static func intersects(road:Dictionary,bridge:Dictionary,occupancy:Array,bridge_shape:Dictionary,cache:Dictionary)->bool:
	if not bridge.has("bridge_mesh") or absf(bridge.rotation[0])+absf(bridge.rotation[2])>.0001:return true
	var pose:=Transform3D(Basis.from_euler(City.vec(bridge.rotation)*PI/180.).scaled(City.vec(bridge.size)),City.vec(bridge.position))
	var inverse:=pose.affine_inverse();var half:float=bridge.bridge_mesh.length*.5
	var road_pose:=Transform3D(Basis.from_euler(City.vec(road.rotation)*PI/180.),City.vec(road.position))
	var polygons:=Road.local_polygons(road);var patches:Array=[]
	for index in polygons.size():
		if not Foot.overlaps(occupancy[index],bridge_shape):continue
		var top:Array=Array(polygons[index]).map(func(p):return road_pose*p)
		var low:=INF;var high:=-INF
		for point:Vector3 in top:
			var local:Vector3=inverse*point;low=minf(low,local.x);high=maxf(high,local.x)
		if low<half-EPS and high>-half+EPS:return true
		var planes:Array=[]
		for i in top.size():
			var a:Vector3=top[i];var b:Vector3=top[(i+1)%top.size()]
			var normal:=Vector3(-(b.z-a.z),0,b.x-a.x).normalized()
			planes.append([normal,-normal.dot(a)-EPS])
		var plane:=Plane(top[0],top[1],top[2]);var normal:Vector3=plane.normal;var distance:float=plane.d
		if normal.y<0:normal=-normal;distance=-distance
		if normal.y<.0001:return true
		planes.append([normal,-distance+(road.size[1]-EPS)*normal.y])
		planes.append([-normal,distance+(road.get("road_clearance",3.)-EPS)*normal.y])
		patches.append({"planes":planes,"bounds":occupancy[index].bounds})
	if patches.is_empty():return false
	# Cache scope is one immutable prepare operation, not persistent map state.
	if not cache.has(bridge.uuid):cache[bridge.uuid]=collision_faces(bridge)
	var geometry:Dictionary=cache[bridge.uuid]
	if not geometry.known:return true
	for face:Dictionary in geometry.faces:
		for patch:Dictionary in patches:
			if not face.bounds.intersects(patch.bounds):continue
			var cut:Array=face.points
			for plane:Array in patch.planes:
				cut=clip(cut,plane[0],plane[1])
				if cut.size()<3:break
			if cut.size()<3:continue
			var area:=0.
			for i in range(1,cut.size()-1):area+=(cut[i]-cut[0]).cross(cut[i+1]-cut[0]).length()*.5
			if area>.0000001:return true
	return false
