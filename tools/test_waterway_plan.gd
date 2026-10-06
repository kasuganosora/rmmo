extends SceneTree
const Plan=preload("res://scripts/world3d/waterway_plan.gd")
const W=preload("res://scripts/world3d/waterway_data.gd")
var failures:=0
func check(ok: bool,label_: String) -> void:
	print(("PASS " if ok else "FAIL ")+label_)
	if not ok: failures+=1
func _initialize() -> void:
	var source:={"uuid":"land","kind":"box","surface_id":"ground","position":[0,-.25,0],"rotation":[0,0,0],"size":[120,.5,120]}
	var settings:=W.defaults().merged({"id":"river","ground_ids":["land"],"points":[[0,-50],[0,50]],"bridges":[{"id":"crossing","segment":0,"t":.5,"width":5.0,"approach":3.0,"rail_height":1.1}]},true)
	var solver:=Plan.new(); var result:=solver.build(settings,[source]); check(result.ok,"straight channel, banks and bridge solve")
	if not result.ok: print(result); quit(1); return
	check(absf(result.area-1200)<.01,"water area matches width and length")
	var ground: Dictionary=result.records[0]
	check(not Plan.Foot.record_shapes(ground).any(func(s):return Geometry2D.is_point_in_polygon(Vector2(0,20),s.polygon)),"excavated ground leaves a real hole")
	check(Plan.Foot.record_shapes(ground).any(func(s):return Geometry2D.is_point_in_polygon(Vector2(30,20),s.polygon)),"land beyond the bank remains")
	check(result.records.filter(func(r):return result.roles[r.uuid]=="water").all(func(r):return r.collision=="none"),"water is not walkable")
	check(result.crossings[0].endpoints==[[11.0,0.0,0.0],[-11.0,0.0,0.0]],"bridgeheads have exact world positions")
	var overlap:=false
	for r in result.records:
		if result.roles[r.uuid]!="bank" or absf(r.position[1]+r.size[1]*.5-.025)>.001: continue
		for shape in Plan.Foot.record_shapes(r):
			var bank: Array=Array(shape.polygon); bank.pop_back()
			if not preload("res://scripts/world3d/road_plan.gd").intersection(bank,result.crossings[0].shape.polygon.slice(0,4)).is_empty(): overlap=true
	check(not overlap,"bridge and bank have no overlapping coplanar top faces")
	var stable:=true
	for r in result.records:
		var a:=MeshInstance3D.new(); var b:=MeshInstance3D.new(); a.mesh=Plan.Surface.mesh(r,null); b.mesh=Plan.Surface.mesh(JSON.parse_string(JSON.stringify(r)),null)
		var paint=preload("res://scripts/world3d/surface_materials.gd"); var original: Dictionary=paint.geometry(a); var reopened: Dictionary=paint.geometry(b)
		for i in original.surfaces.size(): stable=stable and original.surfaces[i].signature==reopened.surfaces[i].signature
		a.free(); b.free()
	check(stable,"mesh / paint signatures survive JSON roundtrip")
	var bent:=settings.duplicate(true); bent.points=[[-15,-50],[-15,-10],[15,20],[15,50]]; bent.bridges=[]
	var bent_result:=solver.build(bent,[source]); check(bent_result.ok,"bent channel clips without filling concave corners")
	if not bent_result.ok: print(bent_result)
	var bad:=settings.duplicate(true); bad.points=[[0,-20],[10,20],[-10,20],[0,-20]]
	check(not solver.build(bad,[source]).ok,"loop / bank overlap fails")
	bad=settings.duplicate(true); bad.bridges[0].t=.02; check(not solver.build(bad,[source]).ok,"bridge near endpoint fails")
	bad=settings.duplicate(true); bad.points=[[80,-50],[80,50]]; check(not solver.build(bad,[source]).ok,"unsupported channel fails")
	bad=settings.duplicate(true); bad.bridges.append(bad.bridges[0].merged({"id":"second"},true)); check(not solver.build(bad,[source]).ok,"overlapping bridgeheads fail")
	print("WATERWAY_MATH_FINISHED failures=%d"%failures); quit(0 if failures==0 else 1)
