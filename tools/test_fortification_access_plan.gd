extends SceneTree
const Plan=preload("res://scripts/world3d/fortification_plan.gd")
const Channel=preload("res://scripts/world3d/channel_surface.gd")
var failed:=0
func _initialize() -> void:
	for shape in ["path","circle","ellipse"]:
		var args:={"id":"walk","style":"medieval_stone","wall_access":true,"arrow_slits":true,"height":7.5,"thickness":3.5,"points":[[-20,0],[20,0]],"shape":"path" if shape=="path" else "ellipse","radius_x":40,"radius_z":30 if shape=="ellipse" else 40}
		var plan:=Plan.new().build(args)
		check(plan.ok,"access plan "+shape)
		if not plan.ok: print(plan); continue
		check(not plan.access_routes.is_empty() and plan.access_routes[0].stair_width>=2.6 and plan.access_routes[0].entry_clearance>=5,"wide stairs and city-facing entry "+shape)
		var valid:=true
		for r in plan.records:
			if not Channel.valid(r): print("INVALID_CHANNEL ",r.fortification.part); valid=false
		check(valid,"all clipped hollow-tower polygons validate "+shape)
		check(plan.records.all(func(r):return r.fortification.role!="corner_tower"),"solid tower cores removed "+shape)
		var stairs: Array=plan.records.filter(func(r):return r.fortification.role=="tower_stair")
		check(stairs.size()==plan.access_routes.size(),"one internal stair mesh per hollow tower "+shape)
		for i in stairs.size():
			var route: Dictionary=plan.access_routes[i]; var center:=Vector2(route.room[0],route.room[2])
			check(Vector2(stairs[i].position[0],stairs[i].position[2]).distance_to(center)<.001 and is_equal_approx(stairs[i].size[0],route.radius*2),"stair mesh remains centered inside round tower "+shape)
			for key in ["stairs_bottom","stairs_top"]: check(Vector2(route[key][0],route[key][2]).distance_to(center)<route.radius-.55,"stair endpoints remain inside tower skin "+shape)
		print("ACCESS_PLAN ",shape," records=",plan.records.size()," route=",plan.access_routes[0])
	for points in [[[-25,-25],[25,-25],[25,25],[-25,25]],[[-25,25],[25,25],[25,-25],[-25,-25]]]:
		var enclosed:=Plan.new().build({"id":"closed","style":"medieval_stone","wall_access":true,"arrow_slits":true,"height":7.5,"thickness":3.5,"closed":true,"points":points})
		check(enclosed.ok,"both windings create city-facing entrances and internal spiral stairs")
		if enclosed.ok:
			for route in enclosed.access_routes: check(Geometry2D.is_point_in_polygon(Vector2(route.entry[0],route.entry[2]),PackedVector2Array(points.map(func(p):return Vector2(p[0],p[1])))),"tower entrance faces inside closed wall")
	check(not Plan.new().build({"id":"low","style":"medieval_stone","wall_access":true,"height":5,"thickness":3.5,"points":[[-20,0],[20,0]]}).ok,"5m entrance cannot protrude through a low tower roof")
	print("ACCESS_PLAN_FINISHED failures=",failed); quit(0 if failed==0 else 1)
func check(value: bool,label_: String) -> void:
	print(("PASS " if value else "FAIL ")+label_)
	if not value: failed+=1
