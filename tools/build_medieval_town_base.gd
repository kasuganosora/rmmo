extends SceneTree
## Content authoring recipe. Outputs ordinary editable records, never a flattened image.
const Doc=preload("res://scripts/world3d/world_document.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const Channel=preload("res://scripts/world3d/channel_surface.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const RoadTools=preload("res://scripts/world_editor/road_tools.gd")
const Intersections=preload("res://scripts/world3d/road_intersections.gd")
const Curves=preload("res://tools/medieval_town_road_curves.gd")
const OUT="D:/code/rmmo_runtime/maps/medieval_river_town"
var spec: Dictionary
var river:=PackedVector2Array()
var road_segments: Array=[]
var graph: Dictionary
var doc=Doc.new()
var scale_m:=1.4
var progress: FileAccess

func _init() -> void: call_deferred("run")
func note(message: String) -> void:
	print(message)
	if progress: progress.store_line(message); progress.flush()
func point(p: Array) -> Vector2: return Vector2((float(p[0])-500)*scale_m,(float(p[1])-500)*scale_m)
func fail(message: String) -> void:
	note("FAIL: "+message); quit(1)
func run() -> void:
	spec=JSON.parse_string(FileAccess.get_file_as_string("res://tools/medieval_town_layout.json")); scale_m=float(spec.size_m)/float(spec.reference_pixels)
	DirAccess.make_dir_recursive_absolute(OUT)
	progress=FileAccess.open(OUT.path_join("build_progress.log"),FileAccess.WRITE)
	var analyzed:=make_graph()
	if not analyzed.ok: fail(JSON.stringify(analyzed)); return
	graph=analyzed.graph
	note("GRAPH nodes=%d edges=%d diagnostics=%s"%[graph.nodes.size(),graph.edges.size(),JSON.stringify(analyzed.diagnostics)])
	if not analyzed.diagnostics.is_empty(): fail("Resolve road diagnostics before generating"); return
	if OS.get_cmdline_user_args().has("--graph-only"): quit(0); return
	if FileAccess.file_exists(OUT.path_join("map.gltf")):
		fail("Map already exists; authoring recipe never overwrites an existing user map."); return
	for p in spec.river_left: river.append(point(p))
	var right: Array=spec.river_right.duplicate(); right.reverse()
	for p in right: river.append(point(p))
	var pavement:=Plan.build(graph,Plan.defaults())
	if not pavement.ok: fail(JSON.stringify(pavement)); return
	note("PAVEMENT chunks=%d"%pavement.chunks)
	var by_cell:={}
	for r in pavement.records: by_cell[Vector2i(floori(r.position[0]/32),floori(r.position[2]/32))]=r
	for square in spec.squares:
		var polygon:=PackedVector2Array()
		for p in square[1]: polygon.append(point(p))
		merge_pavement(polygon,by_cell)
	var clipped:=Curves.clip_map_bounds(by_cell.values()); by_cell.clear()
	for r in clipped: by_cell[Vector2i(floori(r.position[0]/32),floori(r.position[2]/32))]=r
	var material:=preload("res://scripts/world_editor/surface_material_library.gd").new().find("pack:default:paving/outdoor_flagstone/material")
	if material.is_empty(): fail("Default cobblestone PBR material is missing"); return
	var painter:=RoadTools.new()
	# Squares join the same slab mesh; detach the recipe so regeneration cannot erase them.
	for r in by_cell.values():
		r.uuid="town_"+r.uuid
		var painted:=painter.paint_default(r,material)
		if not painted.ok: fail("Pavement material: "+JSON.stringify(painted)); return
		r.erase("road_source")
		doc.records.append(r)
	note("PBR road surfaces ready")
	for z in 7:
		for x in 7: add_terrain(x,z)
		note("TERRAIN row %d/7"%(z+1))
	add_water()
	var layout:=City.defaults(); layout.roads=graph
	for bookmark in [["whole_town","全城底图",[0,0,0],1480],["market","中央市场",[-35,0,1.4],250],["east_bridge","中央东桥",[340,0,-154],200],["south_bank","南岸街区",[210,0,400],400]]:
		layout.bookmarks.append({"id":bookmark[0],"name":bookmark[1],"camera":{"projection":"top","center":bookmark[2],"span":bookmark[3],"distance":1000,"yaw":0,"pitch":-60}})
	# Water is a reserved passage for later placement tools; keep all 52 outline vertices.
	var water_polygon: Array=Array(river).map(func(p):return [p.x,p.y])
	if Poly.area(Array(river))<0: water_polygon.reverse()
	layout.zones=[{"id":"river_corridor","name":"河道保留 · 禁止建筑与植被","polygon":water_polygon,"min_y":-20,"max_y":40,"purpose":"reserved_passage"}]
	for square in spec.squares:
		var poly: Array=square[1].map(func(p):var w:=point(p); return [w.x,w.y])
		layout.zones.append({"id":"square_%d"%layout.zones.size(),"name":square[0],"polygon":poly,"min_y":-.5,"max_y":30,"purpose":"reserved_passage"})
	doc.map_meta={"name":spec.name,"map_ref":"user/medieval_river_town","spawn":[-35,1.1,1.4],"editor_layout":layout,"environment":{"preset":"day","sun_rotation":[-55,32,0],"sun_energy":1.0,"ambient_energy":.55,"ambient_color":[.85,.88,.92],"fog_enabled":false,"sky_enabled":false,"weather":"clear","surface_wetness":false,"environment_audio":false},"town_reference":{"size_m":1400,"meters_per_pixel":1.4,"source":spec.reference,"phase":"terrain_roads_water_only","height_note":"Reference contains no measured elevation. Town building areas are level; outskirts gently undulate.","future_wall_pixels":spec.future_wall}}
	doc.map_meta.editor_view={"spawn":[-35,.025,1.4]}
	var smooth_river:=preload("res://tools/medieval_town_river_curves.gd").new(); smooth_river.setup(spec)
	var river_result:=smooth_river.apply(doc)
	if not river_result.ok: fail(JSON.stringify(river_result)); return
	note("CURVED_RIVER "+JSON.stringify(river_result))
	var river_materials:=preload("res://tools/medieval_town_river_materials.gd").apply(doc,true)
	if not river_materials.ok: fail(JSON.stringify(river_materials)); return
	var ground_materials:=preload("res://tools/medieval_town_ground_materials.gd").apply(doc)
	if not ground_materials.ok: fail(JSON.stringify(ground_materials)); return
	var ground_regions:=preload("res://tools/medieval_town_ground_materials.gd").apply_regions(doc)
	if not ground_regions.ok: fail(JSON.stringify(ground_regions)); return
	note("VALIDATION records=%d layout=%s"%[doc.records.size(),str(City.valid(doc.map_meta))])
	if not City.valid(doc.map_meta): fail("Layout metadata validation failed"); return
	var seam_error:=seam_audit()
	if seam_error>.00001: fail("Terrain seams differ: "+str(seam_error)); return
	note("SAVE start")
	var result: int=doc.save(OUT.path_join("map.gltf"))
	if result!=OK: fail("Native save failed: "+str(result)); return
	var reopened=Doc.open_file(OUT.path_join("map.gltf"))
	if reopened==null or reopened.records.size()!=doc.records.size(): fail("Reopen failed"); return
	var report:={"map":OUT.path_join("map.gltf"),"size_m":[1400,1400],"roads":spec.roads.size(),"nodes":graph.nodes.size(),"edges":graph.edges.size(),"terrain_patches":49,"road_chunks":by_cell.size(),"records":doc.records.size(),"seam_error_m":seam_error,"river_water_y":-1.5,"river_bed_y":-4.5,"bridge_crossings":5,"graph_diagnostics":analyzed.diagnostics}
	var file:=FileAccess.open(OUT.path_join("build_report.json"),FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	note("TOWN_BASE_BUILT "+JSON.stringify(report)); quit(0)

func make_graph() -> Dictionary:
	var nodes:={}; var edges:={}; var g:={"nodes":[],"edges":[]}
	for road in spec.roads:
		var previous:=""
		for p in road[2]:
			var at:=point(p); var key:="n_%d_%d"%[p[0],p[1]]
			if not nodes.has(key): nodes[key]={"id":key,"position":[at.x,0,at.y]}
			if not previous.is_empty():
				var pair: Array=[previous,key]; pair.sort(); var id: String=pair[0]+"__"+pair[1]
				if not edges.has(id): edges[id]={"id":"e_"+id.sha256_text().left(16),"name":road[0],"from":previous,"to":key,"kind":road[3] if road.size()>3 else "ground","width_start":road[1],"width_end":road[1]}
				else: edges[id].width_start=maxf(edges[id].width_start,road[1]); edges[id].width_end=edges[id].width_start
				road_segments.append({"a":Vector2(nodes[previous].position[0],nodes[previous].position[2]),"b":at,"width":float(road[1]),"bridge":road.size()>3})
			previous=key
	g.nodes=nodes.values(); g.edges=edges.values()
	var split:=Intersections.split(g)
	if not split.ok: return split
	var fitted:=Curves.fit(split.graph)
	if not fitted.ok: return fitted
	road_segments.clear()
	var audit:=City.analyze(fitted.graph)
	for edge in fitted.graph.edges:
		var samples: Array=audit.paths[edge.id]
		for i in samples.size()-1:
			road_segments.append({"a":Vector2(samples[i].x,samples[i].z),"b":Vector2(samples[i+1].x,samples[i+1].z),"width":float(edge.width_start),"bridge":edge.kind=="bridge"})
	fitted.diagnostics=audit.diagnostics
	return fitted

func signed_river_distance(p: Vector2) -> float:
	var distance:=INF
	for i in river.size(): distance=minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,river[i],river[(i+1)%river.size()])))
	return -distance if Geometry2D.is_point_in_polygon(p,river) else distance
func elevation(p: Vector2) -> float:
	var d:=signed_river_distance(p)
	if d<10: return -4.5+4.5*smoothstep(-14,10,d)
	# 0m town terrace; low rolling land only outside the inhabited core.
	var radial: float=Vector2(p.x/630.0,p.y/620.0).length()
	var h: float=smoothstep(.93,1.18,radial)*(2.5+1.5*sin(p.x*.012)*cos(p.y*.009))
	var road_distance:=INF
	for s in road_segments:
		if s.bridge: continue
		road_distance=minf(road_distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,s.a,s.b))-s.width*.5)
	return h*smoothstep(10,35,road_distance)
func add_terrain(x: int, z: int) -> void:
	var n:=64; var center:=Vector2(-600+x*200,-600+z*200); var heights: Array=[]; var holes: Array=[]
	for iz in n+1:
		for ix in n+1: heights.append(snappedf(elevation(center+Vector2(float(ix)/n-.5,float(iz)/n-.5)*200),.000001))
	holes.resize(n*n); holes.fill(false)
	var r:={"uuid":"town_terrain_%d_%d"%[x,z],"kind":"box","surface_id":"grass","position":[center.x,0,center.y],"rotation":[0,0,0],"size":[200,1,200],"color":[.34,.40,.23],"editor_name":"城镇地形 · %d,%d"%[x,z],"terrain_mesh":{"version":1,"columns":n,"rows":n,"heights":heights,"holes":holes,"floor":-16}}
	doc.records.append(r)

func clipped_chunks(polygon: PackedVector2Array) -> Dictionary:
	var triangles:=Geometry2D.triangulate_polygon(polygon); var result:={}
	for at in range(0,triangles.size(),3):
		var triangle: Array=[polygon[triangles[at]],polygon[triangles[at+1]],polygon[triangles[at+2]]]
		if (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0])<0: triangle.reverse()
		var bounds:=Rect2(triangle[0],Vector2.ZERO)
		for p in triangle: bounds=bounds.expand(p)
		for x in range(maxi(-22,floori(bounds.position.x/32)),mini(21,floori(bounds.end.x/32))+1):
			for z in range(maxi(-22,floori(bounds.position.y/32)),mini(21,floori(bounds.end.y/32))+1):
				var piece:=Plan.intersection(triangle,Poly.rect([maxf(-700,x*32),maxf(-700,z*32),minf(700,(x+1)*32),minf(700,(z+1)*32)]))
				if piece.is_empty(): continue
				var key:=Vector2i(x,z)
				if not result.has(key): result[key]=[]
				result[key].append(piece)
	return result
func merge_pavement(polygon: PackedVector2Array, chunks: Dictionary) -> void:
	var patches:=clipped_chunks(polygon)
	for key in patches:
		var center:=Vector3((key.x+.5)*32,-.075,(key.y+.5)*32)
		if not chunks.has(key): chunks[key]={"uuid":"square_%d_%d"%[key.x,key.y],"kind":"box","surface_id":"road","position":City.xyz(center),"rotation":[0,0,0],"size":[32,.2,32],"color":[.55,.49,.36],"road_mesh":{"polygons":[],"uv_origin":City.xyz(Vector3(center.x,0,center.z))},"editor_name":"市场广场铺面"}
		var r: Dictionary=chunks[key]
		for poly in patches[key]:
			var fragments: Array=[poly]
			for existing in r.road_mesh.polygons:
				var mask: Array=existing.map(func(p):return Vector2(p[0]*32+center.x,p[1]*32+center.z)); var next: Array=[]
				for fragment in fragments: next.append_array(Poly.subtract(fragment,mask))
				fragments=next
			for fragment in fragments:
				var normalized:=Plan.normalized_patch(fragment,center)
				if not normalized.is_empty(): r.road_mesh.polygons.append(normalized)

func add_water() -> void:
	var chunks:=clipped_chunks(river)
	for key in chunks:
		var center:=Vector3((key.x+.5)*32,-1.54,(key.y+.5)*32); var polygons: Array=[]
		for piece in chunks[key]:
			var normalized:=Plan.normalized_patch(piece,center)
			if not normalized.is_empty(): polygons.append(normalized)
		if polygons.is_empty(): continue
		doc.records.append({"uuid":"town_water_%d_%d"%[key.x,key.y],"kind":"box","surface_id":"water","collision":"none","position":City.xyz(center),"rotation":[0,0,0],"size":[32,.08,32],"color":[.095,.26,.32],"channel_mesh":{"polygons":polygons,"uv_origin":City.xyz(center)},"channel_clearance":0,"editor_name":"河道水面 · %d,%d"%[key.x,key.y]})
	note("WATER chunks=%d"%chunks.size())
func seam_audit() -> float:
	var worst:=0.0
	for z in 7:
		for x in 7:
			var a: Dictionary=doc._find("town_terrain_%d_%d"%[x,z]); var h: Array=a.terrain_mesh.heights
			if x<6:
				var b: Array=doc._find("town_terrain_%d_%d"%[x+1,z]).terrain_mesh.heights
				for i in 65: worst=maxf(worst,absf(h[i*65+64]-b[i*65]))
			if z<6:
				var b: Array=doc._find("town_terrain_%d_%d"%[x,z+1]).terrain_mesh.heights
				for i in 65: worst=maxf(worst,absf(h[64*65+i]-b[i]))
	return worst
