extends RefCounted
const Data=preload("res://scripts/world3d/city_layout.gd")
const Plan=preload("res://scripts/world3d/fortification_plan.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Bridge=preload("res://scripts/world_editor/bridge_tools.gd")
static func grade_foundations(doc,args: Dictionary) -> Dictionary:
	var points: Array=args.points.map(func(p):return Vector2(p[0],p[1])); var entrances: Array=[]
	for gate in args.gates:
		if gate.kind=="land": entrances.append({"center":points[int(gate.segment)].lerp(points[(int(gate.segment)+1)%points.size()],gate.t),"radius":gate.width+5})
	var changed: Array=[]; var samples:=0; var maximum:=0.0
	for r in doc.records:
		if not r.has("terrain_mesh"): continue
		var t: Dictionary=r.terrain_mesh; var count:=0; var fields: Array=[]
		for region in r.get("terrain_regions",{}).get("regions",[]):
			if region.has("furrows"): fields.append({"bounds":preload("res://scripts/world3d/terrain_regions.gd").bounds(preload("res://scripts/world3d/terrain_regions.gd").points(region)).grow(5),"height":region.furrows.height})
		for z in int(t.rows)+1:
			for x in int(t.columns)+1:
				var i: int=z*(int(t.columns)+1)+x; var old: float=t.heights[i]*r.size[1]+r.position[1]
				if old<0: continue # Never fill the river or disturb its banks below city level.
				var p:=Vector2(r.position[0]+(float(x)/t.columns-.5)*r.size[0],r.position[2]+(float(z)/t.rows-.5)*r.size[2]); var distance:=INF
				for j in points.size(): distance=minf(distance,Plan.point_distance(p,points[j],points[(j+1)%points.size()])-7)
				for j in args.tower_indices: distance=minf(distance,p.distance_to(points[int(j)])-12)
				for gate in entrances: distance=minf(distance,p.distance_to(gate.center)-gate.radius)
				if distance>=9: continue
				var target:=0.0
				for field in fields:
					if field.bounds.has_point(p-Vector2(r.position[0],r.position[2])): target=minf(target,-field.height-.01)
				var amount:=1.0-smoothstep(0,9,maxf(0,distance)); var height:=lerpf(old,target,amount)
				t.heights[i]=(height-r.position[1])/r.size[1]; maximum=maxf(maximum,old-height); count+=1
		if count:
			changed.append(r.uuid); samples+=count
	return {"terrain_ids":changed,"changed_samples":samples,"maximum_cut_m":maximum}
static func water_zones(doc,args: Dictionary) -> void:
	var poly=preload("res://scripts/world3d/roof_plan.gd")
	var zones: Array=doc.map_meta.editor_layout.zones.duplicate(true)
	for gate in args.gates:
		if gate.kind!="water": continue
		var a:=Vector2(args.points[int(gate.segment)][0],args.points[int(gate.segment)][1]); var b:=Vector2(args.points[(int(gate.segment)+1)%args.points.size()][0],args.points[(int(gate.segment)+1)%args.points.size()][1]); var n:=Vector2(-(b-a).y,(b-a).x).normalized(); var c:=a.lerp(b,gate.t)
		var next: Array=[]
		for zone in zones:
			if not str(zone.id).begins_with("river_corridor_"): next.append(zone); continue
			var polygon: Array=zone.polygon.map(func(v):return Vector2(v[0],v[1])); var mid: Array=poly.clip(poly.clip(polygon,n,-n.dot(c)+4),-n,n.dot(c)+4)
			if mid.is_empty() or poly.area(mid)<1: next.append(zone); continue
			var pieces: Array=[poly.clip(polygon,n,-n.dot(c)-4),mid,poly.clip(polygon,-n,n.dot(c)-4)]
			for j in 3:
				if pieces[j].is_empty() or poly.area(pieces[j])<1: continue
				var clean: Array=[]
				for v in pieces[j]:
					if clean.is_empty() or clean[-1].distance_to(v)>=.06: clean.append(v)
				if clean.size()>2 and clean[0].distance_to(clean[-1])<.06: clean.pop_back()
				var revised: Dictionary=zone.duplicate(true); revised.id=zone.id+"_w%d"%j; revised.polygon=clean.map(func(v):return [v.x,v.y])
				if j==1: revised.max_y=args.base_height+gate.height-.05; revised.name="水关下方通航保留空间"
				next.append(revised)
		zones=next
	doc.map_meta.editor_layout.zones=zones
static func correct_approaches(doc) -> Dictionary:
	var old: Dictionary=doc.map_meta.editor_layout.roads.duplicate(true); var graph:=old.duplicate(true)
	# Existing approximate roads ran longitudinally through the correctly traced
	# wall. Keep topology; move these five junctions onto the city side.
	var positions:={"n_753_107":[730,115],"n_796_156":[782,168],"n_826_214":[810,221],"n_194_858":[210,842],"n_229_908":[255,897]}
	var deltas:={}; var changed: Array=[]
	for n in graph.nodes:
		if positions.has(n.id):
			var v:=Vector3((positions[n.id][0]-500)*1.4,0,(positions[n.id][1]-500)*1.4); deltas[n.id]=v-Data.vec(n.position); n.position=Data.xyz(v)
	for e in graph.edges:
		if not deltas.has(e.from) and not deltas.has(e.to): continue
		changed.append(e.id)
		if e.has("controls"):
			e.controls[0]=Data.xyz(Data.vec(e.controls[0])+deltas.get(e.from,Vector3.ZERO)); e.controls[1]=Data.xyz(Data.vec(e.controls[1])+deltas.get(e.to,Vector3.ZERO))
	var areas: Array=[]
	for g in [old,graph]:
		var paths: Dictionary=Data.analyze(g).paths
		for id in changed:
			var box:=Rect2(Vector2(paths[id][0].x,paths[id][0].z),Vector2.ZERO)
			for p in paths[id]: box=box.expand(Vector2(p.x,p.z))
			areas.append(box.grow(12))
	var old_cells:={}; var touched: Array=[]
	for r in doc.records:
		if r.has("road_mesh"): old_cells[Vector2i(floori(r.position[0]/32),floori(r.position[2]/32))]=r
	var binding:=preload("res://scripts/world3d/road_bridges.gd").resolve(doc.map_meta.editor_layout)
	var plan:=preload("res://scripts/world3d/road_plan.gd").build(graph,preload("res://scripts/world3d/road_plan.gd").defaults(),binding.portals)
	if not plan.ok: return plan
	var replacements: Array=[]; var painter:=preload("res://scripts/world_editor/road_tools.gd").new()
	for key in old_cells:
		if not areas.any(func(a):return a.intersects(Rect2(Vector2(key)*32,Vector2(32,32)))): continue
		var r: Dictionary=old_cells[key]
		if r.get("editor_locked",false) or r.get("editor_hidden",false) or r.has("event") or r.has("event_template"): return Data.fail("城门接路含受保护的路面")
		touched.append(r.uuid)
	for r in plan.records:
		var key:=Vector2i(floori(r.position[0]/32),floori(r.position[2]/32))
		if not areas.any(func(a):return a.intersects(Rect2(Vector2(key)*32,Vector2(32,32)))): continue
		var nearest: Dictionary=old_cells.get(key,{})
		if nearest.is_empty():
			var distance:=INF
			for previous in old_cells.values():
				var d:=Data.vec(previous.position).distance_squared_to(Data.vec(r.position))
				if d<distance: distance=d; nearest=previous
		r.uuid=old_cells[key].uuid if old_cells.has(key) else "town_"+r.uuid; r.erase("road_source")
		var paint:=painter.paint_default(r,nearest.surface_paint[0].material)
		if not paint.ok: return paint
		replacements.append(r)
	doc.records=doc.records.filter(func(r):return r.uuid not in touched)+replacements
	doc.map_meta.editor_layout.roads=graph
	return {"ok":true,"changed_edges":changed,"replaced_road_ids":touched,"new_road_ids":replacements.map(func(r):return r.uuid),"nodes":positions}
static func requests(doc) -> Dictionary:
	var trace: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/medieval_town_wall_trace.json"))
	var p: Array=trace.pixels.map(func(v):return Vector2((v[0]-500)*1.4,(v[1]-500)*1.4))
	var graph: Dictionary=doc.map_meta.editor_layout.roads; var analysis:=Data.analyze(graph)
	var gates: Array=[]
	for i in p.size():
		var a: Vector2=p[i]; var b: Vector2=p[(i+1)%p.size()]; var length_: float=a.distance_to(b); var tangent: Vector2=(b-a).normalized()
		for edge in graph.edges:
			var path: Array=analysis.paths[edge.id]
			for j in path.size()-1:
				var c:=Vector2(path[j].x,path[j].z); var d:=Vector2(path[j+1].x,path[j+1].z)
				var hit: Variant=Geometry2D.segment_intersects_segment(a,b,c,d)
				if hit==null: continue
				var crossing:=maxf(.1,absf(tangent.cross((d-c).normalized())))
				var width: float=maxf(edge.width_start,edge.width_end)/crossing+3.5*absf(tangent.dot((d-c).normalized()))/crossing+8
				if gates.any(func(g):return g.segment==i and absf(g.t-hit.distance_to(a)/length_)<.02): continue
				gates.append({"id":"land_gate_%d"%gates.size(),"kind":"land","segment":i,"t":hit.distance_to(a)/length_,"width":width,"height":5.0,"open":1.0})
	# River mouths: derive the open span from actual water/bank terrain, not the
	# illustration's river (the user subsequently requested a constant 40m river).
	var terrain: Array=doc.records.filter(func(r):return r.has("terrain_mesh"))
	for i in p.size():
		var a: Vector2=p[i]; var b: Vector2=p[(i+1)%p.size()]; var length_: float=a.distance_to(b); var lo:=INF; var hi:=-INF
		for j in ceili(length_)+1:
			var t: float=minf(j/length_,1); var at: Vector2=a.lerp(b,t)
			if Bridge.ground_height(terrain,Vector3(at.x,0,at.y))<-.3: lo=minf(lo,t*length_); hi=maxf(hi,t*length_)
		if not is_finite(lo): continue
		gates.append({"id":"water_gate_%d"%i,"kind":"water","segment":i,"t":(lo+hi)*.5/length_,"width":hi-lo+10,"height":5.0,"open":1.0})
	var towers: Array=[]; var last:=Vector2(INF,INF)
	for i in p.size():
		if p[i].distance_to(last)<110 or not towers.is_empty() and p[i].distance_to(p[towers[0]])<110: continue
		if gates.any(func(g):return p[i].distance_to(p[int(g.segment)].lerp(p[(int(g.segment)+1)%p.size()],g.t))<g.width*.5+20): continue
		towers.append(i); last=p[i]
	var args:={"id":"reference_town_wall","name":"参考城镇 · 不规则城防轮廓","shape":"path","points":p.map(func(v):return [v.x,v.y]),"tower_indices":towers,"tower_layout":"automatic","closed":true,"base_height":0.0,"height":7.5,"thickness":3.5,"foundation":1.0,"terrain_foundation":true,"wall_access":true,"arrow_slits":true,"gates":gates}
	return args
