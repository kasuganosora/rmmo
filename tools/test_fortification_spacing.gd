extends SceneTree
const Plan=preload("res://scripts/world3d/fortification_plan.gd")
const Spacing=preload("res://scripts/world3d/fortification_spacing.gd")
var failed:=0
func _initialize() -> void:
	var base:={"id":"test","style":"medieval_stone","height":7.5,"thickness":3.5,"wall_access":true,"arrow_slits":true,"layout_version":1,"tower_layout":"automatic","tower_count":0}
	for z in [40,30]:
		var args:=base.merged({"shape":"ellipse","radius_x":40,"radius_z":z},true); var p:=Plan.new().build(args)
		check(p.ok,"automatic ring can reduce excessive tower count "+str(z))
		if p.ok:
			var centers:=Spacing.record_centers(p.records)
			check(centers.size()<8 and Spacing.validate(centers,[],5.6).ok,"all tower pairs satisfy 50m center exclusion")
			check(not p.layout_zones.is_empty(),"preview includes exclusion circles")
		check(not Plan.new().build(args.merged({"tower_count":8},true)).ok,"automatic mode rejects explicit crowded count")
		check(Plan.new().build(args.merged({"tower_count":8,"tower_layout":"manual"},true)).ok,"manual mode allows original 8-tower layout")
		for count in [1,2]: check(Plan.new().build(args.merged({"tower_count":count,"tower_layout":"manual"},true)).ok,"manual mode also allows fewer than three towers")
	var near:=base.merged({"points":[[-20,0],[20,0]]},true)
	check(not Plan.new().build(near).ok,"automatic path rejects crowded corner towers")
	var manual:=Plan.new().build(near.merged({"tower_layout":"manual"},true))
	check(manual.ok,"manual path keeps requested nearby towers")
	if manual.ok:
		var floors: Array=manual.records.filter(func(r):return r.fortification.part.contains("_ground_floor"))
		check(floors.size()>0 and floors.all(func(r):return absf(r.position[1]+r.size[1]*.5-.03)<.001 and absf(r.position[1]-r.size[1]*.5+1)<.001),"stone floor top and one-meter solid foundation")
	var gate:=base.merged({"points":[[-30,0],[30,0]],"gates":[{"id":"entry","segment":0,"t":.22,"width":5,"height":5,"open":1}]},true)
	gate=JSON.parse_string(JSON.stringify(gate)) # HTTP JSON integer fields arrive as floats.
	check(not Plan.new().build(gate).ok,"automatic tower-gate clearance enforced")
	check(Plan.new().build(gate.merged({"tower_layout":"manual"},true)).ok,"manual gate placement ignores aesthetic clearance")
	check(not Spacing.cross_validate([Vector2.ZERO],[],5.6,[Vector2(0,40)],[],5.6).ok,"cross-group tower spacing cannot bypass auto rule")
	check(Spacing.cross_validate([Vector2.ZERO],[],5.6,[Vector2(0,50)],[],5.6).ok,"50m boundary accepted")
	var gated:=base.merged({"shape":"ellipse","radius_x":40,"radius_z":40,"gates":[{"id":"entry","angle":45,"width":6,"height":5,"open":1}]},true)
	var shifted:=Plan.new().build(gated)
	check(shifted.ok,"automatic ring shifts tower phase away from gate")
	if shifted.ok: check(Spacing.validate(Spacing.record_centers(shifted.records),Spacing.gates(shifted.get("settings",preload("res://scripts/world3d/fortification_data.gd").defaults().merged(gated,true))),5.6).ok,"shifted ring retains tower and actual gate chord clearance")
	check(Plan.new().build(near.merged({"layout_version":0},true)).ok,"saved legacy layout still rebuilds for gate operation")
	print("SPACING_FINISHED failures=",failed); quit(0 if failed==0 else 1)
func check(ok_: bool,label_: String) -> void:
	print(("PASS " if ok_ else "FAIL ")+label_)
	if not ok_: failed+=1
