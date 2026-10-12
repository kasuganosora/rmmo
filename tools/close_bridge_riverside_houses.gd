extends "res://tools/residential_bridge_street.gd"
## A pose-only correction of the added riverside residence and its door lamp.
const SPACING_OUT="D:/code/rmmo_runtime/review_artifacts/bridge_house_spacing_20261007"
const PRIOR_OUT="D:/code/rmmo_runtime/review_artifacts/bridge_residential_complete_20261007"
const HOME="building_20261007ba0000000001"
const NEIGHBOR="building_afe702fd4f2205041eaf"
const LAMP="obj_330016"
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
func run()->void:
	OUT=SPACING_OUT
	if "--publish" in OS.get_cmdline_user_args():await super.run();return
	DirAccess.make_dir_recursive_absolute(OUT)
	var baseline:=FileAccess.get_sha256(FORMAL)
	var d=Doc.open_file(FORMAL)
	check(d!=null,"latest native map opened")
	if failed:quit(1);return
	var p:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(PRIOR_OUT+"/plan.json"))
	var original:Array=d.records.duplicate(true);var original_meta:Dictionary=d.map_meta.duplicate(true)
	var source:Dictionary=d.map_meta.building_instances[HOME]
	check(Blueprint.vec(source.position).distance_to(Vector3(304,0,199))<.001,"house still at reviewed starting position")
	var members:Array=d.records.filter(func(r):return r.get("building",{}).get("id")==HOME)
	check(members.size()==16 and members.all(func(r):return not r.get("editor_locked",false)),"whole residence editable")
	check(not d._find(LAMP).get("editor_locked",false),"door lamp editable")
	if failed:quit(1);return
	var delta:=Basis(Vector3.UP,deg_to_rad(source.yaw))*Vector3(5.5,0,-3.6)
	var prepared:Dictionary=preload("res://scripts/world_editor/building_motion.gd").new().proposal([{ "id":HOME,"value":source,"records":members}],delta,Basis.IDENTITY,Blueprint.vec(source.position))
	check(prepared.ok,"shared rigid building movement")
	var candidate:Dictionary=prepared.plans[0];var bounds:=Geometry.bounds(candidate.records)
	var excluded:Array=members.map(func(r):return r.uuid);excluded.append(LAMP);excluded.append("obj_201010")
	var laundry:Dictionary=d._find("obj_201010").duplicate(true)
	laundry.position=Blueprint.arr(Blueprint.vec(laundry.position)+Vector3(-1.5,0,-1.5))
	var blocked:Array=[]
	for obstacle:Dictionary in d.records:
		if obstacle.uuid in excluded:continue
		# A tree's leaf-canopy bounds are not a solid box. Keep its trunk clear;
		# inspect the actual overhanging crown in the outdoor GPU preview.
		if obstacle.uuid=="obj_201002":
			var trunk:Dictionary={"kind":"box","position":obstacle.position,"rotation":[0,0,0],"size":[1.5,12,1.5]}
			if Foot.batches_overlap(candidate.occupancy,Foot.record_shapes(trunk)):blocked.append(obstacle.uuid)
			continue
		if not obstacle.has("building") and not obstacle.has("road_mesh") and not obstacle.has("bridge_mesh") and obstacle.get("kind")!="asset":continue
		if bounds.intersects(Geometry.bounds([obstacle])) and Foot.batches_overlap(candidate.occupancy,Foot.record_shapes(obstacle)):blocked.append(obstacle.uuid)
	check(not Foot.batches_overlap(candidate.occupancy,Foot.record_shapes(laundry)),"laundry clear of house")
	var laundry_bounds:=Geometry.bounds([laundry]);var laundry_blocked:Array=[]
	for obstacle:Dictionary in d.records:
		if obstacle.uuid in excluded or obstacle.uuid=="obj_201002":continue
		if not obstacle.has("building") and not obstacle.has("road_mesh") and obstacle.get("kind")!="asset":continue
		if laundry_bounds.intersects(Geometry.bounds([obstacle])) and Foot.batches_overlap(Foot.record_shapes(laundry),Foot.record_shapes(obstacle)):laundry_blocked.append(obstacle.uuid)
	check(laundry_blocked.is_empty(),"laundry outside roadway and existing objects: "+str(laundry_blocked))
	check(blocked.is_empty(),"houses, eaves, tree trunk and roads remain clear: "+str(blocked))
	check(not Foot.batches_overlap(candidate.occupancy,preload("res://scripts/world3d/planning_zones.gd").obstacles(d.map_meta)),"reserved areas preserved")
	if failed:quit(1);return
	d.checkpoint_recovery()
	var replacements:Dictionary={}
	for r:Dictionary in candidate.records:replacements[r.uuid]=r
	replacements[laundry.uuid]=laundry
	for i in d.records.size():
		if replacements.has(d.records[i].uuid):d.records[i]=replacements[d.records[i].uuid]
	d.map_meta.building_instances[HOME]=candidate.value
	d._find(LAMP).position=Blueprint.arr(Blueprint.vec(d._find(LAMP).position)+delta)
	check(Blueprint.valid_ownership(d.map_meta,d.records),"per-floor and fixture ownership preserved")
	for r:Dictionary in original:
		if r.uuid not in excluded and not equivalent(r,d._find(r.uuid)):check(false,"unrelated record changed "+r.uuid)
	var old_meta:=original_meta.duplicate(true);var new_meta:Dictionary=d.map_meta.duplicate(true)
	old_meta.building_instances.erase(HOME);new_meta.building_instances.erase(HOME)
	check(equivalent(old_meta,new_meta),"all other buildings and map metadata unchanged")
	var final:Array=d.records.duplicate(true);var final_meta:Dictionary=d.map_meta.duplicate(true)
	check(d.undo() and equivalent(d.records,original) and equivalent(d.map_meta,original_meta),"single move undo")
	check(d.redo() and equivalent(d.records,final) and equivalent(d.map_meta,final_meta),"single move redo")
	p.records=d.records;p.metadata=d.map_meta;p.next=d._next;p.failures=failed;p.formal_sha256=baseline
	p.spacing={"house":HOME,"neighbor":NEIGHBOR,"before":source.position,"after":candidate.value.position,"delta":Blueprint.arr(delta),"distance":delta.length(),"moved_records":excluded}
	for h:Dictionary in p.houses:if h.id==HOME:h.position=candidate.value.position
	for lamp:Dictionary in p.lamps:if lamp.id==LAMP:lamp.position=d._find(LAMP).position
	FileAccess.open(OUT+"/plan.json",FileAccess.WRITE).store_string(JSON.stringify(p))
	print("HOUSE_SPACING ",JSON.stringify(p.spacing)," failures=",failed);quit(failed)
