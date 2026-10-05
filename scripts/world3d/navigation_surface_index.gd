extends RefCounted
## Conservative support certificates, not a replacement for exact pathfinding.
## Triangle fans match NavigationServer's polygon nearest-point queries.
const CELL:=16.0
var vertices:=PackedVector3Array()
var triangles:=PackedInt32Array()
var normals:=PackedVector3Array()
var cells:Dictionary={}

static func build(mesh:NavigationMesh)->RefCounted:
	var result=load("res://scripts/world3d/navigation_surface_index.gd").new()
	result.vertices=mesh.get_vertices()
	for p in mesh.get_polygon_count():
		var polygon:=mesh.get_polygon(p)
		if polygon.size()<3:continue
		var origin:Vector3=result.vertices[polygon[0]]
		var plane_normal:Vector3=(result.vertices[polygon[1]]-origin).cross(result.vertices[polygon[2]]-origin).normalized()
		if plane_normal.length_squared()<.9:continue
		# Godot may normalize non-planar input polygons when publishing regions.
		# Certify only coplanar polygons; keep engine queries for warped faces.
		var planar:=true
		for vertex:int in polygon:
			if absf(plane_normal.dot(result.vertices[vertex]-origin))>.000001:planar=false;break
		if not planar:continue
		for j in range(2,polygon.size()):
			var a:Vector3=result.vertices[polygon[0]];var b:Vector3=result.vertices[polygon[j-1]];var c:Vector3=result.vertices[polygon[j]]
			var normal:Vector3=(b-a).cross(c-a)
			if normal.length_squared()<1e-12:continue
			var id:int=result.normals.size();result.normals.append(normal.normalized())
			result.triangles.append_array(PackedInt32Array([polygon[0],polygon[j-1],polygon[j]]))
			var low:Vector3=a.min(b).min(c);var high:Vector3=a.max(b).max(c)
			for x in range(floori(low.x/CELL),floori(high.x/CELL)+1):
				for z in range(floori(low.z/CELL),floori(high.z/CELL)+1):
					var key:=Vector2i(x,z)
					if not result.cells.has(key):result.cells[key]=[]
					result.cells[key].append(id)
	return result

func support(point:Vector3,radius:float)->Vector3:
	# Only accept an actual point on an actual triangle within the smaller
	# tolerance sphere. A globally closer point must then satisfy both original
	# horizontal/vertical limits too. No certificate => use the engine query.
	if radius<=0 or not point.is_finite():return Vector3.INF
	for id:int in cells.get(Vector2i(floori(point.x/CELL),floori(point.z/CELL)),[]):
		var a:=vertices[triangles[id*3]];var normal:=normals[id]
		var distance:=normal.dot(point-a)
		if absf(distance)>radius*.99999:continue
		var at:=point-normal*distance
		var b:=vertices[triangles[id*3+1]];var c:=vertices[triangles[id*3+2]]
		if (b-a).cross(at-a).dot(normal)<0 or (c-b).cross(at-b).dot(normal)<0 or (a-c).cross(at-c).dot(normal)<0:continue
		return at
	return Vector3.INF
