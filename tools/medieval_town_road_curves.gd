extends RefCounted
## Fit the traced streets without moving any authored or previously split junction.
const City=preload("res://scripts/world3d/city_layout.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")

static func fit(graph: Dictionary) -> Dictionary:
	if graph.nodes.any(func(n):return n.get("locked",false) or n.get("hidden",false)) or graph.edges.any(func(e):return e.get("locked",false) or e.get("hidden",false)):
		return City.fail("Unlock and show the road graph before fitting the town streets")
	var result: Dictionary=graph.duplicate(true); var nodes:={}; var adjacency:={}
	for node in result.nodes: nodes[node.id]=node; adjacency[node.id]=[]
	for edge in result.edges:
		edge.erase("controls")
		adjacency[edge.from].append(edge); adjacency[edge.to].append(edge)
	for edge in result.edges:
		if edge.kind=="bridge": continue
		var a:=City.vec(nodes[edge.from].position); var b:=City.vec(nodes[edge.to].position)
		var chord:=b-a; var length_:=chord.length(); var direction:=chord.normalized()
		var start:=tangent(edge,edge.from,nodes,adjacency)
		var end:=-tangent(edge,edge.to,nodes,adjacency)
		if start.dot(direction)>.999999 and end.dot(direction)>.999999: continue
		edge.controls=[City.xyz(a+start*length_/3),City.xyz(b-end*length_/3)]
	var audit:=City.analyze(result); var constrained: Array=[]
	# At tight multiway junctions a secondary street must approach in its own
	# lane sector instead of bowing across the wider through street.
	for iteration in 8:
		if not audit.ok: return audit
		if audit.diagnostics.is_empty(): break
		var changed:=false
		for problem in audit.diagnostics:
			if problem.code!="unconnected_crossing": continue
			var pair: Array=result.edges.filter(func(e):return e.id in problem.edges)
			if pair.size()!=2: continue
			pair.sort_custom(func(a,b):return a.width_start<b.width_start)
			var narrow: Dictionary=pair[0]; var wide: Dictionary=pair[1]
			for id in [narrow.from,narrow.to]:
				if id not in [wide.from,wide.to]: continue
				for edge in adjacency[id]:
					if edge.get("name")!=narrow.get("name") or not edge.has("controls"): continue
					var index:=0 if edge.from==id else 1
					var other: String=edge.to if index==0 else edge.from
					var handle:=City.xyz(City.vec(nodes[id].position).lerp(City.vec(nodes[other].position),1.0/3))
					if edge.controls[index]!=handle: edge.controls[index]=handle; changed=true
				if id not in constrained: constrained.append(id)
		if not changed: break
		audit=City.analyze(result)
	# Never silently move crossings or change topology to make a curve fit.
	if not audit.diagnostics.is_empty():
		var problem_edges: Array=[]
		for problem in audit.diagnostics:
			for edge in result.edges:
				if edge.id in problem.get("edges",[]): problem_edges.append(edge)
		return {"ok":false,"error":"Fitted streets have unresolved crossings","diagnostics":audit.diagnostics,"edges":problem_edges}
	return {"ok":true,"graph":result,"curves":result.edges.filter(func(e):return e.has("controls")).size(),"constrained_junctions":constrained}

static func tangent(edge: Dictionary, id: String, nodes: Dictionary, adjacency: Dictionary) -> Vector3:
	var at:=City.vec(nodes[id].position)
	var other: String=edge.to if id==edge.from else edge.from
	var outgoing:=(City.vec(nodes[other].position)-at).normalized()
	var neighbor:={}; var best:=-INF
	for candidate in adjacency[id]:
		if candidate.id==edge.id: continue
		var opposite: String=candidate.to if id==candidate.from else candidate.from
		var incoming:=(at-City.vec(nodes[opposite].position)).normalized()
		var alignment:=outgoing.dot(incoming)
		var same: bool=candidate.get("name","")==edge.get("name","")
		if alignment<.5 and not same: continue
		var score:=alignment+(2 if same else 0)+(4 if candidate.kind=="bridge" else 0)
		if score>best: best=score; neighbor={"edge":candidate,"direction":incoming}
	if neighbor.is_empty(): return outgoing
	if neighbor.edge.kind=="bridge": return neighbor.direction
	return (outgoing+neighbor.direction).normalized()

static func merge_squares(records: Array, spec: Dictionary) -> Array:
	var chunks:={}; var scale_m: float=spec.size_m/spec.reference_pixels
	for r in records: chunks[Vector2i(floori(r.position[0]/32),floori(r.position[2]/32))]=r
	for square in spec.squares:
		var polygon:=PackedVector2Array()
		for p in square[1]: polygon.append(Vector2(p[0]-500,p[1]-500)*scale_m)
		var triangles:=Geometry2D.triangulate_polygon(polygon)
		for at in range(0,triangles.size(),3):
			var triangle: Array=[polygon[triangles[at]],polygon[triangles[at+1]],polygon[triangles[at+2]]]
			if Poly.area(triangle)<0: triangle.reverse()
			var bounds:=Rect2(triangle[0],Vector2.ZERO)
			for p in triangle: bounds=bounds.expand(p)
			for x in range(floori(bounds.position.x/32),floori(bounds.end.x/32)+1):
				for z in range(floori(bounds.position.y/32),floori(bounds.end.y/32)+1):
					var piece:=Plan.intersection(triangle,Poly.rect([x*32,z*32,(x+1)*32,(z+1)*32]))
					if piece.is_empty(): continue
					var key:=Vector2i(x,z); var center:=Vector3((x+.5)*32,-.075,(z+.5)*32)
					if not chunks.has(key): chunks[key]={"uuid":"square_%d_%d"%[x,z],"kind":"box","surface_id":"road","position":City.xyz(center),"rotation":[0,0,0],"size":[32,.2,32],"color":[.55,.49,.36],"road_mesh":{"polygons":[],"uv_origin":City.xyz(Vector3(center.x,0,center.z))},"editor_name":"市场广场铺面"}
					var r: Dictionary=chunks[key]; var fragments: Array=[piece]
					for existing in r.road_mesh.polygons:
						var mask: Array=existing.map(func(p):return Vector2(p[0]*32+center.x,p[1]*32+center.z)); var next: Array=[]
						for fragment in fragments: next.append_array(Poly.subtract(fragment,mask))
						fragments=next
					for fragment in fragments:
						var normalized:=Plan.normalized_patch(fragment,center)
						if not normalized.is_empty(): r.road_mesh.polygons.append(normalized)
	return chunks.values()

static func clip_map_bounds(records: Array) -> Array:
	var out: Array=[]; var bounds:=Poly.rect([-700,-700,700,700])
	for r in records:
		var center:=City.vec(r.position); var polys: Array=[]
		for polygon in r.road_mesh.polygons:
			var world: Array=polygon.map(func(p):return Vector2(p[0]*32+center.x,p[1]*32+center.z))
			var clipped:=Plan.intersection(world,bounds)
			if not clipped.is_empty():
				var normalized:=Plan.normalized_patch(clipped,center)
				if not normalized.is_empty(): polys.append(normalized)
		if not polys.is_empty(): r.road_mesh.polygons=polys; out.append(r)
	return out
