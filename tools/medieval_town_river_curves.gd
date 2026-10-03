extends RefCounted
## The reference river is monotone north-to-south. Shape-preserving cubic x(z)
## gives both banks continuous tangents without overshooting their traced bends.
const City=preload("res://scripts/world3d/city_layout.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Channel=preload("res://scripts/world3d/channel_surface.gd")
const Zones=preload("res://scripts/world3d/planning_zones.gd")
var left: Array=[]
var right: Array=[]
var sampled_left:=PackedVector2Array()
var sampled_right:=PackedVector2Array()
var original:=PackedVector2Array()
var dry_bank_width:=10.0
var ribbon: Dictionary={}
const STEP:=2.0

func setup(spec: Dictionary) -> void:
	sampled_left.clear(); sampled_right.clear()
	dry_bank_width=float(spec.get("river_dry_bank_width",10.0))
	var scale_m: float=spec.size_m/spec.reference_pixels
	left=spec.river_left.map(func(p):return Vector2(p[0]-500,p[1]-500)*scale_m)
	right=spec.river_right.map(func(p):return Vector2(p[0]-500,p[1]-500)*scale_m)
	original=PackedVector2Array(left); var reverse: Array=right.duplicate(); reverse.reverse(); original.append_array(PackedVector2Array(reverse))
	ribbon={}
	if spec.has("river_centerline"):
		var recipe: Dictionary=spec.river_centerline
		var anchors: Array=recipe.points.map(func(p):return Vector2(p[0]-500.,p[1]-500.)*scale_m)
		ribbon=preload("res://tools/medieval_town_river_ribbon.gd").build(anchors,float(recipe.width_m))
		if not ribbon.ok: push_error(str(ribbon)); return
		left=ribbon.left; right=ribbon.right
	for i in 701:
		var z: float=-700+i*STEP
		if ribbon.is_empty():
			sampled_left.append(Vector2(x_at(left,z),z)); sampled_right.append(Vector2(x_at(right,z),z))
		else:
			sampled_left.append(Vector2(preload("res://tools/medieval_town_river_ribbon.gd").bank_x(left,z),z))
			sampled_right.append(Vector2(preload("res://tools/medieval_town_river_ribbon.gd").bank_x(right,z),z))

static func slope(points: Array, i: int) -> float:
	if i==0: return (points[1].x-points[0].x)/(points[1].y-points[0].y)
	if i==points.size()-1: return (points[i].x-points[i-1].x)/(points[i].y-points[i-1].y)
	var h0: float=points[i].y-points[i-1].y; var h1: float=points[i+1].y-points[i].y
	var a: float=(points[i].x-points[i-1].x)/h0; var b: float=(points[i+1].x-points[i].x)/h1
	if a*b<=0: return 0
	var w0:=2*h1+h0; var w1:=h1+2*h0
	return (w0+w1)/(w0/a+w1/b)

static func x_at(points: Array, z: float) -> float:
	for i in points.size()-1:
		if z>points[i+1].y: continue
		var a: Vector2=points[i]; var b: Vector2=points[i+1]; var h:=b.y-a.y; var t:=clampf((z-a.y)/h,0,1)
		return (2*t*t*t-3*t*t+1)*a.x+(t*t*t-2*t*t+t)*h*slope(points,i)+(-2*t*t*t+3*t*t)*b.x+(t*t*t-t*t)*h*slope(points,i+1)
	return points[-1].x

func signed_distance(p: Vector2) -> float:
	var at:=clampi(floori((p.y+700)/STEP),0,699); var distance:=40.0
	for points in [sampled_left,sampled_right]:
		for i in range(maxi(0,at-21),mini(700,at+22)):
			distance=minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,points[i],points[i+1])))
	var t:=clampf((p.y-sampled_left[at].y)/STEP,0,1)
	var inside: bool=p.x>=lerpf(sampled_left[at].x,sampled_left[at+1].x,t) and p.x<=lerpf(sampled_right[at].x,sampled_right[at+1].x,t)
	return -distance if inside else distance

func old_distance(p: Vector2) -> float:
	var distance:=INF
	for i in original.size(): distance=minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,original[i],original[(i+1)%original.size()])))
	return -distance if Geometry2D.is_point_in_polygon(p,original) else distance

static func height_at(distance: float, dry_width: float=10.0) -> float:
	# Use the same nonzero 1:4 slope on both sides of the waterline. A flat
	# smoothstep tangent there amplifies tiny heightfield interpolation errors
	# into metre-wide scallops in the visible shoreline.
	if distance<0:
		var t:=clampf((distance+14)/14,0,1)
		return -4.5+3*(3*t*t-2*t*t*t)+3.5*(t*t*t-t*t)
	var t:=clampf(distance/dry_width,0,1)
	return -1.5+1.5*(3*t*t-2*t*t*t)+(.25*dry_width)*(t*t*t-2*t*t+t)

func apply(doc, previous: RefCounted=null) -> Dictionary:
	if sampled_left.size()!=701 or sampled_right.size()!=701: return City.fail("Invalid or incomplete river curve; no records changed")
	if doc.map_meta.get("town_reference",{}).has("river_curve") and previous==null: return City.fail("River already curved; provide its previous trace to revise the corridor")
	if previous!=null and doc.map_meta.get("town_reference",{}).get("river_curve",{}).get("trace_revision",1)!=(1 if ribbon.is_empty() else 2): return City.fail("Town shoreline revision already applied or has an unexpected source")
	var changed_vertices:=0; var changed_tiles:=0; var cells:={}; var old_water: Array=doc.records.filter(func(r):return r.has("channel_mesh") and r.surface_id=="water")
	if old_water.is_empty(): return City.fail("No existing river material to preserve")
	if old_water.any(func(r):return r.get("editor_locked",false) or r.get("editor_hidden",false)): return City.fail("Show and unlock water before river authoring")
	if doc.map_meta.editor_layout.zones.any(func(z):return str(z.id).begins_with("river_corridor") and (z.get("locked",false) or z.get("hidden",false))): return City.fail("Show and unlock river reservation bands")
	var material: Dictionary=old_water[0].surface_paint[0].material.duplicate(true) if old_water[0].has("surface_paint") else preload("res://scripts/world_editor/surface_material_library.gd").new().find("pack:default:water/river_ripples/material")
	if material.is_empty(): return City.fail("River material dependency is missing")
	var road_segments: Array=[]
	if previous!=null:
		var graph: Dictionary=doc.map_meta.editor_layout.roads; var analyzed:=City.analyze(graph)
		if not analyzed.ok: return analyzed
		for e in graph.edges:
			if e.kind=="bridge": continue
			var points: Array=analyzed.paths[e.id]
			for i in points.size()-1: road_segments.append({"a":Vector2(points[i].x,points[i].z),"b":Vector2(points[i+1].x,points[i+1].z),"width":float(e.width_start)})
	for r in doc.records:
		if not r.has("terrain_mesh"): continue
		if r.get("editor_locked",false) or r.get("editor_hidden",false): return City.fail("Show and unlock terrain before river authoring")
		var changed:=false; var t: Dictionary=r.terrain_mesh
		for iz in int(t.rows)+1:
			for ix in int(t.columns)+1:
				var p:=Vector2(r.position[0]+(float(ix)/t.columns-.5)*r.size[0],r.position[2]+(float(iz)/t.rows-.5)*r.size[2])
				var at:=clampi(roundi((p.y+700)/STEP),0,700)
				var low: float=sampled_left[at].x; var high: float=sampled_right[at].x
				if previous!=null: low=minf(low,previous.sampled_left[at].x); high=maxf(high,previous.sampled_right[at].x)
				if p.x<low-40 or p.x>high+40: continue
				var old: float=previous.signed_distance(p) if previous!=null else old_distance(p); var current:=signed_distance(p)
				if old>10 and current>10: continue
				var old_height: float=-4.5+4.5*smoothstep(-14,10,old) if old<10 else 0.0
				var index: int=iz*(int(t.columns)+1)+ix
				var value:=snappedf(float(t.heights[index])+height_at(current,dry_bank_width)-old_height,.000001)
				if previous!=null:
					# This authored base has no user sculpting/buildings. Restore its
					# old corridor to the same road-aware land function, then excavate
					# the corrected trace; do not leave the obsolete trench behind.
					value=snappedf(height_at(current,dry_bank_width) if current<dry_bank_width else land_height(p,road_segments),.000001)
				if absf(value-t.heights[index])>.000001: t.heights[index]=value; changed_vertices+=1; changed=true
		if changed: changed_tiles+=1
	for i in sampled_left.size()-1:
		# Three metres of water extend beneath the dry bank to hide sub-cell
		# heightfield interpolation gaps; the visible shore comes from the terrain.
		var quad: Array=[sampled_left[i]-Vector2(3,0),sampled_right[i]+Vector2(3,0),sampled_right[i+1]+Vector2(3,0),sampled_left[i+1]-Vector2(3,0)]
		var bounds:=Rect2(quad[0],Vector2.ZERO)
		for p in quad: bounds=bounds.expand(p)
		for x in range(maxi(-22,floori(bounds.position.x/32)),mini(21,floori(bounds.end.x/32))+1):
			for z in range(maxi(-22,floori(bounds.position.y/32)),mini(21,floori(bounds.end.y/32))+1):
				var piece:=Plan.intersection(quad,Poly.rect([maxf(-700,x*32),maxf(-700,z*32),minf(700,(x+1)*32),minf(700,(z+1)*32)]))
				if piece.is_empty(): continue
				var key:=Vector2i(x,z); var center:=Vector3((x+.5)*32,-1.54,(z+.5)*32)
				var normalized:=Plan.normalized_patch(piece,center)
				if normalized.is_empty(): continue
				if not cells.has(key): cells[key]=[]
				cells[key].append(normalized)
	var water: Array=[]
	for key in cells:
		var center:=Vector3((key.x+.5)*32,-1.54,(key.y+.5)*32)
		var r:={"uuid":"town_water_%d_%d"%[key.x,key.y],"kind":"box","surface_id":"water","collision":"none","position":City.xyz(center),"rotation":[0,0,0],"size":[32,.08,32],"color":old_water[0].color.duplicate(),"channel_mesh":{"polygons":cells[key],"uv_origin":City.xyz(center)},"channel_clearance":0,"editor_name":"平滑河道水面 · %d,%d"%[key.x,key.y]}
		var node:=MeshInstance3D.new(); node.mesh=Channel.mesh(r,null); var geometry:=Paint.geometry(node); node.free()
		if not geometry.ok: return geometry
		var surface: Dictionary=geometry.surfaces[0]; var entries: Array=[]
		for face in surface.faces: entries.append({"mesh":".","surface":0,"face":face,"geometry":surface.signature,"material":material.duplicate(true),"mapping":"uv","scale":[.25,.25],"offset":[0,0],"rotation":0.0})
		r.surface_paint=entries
		if old_water[0].has("water_depth_effect"): r.water_depth_effect=old_water[0].water_depth_effect.duplicate(true)
		if not Channel.valid(r) or not Paint.valid(r): return City.fail("Invalid river patch / paint: "+r.uuid)
		water.append(r)
	var zones: Array=[]
	for start in range(0,700,30):
		var end:=mini(start+30,700); var points: Array=[]
		for i in range(start,end+1): points.append([sampled_left[i].x-3,sampled_left[i].y])
		for i in range(end,start-1,-1): points.append([sampled_right[i].x+3,sampled_right[i].y])
		points.reverse()
		zones.append({"id":"river_corridor" if start==0 else "river_corridor_%d"%start,"name":"平滑河道保留区域","polygon":points,"min_y":-20,"max_y":40,"purpose":"reserved_passage"})
	if not Zones.valid(zones): return City.fail("Invalid curved river reservation bands")
	doc.records=doc.records.filter(func(r):return not (r.has("channel_mesh") and r.surface_id=="water"))+water
	doc.map_meta.editor_layout.zones=doc.map_meta.editor_layout.zones.filter(func(z):return not str(z.id).begins_with("river_corridor"))+zones
	doc.map_meta.town_reference.river_curve={"version":1,"method":"shape_preserving_cubic_x_of_z","sample_spacing":STEP,"shore_y":-1.5,"bed_y":-4.5,"water_under_bank":3,"shore_slope":.25,"dry_bank_width":dry_bank_width,"trace_revision":2}
	if not ribbon.is_empty():
		doc.map_meta.town_reference.river_curve.merge({"method":"c2_centerline_normal_offset","width_m":ribbon.width,"minimum_radius_m":ribbon.minimum_radius,"trace_revision":3},true)
	return {"ok":true,"water_chunks":water.size(),"changed_terrain_tiles":changed_tiles,"changed_height_samples":changed_vertices,"river_zones":zones.size(),"bank_samples":sampled_left.size()}

static func land_height(p: Vector2, roads: Array) -> float:
	var radial:=Vector2(p.x/630.,p.y/620.).length()
	var h:=smoothstep(.93,1.18,radial)*(2.5+1.5*sin(p.x*.012)*cos(p.y*.009))
	if h==0.: return 0.
	var distance:=INF
	for s in roads: distance=minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,s.a,s.b))-s.width*.5)
	return h*smoothstep(10,35,distance)
