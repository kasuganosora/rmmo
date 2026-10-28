extends RefCounted
## Operation-local narrow phase for static imported assets. Unknown/dynamic
## sources retain the editor's conservative occupancy protection.
const City=preload("res://scripts/world3d/city_layout.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Clip=preload("res://scripts/world3d/road_bridge_approach.gd")
const EPS:=.005
static func collect(node:Node,parent:Transform3D,result:Dictionary)->void:
	if not result.known:return
	if node is AnimationPlayer or node is AnimationTree or node is Skeleton3D or node is CollisionShape3D:
		result.known=false;return
	var pose:Transform3D=parent*node.transform if node is Node3D else parent
	var extras:Dictionary=node.get_meta("extras",{})
	for key in extras:
		if str(key).contains("wind") or str(key).contains("component") or str(key).contains("fixture"):
			result.known=false;return
	if node is MeshInstance3D:
		if node.mesh==null or node.skin!=null or (node.mesh is ArrayMesh and node.mesh.get_blend_shape_count()>0):result.known=false;return
		# Visible nonblocking decorations still occupy editor road clearance.
		# Include both the actual collision source and authored visual mesh.
		var sources:Array=[node.get_meta("collision_solid",node.get_meta("paint_source",node.mesh))]
		if sources[0]!=node.mesh:sources.append(node.mesh)
		for mesh:Mesh in sources:
			var solid:Array=[]
			var points:PackedVector3Array=mesh.get_faces()
			if points.size()%3!=0:result.known=false;return
			for i in range(0,points.size(),3):
				var a:Vector3=pose*points[i];var b:Vector3=pose*points[i+1];var c:Vector3=pose*points[i+2]
				if not a.is_finite() or not b.is_finite() or not c.is_finite():result.known=false;return
				if (b-a).cross(c-a).length_squared()<1e-16:continue
				var face:Dictionary={"points":[a,b,c],"bounds":AABB(a,Vector3.ZERO).expand(b).expand(c).grow(.0001)}
				result.faces.append(face);solid.append(face)
			if not solid.is_empty():result.solids.append(solid)
	for child in node.get_children():collect(child,pose,result)
static func geometry(asset:Dictionary,cache:Dictionary)->Dictionary:
	if asset.get("kind")!="asset" or asset.has("house_prefab") or asset.has("fixture") or asset.has("wind_response") or asset.has("parametric_tree"):return {"known":false}
	var path:String=asset.get("asset_path","")
	var library=preload("res://scripts/world_editor/asset_library.gd")
	if not preload("res://scripts/world3d/map_paths.gd").asset_key_allowed(path):return {"known":false}
	var candidate:Dictionary=library.native_validation_candidate(path)
	if candidate.is_empty():return {"known":false}
	var digest:String=candidate.source_sha
	var key:=City.token([path,candidate.native_product_kind,digest,candidate.payload_sha,candidate.generator,asset.get("position"),asset.get("rotation"),asset.get("size")])
	if cache.has(key):return cache[key]
	var result:={"known":true,"faces":[],"solids":[],"source_sha256":digest}
	var scene=library.instantiate_preview(path,true)
	if scene==null:return {"known":false}
	var size:=City.vec(asset.size)
	if minf(absf(size.x),minf(absf(size.y),absf(size.z)))<.000001:scene.free();return {"known":false}
	collect(scene,Transform3D(Basis.from_euler(City.vec(asset.rotation)*PI/180)*Basis.from_scale(size),City.vec(asset.position)),result)
	scene.free()
	if result.faces.is_empty():result.known=false
	cache[key]=result;return result
static func inside(point:Vector3,faces:Array)->bool:
	# Signed crossings preserve adjacent solids' coincident exit/entry faces.
	# Odd/even after deduplicating distances alone incorrectly makes a merged
	# row of touching blocks solid all the way through an unrelated opening.
	for direction:Vector3 in [Vector3(1,.371,.217).normalized(),Vector3(.193,1,.431).normalized()]:
		var hits:Array=[];var winding:=0
		for face:Dictionary in faces:
			var p:Array=face.points
			var hit:Variant=Geometry3D.ray_intersects_triangle(point,direction,p[0],p[1],p[2])
			if hit==null:continue
			var distance:float=point.distance_to(hit)
			if distance<.00001:return true
			var orientation:=signi(int(signf((p[1]-p[0]).cross(p[2]-p[0]).dot(direction))))
			if orientation==0:continue
			# Same-oriented shared triangle edges count once; opposite faces
			# belong to adjacent solids and must both contribute (cancel).
			if hits.any(func(h):return h[1]==orientation and absf(h[0]-distance)<.00001):continue
			hits.append([distance,orientation]);winding+=orientation
		if winding!=0:
			# Imported decorative shells can be open. A ray crossing an open
			# shell is not evidence that the road is inside a solid. Resolve the
			# ambiguous case using the oriented solid angle of the actual mesh.
			var angle:=0.
			for face:Dictionary in faces:
				var p:Array=face.points
				var a:Vector3=p[0]-point;var b:Vector3=p[1]-point;var c:Vector3=p[2]-point
				var la:=a.length();var lb:=b.length();var lc:=c.length()
				if minf(la,minf(lb,lc))<.00001:return true
				angle+=2.*atan2(a.dot(b.cross(c)),la*lb*lc+a.dot(b)*lc+b.dot(c)*la+c.dot(a)*lb)
			# A closed containing shell subtends 4*pi (orientation independent).
			# The half-winding boundary also covers intersecting closed solids.
			return absf(angle)>TAU
	return false
static func intersects(road:Dictionary,asset:Dictionary,occupancy:Array,shape:Dictionary,cache:Dictionary)->bool:
	return intersects_geometry(road,geometry(asset,cache),occupancy,shape)
static func intersects_geometry(road:Dictionary,data:Dictionary,occupancy:Array,shape:Dictionary)->bool:
	if not data.get("known",false):return true
	var pose:=Transform3D(Basis.from_euler(City.vec(road.rotation)*PI/180),City.vec(road.position))
	var polygons:=Road.local_polygons(road)
	for index in polygons.size():
		if not Foot.overlaps(occupancy[index],shape):continue
		var top:Array=Array(polygons[index]).map(func(p):return pose*p)
		var planes:Array=[];var center:=Vector3.ZERO
		for i in top.size():
			var a:Vector3=top[i];var b:Vector3=top[(i+1)%top.size()];center+=a
			var normal:=Vector3(-(b.z-a.z),0,b.x-a.x).normalized()
			planes.append([normal,-normal.dot(a)-EPS])
		var plane:=Plane(top[0],top[1],top[2]);var normal:=plane.normal;var distance:=plane.d
		if normal.y<0:normal=-normal;distance=-distance
		if normal.y<.0001:return true
		planes.append([normal,-distance+(road.size[1]-EPS)*normal.y])
		planes.append([-normal,distance+(road.get("road_clearance",3.)-EPS)*normal.y])
		for face:Dictionary in data.faces:
			if not face.bounds.intersects(occupancy[index].bounds):continue
			var cut:Array=face.points
			for item:Array in planes:
				cut=Clip.clip(cut,item[0],item[1])
				if cut.size()<3:break
			if cut.size()<3:continue
			var area:=0.
			for i in range(1,cut.size()-1):area+=(cut[i]-cut[0]).cross(cut[i+1]-cut[0]).length()*.5
			if area>.0000001:return true
		center/=top.size()
		for solid:Array in data.solids:
			if inside(center+Vector3.UP*.05,solid):return true
	return false
