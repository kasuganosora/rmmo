extends RefCounted
## Exact cultivation triangles, binned once per operation; never raycast visuals.
const T=preload("res://scripts/world3d/terrain_surface.gd")
var entries:Array=[]
func setup(records:Array)->void:
	for r:Dictionary in records:
		var bins:Dictionary={};var built:=preload("res://scripts/world3d/terrain_furrows.gd").generate(r)
		if not built.ok:continue
		var vertices:PackedVector3Array=built.vertices
		for i in range(0,vertices.size(),3):
			var poly:=[vertices[i],vertices[i+1],vertices[i+2]];var box:=Rect2(Vector2(poly[0].x,poly[0].z),Vector2.ZERO)
			for p:Vector3 in poly:box=box.expand(Vector2(p.x,p.z))
			for z in range(floori(box.position.y),floori(box.end.y)+1):
				for x in range(floori(box.position.x),floori(box.end.x)+1):
					var key:=Vector2i(x,z)
					if not bins.has(key):bins[key]=[]
					bins[key].append(poly)
		entries.append({"record":r,"pose":T.transform(r),"bins":bins})
func sample(world:Vector3)->float:
	var result:=-INF
	for entry:Dictionary in entries:
		var p:Vector3=entry.pose.affine_inverse()*world;var y:=T.sample(entry.record,p)
		if not is_finite(y):continue
		for triangle:Array in entry.bins.get(Vector2i(floori(p.x),floori(p.z)),[]):
			var poly:=PackedVector2Array(triangle.map(func(v):return Vector2(v.x,v.z)))
			if not Geometry2D.is_point_in_polygon(Vector2(p.x,p.z),poly):continue
			var plane:=Plane(triangle[0],triangle[1],triangle[2])
			if absf(plane.normal.y)>.000001:y=maxf(y,(plane.d-plane.normal.x*p.x-plane.normal.z*p.z)/plane.normal.y)
		result=maxf(result,(entry.pose*Vector3(p.x,y,p.z)).y)
	return result
