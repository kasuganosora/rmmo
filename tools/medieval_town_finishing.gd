extends RefCounted
## Content recipe; all edits are submitted through existing 3D editor operations.
const Ground=preload("res://tools/medieval_town_ground_materials.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const STONE="pack:default:paving/outdoor_flagstone/material"

static func simplified(polygon: PackedVector2Array) -> Array:
	var points: Array=Array(polygon)
	var changed:=true
	while changed and points.size()>4:
		changed=false
		for i in points.size():
			var p: Vector2=points[i]
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p,points[(i-1+points.size())%points.size()],points[(i+1)%points.size()]))<.3:
				points.remove_at(i); changed=true; break
	return points.map(func(p):return [p.x,p.y])

static func requests(doc) -> Dictionary:
	var graph: Dictionary=doc.map_meta.editor_layout.roads
	var audit:=Ground.City.analyze(graph)
	if not audit.ok: return audit
	var segments: Array=[]; var regions: Array=[]
	for e in graph.edges:
		var path: Array=audit.paths[e.id]; var line:=PackedVector2Array()
		var dirt: bool=e.kind!="bridge" and e.name in Ground.DIRT_ROUTES
		for p in path: line.append(Vector2(p.x,p.z))
		for i in line.size()-1:
			segments.append({"a":line[i],"b":line[i+1],"dirt":dirt,"half_width":float(e.width_start)*.5})
		if not dirt: continue
		# Add worn soil at the shoulders, also beneath the last paved approach.
		# World polygons extend across terrain patches; no feather is restarted at a seam.
		for polygon in Geometry2D.offset_polyline(line,float(e.width_start)*.5+1.5,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND):
			var points:=simplified(polygon); var rect:=Rect2(polygon[0],Vector2.ZERO)
			for p in polygon: rect=rect.expand(p)
			for r in doc.records:
				if not r.has("terrain_mesh"): continue
				var patch:=Rect2(Vector2(r.position[0]-r.size[0]*.5,r.position[2]-r.size[2]*.5),Vector2(r.size[0],r.size[2]))
				if not patch.intersects(rect.grow(3)): continue
				regions.append({"id":"verge_"+str(e.id),"terrain_ids":[r.uuid],"polygon":points,"material_id":Ground.DIRT,"feather":4.,"opacity":.85})
	var paints: Array=[]; var changes:={}
	for r in doc.records:
		if not r.has("road_mesh"): continue
		# Avoid 32m-cell-wide material switches: classify each original editable face.
		# A paved junction keeps an 8m approach, but neighbouring dirt faces can differ.
		var node:=MeshInstance3D.new(); node.mesh=Surface.mesh(r,null)
		var geometry:=Paint.geometry(node); node.free()
		if not geometry.ok: return geometry
		var top: Dictionary=geometry.surfaces[0]
		for face in top.faces:
			var c: Vector3=top.faces[face].center
			var p:=Vector2(c.x+r.position[0],c.z+r.position[2]); var soil:=INF; var stone:=INF
			for s in segments:
				var d:=p.distance_to(Geometry2D.get_closest_point_to_segment(p,s.a,s.b))
				if s.dirt: soil=minf(soil,d-s.half_width)
				else: stone=minf(stone,d-s.half_width)
			var material: String=Ground.DIRT if soil<1. and stone>8. else STONE
			var old: Array=r.get("surface_paint",[]).filter(func(entry):return entry.surface==0 and entry.face==face)
			if not old.is_empty() and str(old[0].material.get("texture_path","")).contains("natural_dirt" if material==Ground.DIRT else "outdoor_flagstone"): continue
			paints.append({"id":r.uuid,"target":{"mesh":".","surface":0,"face":face,"geometry":top.signature},"material_id":material,"mapping":"uv","scale":[.5,.5]})
			changes[r.uuid]=true
	return {"ok":true,"regions":regions,"paints":paints,"changed_roads":changes.keys()}
