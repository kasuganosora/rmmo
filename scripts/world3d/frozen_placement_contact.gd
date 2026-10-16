extends RefCounted
## A frozen batch's bounds are only a broad phase. Authoring keeps the new
## building's occupied volume, but tests it against the saved static geometry.
const Frozen=preload("res://scripts/world3d/frozen_road_contact.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Clip=preload("res://scripts/world3d/road_bridge_approach.gd")
const Solid=preload("res://scripts/world3d/asset_road_contact.gd")
static func intersects(record:Dictionary,occupancy:Array,broad:Dictionary,cache:Dictionary)->bool:
	# Existing generated buildings reserve their whole occupied interiors, not
	# just wall surfaces. Do not permit nesting a new house inside an empty hall.
	if record.has("building"):return true
	var data:Dictionary=Frozen.geometry(record,cache)
	if not data.get("known",false):return true
	for shape:Dictionary in occupancy:
		if not Foot.overlaps(shape,broad):continue
		var polygon:PackedVector2Array=shape.polygon
		var count:=polygon.size()-1 if polygon.size()>1 and polygon[0]==polygon[-1] else polygon.size()
		if count<3:return true
		var center:=Vector3.ZERO
		for i in count:center+=Vector3(polygon[i].x,0,polygon[i].y)
		center/=count;center.y=(shape.bounds.position.y+shape.bounds.end.y)*.5
		var planes:Array=[]
		for i in count:
			var a:=Vector3(polygon[i].x,0,polygon[i].y);var j:=(i+1)%count
			var b:=Vector3(polygon[j].x,0,polygon[j].y);var edge:=b-a
			if edge.length_squared()<1e-12:continue
			var n:=Vector3(-edge.z,0,edge.x).normalized()
			if n.dot(center-a)<0:n=-n
			planes.append([n,-n.dot(a)-.005])
		# Match Foot.overlaps' existing 1 cm vertical contact tolerance.
		planes.append([Vector3.UP,-shape.bounds.position.y-.01])
		planes.append([Vector3.DOWN,shape.bounds.end.y-.01])
		for face:Dictionary in data.faces:
			if not face.bounds.intersects(shape.bounds):continue
			var cut:Array=face.points
			for plane:Array in planes:
				cut=Clip.clip(cut,plane[0],plane[1])
				if cut.size()<3:break
			if cut.size()<3:continue
			var area:=0.
			for i in range(1,cut.size()-1):area+=(cut[i]-cut[0]).cross(cut[i+1]-cut[0]).length()*.5
			if area>1e-7:return true
		# A new occupied volume entirely enclosed by a wall/solid still blocks,
		# even when none of the outer frozen triangles crosses its boundary.
		for solid:Array in data.solids:
			if Solid.inside(center,solid):return true
	return false
