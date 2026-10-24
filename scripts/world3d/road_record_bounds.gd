extends RefCounted
## Stream authored points once; do not materialize the full slab/kerb vertex list.
static var enabled:=true
static func measure(record:Dictionary)->Dictionary:
	var p:Array=record.position;var r:Array=record.rotation
	var pose:=Transform3D(Basis.from_euler(Vector3(r[0],r[1],r[2])*PI/180.),Vector3(p[0],p[1],p[2]))
	var road:Dictionary=record.road_mesh;var size:Array=record.size
	var grade:Array=road.get("grade",[0,0]);var terrain:Array=record.get("terrain_grade",[])
	var elevations:Array=road.get("elevations",[]);var drop:=Vector3.UP*float(size[1])
	var bounds:=AABB();var first:=true;var magnitude:=1.
	for polygon_index:int in road.polygons.size():
		var polygon:Array=road.polygons[polygon_index]
		for vertex_index:int in polygon.size():
			var raw:Array=polygon[vertex_index];var x:float=raw[0]*size[0];var z:float=raw[1]*size[2]
			var y:float=elevations[polygon_index][vertex_index] if road.has("elevations") else size[1]*.5+grade[0]*x+grade[1]*z
			if not terrain.is_empty():y+=terrain[0]*x+terrain[1]*z
			var top:=Vector3(x,y,z)
			for local:Vector3 in [top,top-drop]:
				var point:=pose*local
				if not point.is_finite():return {"known":false}
				bounds=AABB(point,Vector3.ZERO) if first else bounds.expand(point);first=false
				magnitude=maxf(magnitude,maxf(absf(point.x),maxf(absf(point.y),absf(point.z))))
	for part:Dictionary in road.get("kerbs",[]):
		for section:Array in [part.a,part.b]:
			for raw:Array in section:
				var point:=pose*Vector3(raw[0],raw[1],raw[2])
				if not point.is_finite():return {"known":false}
				bounds=AABB(point,Vector3.ZERO) if first else bounds.expand(point);first=false
				magnitude=maxf(magnitude,maxf(absf(point.x),maxf(absf(point.y),absf(point.z))))
	bounds=bounds.grow(maxf(.001,magnitude*.000001))
	return {"known":not first and preload("res://scripts/world3d/asset_bounds_manifest.gd")._finite_box(bounds),"bounds":bounds}
