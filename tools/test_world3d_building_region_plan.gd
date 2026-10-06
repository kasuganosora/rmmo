extends SceneTree
const Region=preload("res://scripts/world_editor/building_region.gd")
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const Footprint=preload("res://scripts/world_editor/building_footprint.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Editor=preload("res://scripts/world_editor/world_editor.gd")
var failed:=0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	print("%s: %s"%["PASS" if ok else "FAIL",label]); if not ok: failed+=1

func run() -> void:
	var doc:=Doc.new(); doc.add_box("ground",Vector3(0,-.1,0),Vector3(160,.2,140))
	var obstacle: String=doc.add_box("block",Vector3(0,5,0),Vector3(14,10,40),Vector3(0,17,0))
	doc._find(obstacle).editor_hidden=true; doc._find(obstacle).editor_locked=true
	for style in ["urban_village","medieval","standard"]:
		for yaw in [0,90,180,-90]:
			var args:={"from":[-35,0,-30],"to":[35,0,30],"style":style,"mode":"block","seed":19,"yaw":yaw,"max_buildings":6}
			var result:=Region.plan(args,doc.records)
			check(result.ok,"seeded region for %s / %d"%[style,yaw])
			if not result.ok: print(result); continue
			check(result==Region.plan(args,doc.records),"identical seed and obstacles reproduce the exact plan")
			var occupied: Array=[]; var safe:=true; var inside:=true
			for placement in result.request.placements:
				var plan:=Blueprint.generate(placement.parameters)
				var shapes:=Footprint.components(plan.records,Blueprint.vec(placement.position),Basis(Vector3.UP,deg_to_rad(placement.yaw)))
				safe=safe and not Footprint.batches_overlap(shapes,[Footprint.record_shape(doc._find(obstacle))]) and not Footprint.batches_overlap(shapes,occupied)
				for shape in shapes: inside=inside and shape.bounds.position.x>=-35-.001 and shape.bounds.end.x<=35+.001 and shape.bounds.position.z>=-30-.001 and shape.bounds.end.z<=30+.001
				occupied.append_array(shapes)
			check(safe and inside,"all overhangs stay inside region and avoid hidden/locked props and each other")
			var next:=Region.plan(args.merged({"seed":20},true),doc.records)
			check(next.ok and next.plan_token!=result.plan_token,"reroll changes the proposal")
	var small:={"from":[-7,0,-9],"to":[7,0,9],"seed":3}
	check(Region.plan(small,[doc.records[0]]).ok,"single-house shortcut fits a practical small lot")
	check(not Region.plan(small,doc.records).ok,"fully obstructed lot fails without deleting existing objects")
	for bad in [{"from":[0,0,0],"to":[2,0,2]},{"from":[0,0,0],"to":[30,1,30]},{"from":[0,0,0],"to":[501,0,20]},small.merged({"yaw":45},true),small.merged({"rental_units":4},true)]:
		check(not Region.plan(bad,doc.records).ok,"reject malformed, sloped or unusable region")
	print("test_world3d_building_region_plan: %s"%("PASS" if failed==0 else "FAIL")); quit(0 if failed==0 else 1)
