extends SceneTree
const Plan=preload("res://scripts/world3d/fortification_plan.gd")
var failures:=0
func check(value: bool,label: String) -> void:
	if not value: failures+=1
	print(("PASS " if value else "FAIL ")+label)
func _initialize() -> void:
	var args:={"id":"water_test","style":"medieval_stone","height":7.5,"thickness":3.5,"wall_access":true,"layout_version":1,"points":[[-60,0],[60,0]],"tower_indices":[0,1],"gates":[{"id":"river","kind":"water","segment":0,"t":.5,"width":50,"height":5,"open":1}]}
	var parsed: Dictionary=JSON.parse_string(JSON.stringify(args)); var result:=Plan.new().build(parsed)
	check(result.ok,"JSON numeric node indices and water gate accepted")
	if result.ok:
		check(result.access_routes.size()==2,"selected endpoint towers survive HTTP number decoding")
		check(not result.records.any(func(r):return r.get("fixture",{}).get("id")=="river"),"water opening has no giant door leaves")
		check(result.records.filter(func(r):return r.fortification.role=="gate_lintel").all(func(r):return r.position[1]-r.size[1]*.5>=5),"water gate starts above 5m clearance")
	check(not Plan.new().build(args.merged({"tower_indices":[0,.5]},true)).ok,"fractional indices rejected before normalization")
	check(not Plan.new().build(args.merged({"tower_indices":[0,0]},true)).ok,"duplicate indices rejected")
	var land:=args.duplicate(true); land.gates[0].kind="land"
	check(not Plan.new().build(land).ok,"land doors cannot exceed 32m")
	var covered:=true
	for sign_ in [-1,1]:
		var leaf:={"kind":"box","position":[30,3,40],"rotation":[0,31,0],"size":[9,5,.18],"fortification":{"id":"f","part":"door","role":"door"},"fixture":{"id":"d","kind":"door","pivot":[sign_*4.5,0,0],"angle":sign_*100,"open":1}}
		var shape: Dictionary=preload("res://scripts/world_editor/building_footprint.gd").record_shapes(leaf)[0]
		var local:=AABB(Vector3(-4.5,-2.5,-.09),Vector3(9,5,.18))
		for i in 1001:
			leaf.fixture.open=i/1000.; var pose:=preload("res://scripts/world3d/building_fixtures.gd").transform(leaf)
			for corner in 8:
				var p: Vector3=pose*local.get_endpoint(corner)
				covered=covered and Geometry2D.is_point_in_polygon(Vector2(p.x,p.z),shape.polygon) and shape.bounds.has_point(p)
	check(covered,"conservative sweep covers 1001 real poses for both rotated door leaves")
	var trace: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/medieval_town_wall_trace.json"))
	var town:={"id":"precision_town","style":"medieval_stone","height":7.5,"thickness":3.5,"wall_access":true,"arrow_slits":true,"layout_version":1,"closed":true,"points":trace.pixels.map(func(v):return [(v[0]-500)*1.4,(v[1]-500)*1.4]),"tower_indices":[1,3,5,7,9,11,13,15,17,19,21,23,25,28,30,33,36,39,42,43,45,47,49,51,54,57,60]}
	var town_plan:=Plan.new().build(town)
	check(town_plan.ok,"kilometre-scale trace geometry builds")
	if town_plan.ok:
		var validator:=preload("res://scripts/world3d/world_document.gd").new()
		check(town_plan.records.all(func(r):return validator.validate_save_record(r)==OK),"every distant clipped merlon and tower record passes native save validation")
	print("TRACE_GEOMETRY_FINISHED failures=",failures); quit(1 if failures else 0)

