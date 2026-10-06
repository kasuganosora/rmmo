extends SceneTree
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Split=preload("res://scripts/world3d/road_intersections.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Zones=preload("res://scripts/world3d/planning_zones.gd")
var failed:=0
func check(ok: bool,label_: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+label_)
	if not ok: failed+=1
static func graph(paths: Array) -> Dictionary:
	var result:={"nodes":[],"edges":[]}; var ids:={}
	for path in paths:
		var previous:=""
		for xyz in path:
			var key:=str(xyz)
			if not ids.has(key):
				ids[key]="node_%d"%ids.size(); result.nodes.append({"id":ids[key],"position":xyz})
			if not previous.is_empty(): result.edges.append({"id":"edge_%d"%result.edges.size(),"from":previous,"to":ids[key],"kind":"ground","width_start":4.0,"width_end":4.0})
			previous=ids[key]
	return result
static func covers(records: Array,point: Vector3) -> bool:
	for record in records:
		for shape in Foot.record_shapes(record):
			if point.y>=shape.bounds.position.y and point.y<=shape.bounds.end.y and Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),shape.polygon): return true
	return false
func _init() -> void: call_deferred("run")
func run() -> void:
	var cases:={
		"cross":[[[-60,0,0],[60,0,0]],[[0,0,-35],[0,0,35]]],
		"T":[[[-40,0,0],[40,0,0]],[[0,0,0],[0,0,30]]],
		"Y":[[[0,0,-30],[0,0,0],[25,0,30]],[[0,0,0],[-25,0,30]]],
		"acute":[[[-30,0,0],[0,0,0],[-25,0,7]]],
		"ring":[[[-25,0,-25],[25,0,-25],[25,0,25],[-25,0,25],[-25,0,-25]]]
	}
	for name_ in cases:
		var g:=graph(cases[name_]); var split:=Split.split(g); check(split.ok,name_+" intersection splitting")
		if not split.ok: print(split); continue
		var again:=Split.split(split.graph); check(again.ok and again.graph==split.graph,name_+" repeated split is idempotent")
		var result:=Plan.build(split.graph,Plan.defaults()); check(result.ok,name_+" road plan valid")
		if not result.ok: print(result); continue
		check(result.area>0 and result.chunks>0,name_+" area and chunks")
		var mesh_ok:=true; var overlaps:=false
		for r in result.records:
			var mesh:=Surface.mesh(r,null); mesh_ok=mesh_ok and mesh.get_surface_count()==3
			var shapes:=Foot.record_shapes(r)
			for i in shapes.size():
				for j in range(i+1,shapes.size()): overlaps=overlaps or Foot.overlaps(shapes[i],shapes[j])
			var arrays:=mesh.surface_get_arrays(0)
			for n in arrays[Mesh.ARRAY_NORMAL]: mesh_ok=mesh_ok and n.y>.999
		check(mesh_ok and not overlaps,name_+" upward mesh normals and disjoint pavement patches")
		if name_=="cross": check(covers(result.records,Vector3(0,1,0)) and covers(result.records,Vector3(32,1,0)),"junction and cell seam have pavement")
		if name_=="ring": check(not covers(result.records,Vector3(0,1,0)),"ring courtyard remains empty")
	var curve:=graph([[[-40,0,0],[40,0,0]],[[0,0,-35],[0,0,35]]]); curve.edges[0].controls=[[-20,0,20],[20,0,-20]]
	var split:=Split.split(curve); check(split.ok,"cubic crossing splits")
	if split.ok:
		var again:=Split.split(split.graph); check(again.ok and again.graph==split.graph,"repeated cubic split preserves exact controls and token")
		var source:=Data.analyze(curve); var solved:=Data.analyze(split.graph); var matches:=true
		for edge in split.graph.edges:
			if not edge.id.begins_with("edge_0"): continue
			var lo:=Split.nearest(curve.edges[0],source.nodes,Data.vec(solved.nodes[edge.from].position)); var hi:=Split.nearest(curve.edges[0],source.nodes,Data.vec(solved.nodes[edge.to].position))
			for i in 11: matches=matches and Split.position(edge,solved.nodes,i/10.0).distance_to(Split.position(curve.edges[0],source.nodes,lerpf(lo,hi,i/10.0)))<.001
		check(matches,"split subcurves preserve original cubic geometry")
		var result:=Plan.build(split.graph,Plan.defaults()); check(result.ok,"curved pavement union valid"); if not result.ok: print(result)
	var bend:=graph([[[-80,0,0],[80,0,0]]]); bend.edges[0].controls=[[-25,0,50],[25,0,-50]]
	var tee:=graph([[[0,0,-40],[0,0,0],[0,0,40]],[[0,0,0],[60,0,0]]])
	for e in tee.edges: e.width_start=14 if e.id=="edge_2" else 6; e.width_end=e.width_start
	var tee_plan:=Plan.build(tee,Plan.defaults())
	check(tee_plan.ok and covers(tee_plan.records,Vector3(1,1,0)) and not covers(tee_plan.records,Vector3(-5,1,0)),"wide T branch has continuous junction without a cap protruding through the narrow street")
	var bend_plan:=Plan.build(bend,Plan.defaults())
	check(bend_plan.ok,"continuous S bend builds")
	if bend_plan.ok:
		var checked:=Data.analyze(bend); var coverage:=true; var outside:=false; var overlap:=false; var patches:=0
		for i in range(1,40):
			var t:=i/40.0; var p:=Split.position(bend.edges[0],checked.nodes,t); var d:=Split.derivative(bend.edges[0],checked.nodes,t).normalized(); var side:=Vector3(-d.z,0,d.x)
			for sign_ in [-1,1]:
				coverage=coverage and covers(bend_plan.records,p+side*1.9*sign_+Vector3.UP)
				outside=outside or covers(bend_plan.records,p+side*2.25*sign_+Vector3.UP)
		for record in bend_plan.records:
			patches+=record.road_mesh.polygons.size()
			var shapes:=Foot.record_shapes(record)
			for i in shapes.size():
				for j in range(i+1,shapes.size()): overlap=overlap or Foot.overlaps(shapes[i],shapes[j])
		check(coverage and not outside,"S bend covers both edges at intended width without join bulges")
		check(not overlap and patches<100,"shared curve edges produce disjoint compact patches")
	var bridge:=graph([[[-40,0,0],[40,0,0]],[[0,5,-30],[0,5,30]]]); bridge.edges[1].kind="bridge"
	check(Split.split(bridge).added_nodes==0,"grade separation does not join nodes")
	check(Plan.build(bridge,Plan.defaults()).ok,"5m bridge with sufficient underside clearance")
	bridge.nodes[2].position[1]=2; bridge.nodes[3].position[1]=2
	check(not Plan.build(bridge,Plan.defaults()).ok,"insufficient bridge clearance rejected")
	var parallel:=graph([[[-30,0,0],[30,0,0]],[[-30,5,0],[30,5,0]]]); parallel.edges[1].kind="bridge"
	check(Plan.build(parallel,Plan.defaults()).ok,"parallel bridge above ground road retains separate surfaces")
	var slope:=graph([[[0,0,0],[20,2,0]]]); check(Plan.build(slope,Plan.defaults()).ok,"straight slope with level end landings")
	slope.nodes[1].position[1]=3; check(not Plan.build(slope,Plan.defaults()).ok,"grade after reserving landings must remain below 15 percent")
	var zone:={"id":"test","polygon":[[0,0],[20,0],[20,5],[5,5],[5,20],[0,20]],"min_y":-2,"max_y":50,"purpose":"no_build","hidden":true}
	check(Zones.valid([zone]),"concave hidden zone valid")
	var meta:={"editor_layout":{"zones":[zone]}}; var obstacles:=Zones.obstacles(meta)
	check(obstacles.size()==4,"concave zone triangulated")
	var box:={"position":[12,2,12],"size":[2,4,2],"rotation":[0,0,0]}
	check(not Foot.batches_overlap(Foot.record_shapes(box),obstacles),"empty concave corner stays buildable")
	box.position=[2,2,12]; check(Foot.batches_overlap(Foot.record_shapes(box),obstacles),"hidden no-build area still constrains building")
	zone.polygon=[[0,0],[10,10],[0,10],[10,0]]; check(not Zones.valid([zone]),"self-intersecting zone rejected")
	print("test_road_plan: failures=%d"%failed); quit(0 if failed==0 else 1)
