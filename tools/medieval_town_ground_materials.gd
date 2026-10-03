extends RefCounted
## Reference-map content recipe. Keep urban paving and bridge crossings intact.
const City=preload("res://scripts/world3d/city_layout.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const DIRT="pack:default:terrain/natural_dirt/material"
const GRASS="pack:default:terrain/outdoor_short_grass/material"
const MOSS="pack:default:terrain/mossy_grass/material"
const DIRT_ROUTES=["北郊小路","西北门外路","西南门外路","东北郊小路","东北田间岔路","东南田间路","南郊横巷"]
static func apply(doc) -> Dictionary:
	var graph: Dictionary=doc.map_meta.editor_layout.roads; var audit:=City.analyze(graph)
	if not audit.ok: return audit
	var paths: Array=[]
	for e in graph.edges:
		var points: Array=audit.paths[e.id]
		for i in points.size()-1: paths.append({"a":Vector2(points[i].x,points[i].z),"b":Vector2(points[i+1].x,points[i+1].z),"dirt":e.kind!="bridge" and e.name in DIRT_ROUTES})
	var library=preload("res://scripts/world_editor/surface_material_library.gd").new()
	var material: Dictionary=library.find(DIRT)
	if material.is_empty(): return {"ok":false,"error":"Missing country-path dirt material"}
	var painter=preload("res://scripts/world_editor/road_tools.gd").new(); var ids: Array=[]
	for r in doc.records:
		if not r.has("road_mesh"): continue
		# Leave an entire junction paved when any polygon lies near an urban road.
		# This avoids changing a crossing just because its 32m chunk centre is rural.
		var chosen:=true
		for poly in Surface.local_polygons(r):
			var p:=Vector2.ZERO
			for v in poly: p+=Vector2(v.x+r.position[0],v.z+r.position[2])
			p/=poly.size(); var soil:=INF; var stone:=INF
			for s in paths:
				var distance:=p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p,s.a,s.b))
				if s.dirt: soil=minf(soil,distance)
				else: stone=minf(stone,distance)
			if soil>144 or stone<225 or stone<soil: chosen=false; break
		if not chosen: continue
		if r.get("editor_locked",false) or r.get("editor_hidden",false): return {"ok":false,"error":"Show and unlock rural path before authoring"}
		var result:=painter.paint_default(r,material)
		if not result.ok: return result
		ids.append(r.uuid)
	doc.map_meta.town_reference.ground_materials={"dirt_routes":DIRT_ROUTES,"dirt_road_ids":ids,"material":DIRT,"note":"Courtyards and fields use editable ground_regions in the layout recipe; surfaces obscured by buildings are not inferred."}
	return {"ok":true,"dirt_chunks":ids.size(),"ids":ids}

static func region_requests(doc) -> Array:
	var spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/medieval_town_layout.json"))
	var ids: Array=[]
	for record in doc.records:
		if record.has("terrain_mesh"): ids.append(record.uuid)
	var result: Array=[]
	for region in spec.ground_regions:
		var polygon: Array=[]
		for p in region.polygon: polygon.append([(p[0]-500.)*1.4,(p[1]-500.)*1.4])
		result.append({"id":region.id,"terrain_ids":ids,"polygon":polygon,"material_id":MOSS if region.material=="moss" else DIRT,"feather":region.feather,"opacity":region.opacity})
	return result

static func apply_regions(doc) -> Dictionary:
	var library=preload("res://scripts/world_editor/surface_material_library.gd").new()
	var records: Array=doc.records.duplicate(true)
	var requests:=region_requests(doc)
	for request in requests:
		var result:=preload("res://scripts/world_editor/terrain_region_tools.gd").prepare(records,request,library,func(r):return not r.get("editor_locked",false) and not r.get("editor_hidden",false))
		if not result.ok: return result
		for r in result.records:
			for i in records.size():
				if records[i].uuid==r.uuid: records[i]=r; break
	doc.records=records
	return {"ok":true,"regions":requests.size()}
