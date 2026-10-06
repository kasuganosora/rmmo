extends SceneTree
const Plan=preload("res://scripts/world3d/fortification_plan.gd")
const F=preload("res://scripts/world3d/fortification_data.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
var failed:=0
func check(ok: bool,label_: String) -> void:
	print(("PASS " if ok else "FAIL ")+label_)
	if not ok: failed+=1
func _initialize() -> void:
	var s:=F.defaults().merged({"id":"wall","points":[[-30,-30],[30,-30],[30,30],[-30,30]],"closed":true,"gates":[{"id":"north","segment":0,"t":.5,"width":6,"height":4.5,"open":1}]},true)
	var r:=Plan.new().build(s); check(r.ok,"closed walls, towers, crenellations and gate generated")
	if not r.ok: print(r); quit(1); return
	check(r.records.any(func(p):return p.fortification.role=="corner_tower") and r.records.filter(func(p):return p.has("fixture")).size()==2,"corner towers and two articulated leaves")
	var clearance:=preload("res://scripts/world3d/waterway_plan.gd").shape([Vector2(-2,-34),Vector2(2,-34),Vector2(2,-26),Vector2(-2,-26)],0,3)
	check(not r.records.filter(func(p):return not p.has("fixture")).any(func(p):return Foot.batches_overlap(Foot.record_shapes(p),[clearance])),"gate masonry leaves a real traversable opening")
	var bad:=s.duplicate(true); bad.gates[0].height=6; check(not Plan.new().build(bad).ok,"gate must leave a load-bearing lintel")
	bad=s.duplicate(true); bad.points=[[-20,-20],[20,20],[-20,20],[20,-20]]; check(not Plan.new().build(bad).ok,"crossed wall loop rejected")
	bad=s.duplicate(true); bad.gates[0].t=.02; check(not Plan.new().build(bad).ok,"gate near corner tower rejected")
	bad=s.duplicate(true); bad.gates=[]; bad.points=[[0,0],[40,0],[40,30],[20,15]]; check(not Plan.new().build(bad).ok,"sharp closing seam rejected")
	var ring:=F.defaults().merged({"id":"ring","shape":"ellipse","gates":[{"id":"north","angle":270,"width":6,"height":4.5,"open":1}]},true)
	var circle:=Plan.new().build(ring); check(circle.ok,"circular wall with round towers and cardinal gate generated")
	if circle.ok:
		check(circle.records.any(func(p):return p.has("channel_mesh")) and absf(circle.length-TAU*40)<.1,"circle uses curved slabs and expected circumference")
		var inner:=preload("res://scripts/world3d/waterway_plan.gd").shape([Vector2(-10,-10),Vector2(10,-10),Vector2(10,10),Vector2(-10,10)],0,4)
		check(not circle.records.any(func(p):return Foot.batches_overlap(Foot.record_shapes(p),[inner])),"round wall leaves town center physically empty")
		var opening:=preload("res://scripts/world3d/waterway_plan.gd").shape([Vector2(-2,-45),Vector2(2,-45),Vector2(2,-35),Vector2(-2,-35)],0,3)
		check(not circle.records.filter(func(p):return not p.has("fixture")).any(func(p):return Foot.batches_overlap(Foot.record_shapes(p),[opening])),"curved north gate keeps road clearance")
	bad=ring.duplicate(true); bad.radius_x=60; bad.radius_z=35; bad.rotation=23; check(Plan.new().build(bad).ok,"rotated elliptical city perimeter supported")
	bad=ring.duplicate(true); bad.gates[0].angle=0; check(Plan.new().build(bad).ok,"gate crossing circular parameter seam remains open")
	bad=ring.duplicate(true); bad.gates[0].angle=22.5; check(not Plan.new().build(bad).ok,"ring gate colliding with tower rejected")
	bad=ring.duplicate(true); bad.radius_x=200; bad.radius_z=15; check(not Plan.new().build(bad).ok,"overly flattened ellipse rejected")
	bad=ring.duplicate(true); bad.radius_x=15; bad.radius_z=15; bad.tower_count=24; bad.thickness=4; bad.gates=[]; check(not Plan.new().build(bad).ok,"overcrowded circular towers rejected")
	bad=s.duplicate(true)
	for key in ["shape","center_x","center_z","radius_x","radius_z","rotation","tower_count"]: bad.erase(key)
	check(F.valid_settings(bad) and Plan.new().build(bad).ok,"legacy path recipes still validate without ring fields")
	print("FORTIFICATION_MATH_FINISHED failures=%d"%failed); quit(0 if failed==0 else 1)
