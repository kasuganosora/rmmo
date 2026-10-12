extends "res://tools/residential_bridge_street.gd"
const FINAL_OUT="D:/code/rmmo_runtime/review_artifacts/bridge_residential_complete_20261007"
const LAMPS="D:/code/rmmo_runtime/review_artifacts/bridge_residential_lamps_20261007"
const SAMPLE="building_afe702fd4f2205041eaf"
const NEW_HOME="building_20261007ba0000000001"
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
func ground_at(records:Array,point:Vector3)->float:
	for r:Dictionary in records:
		if not r.has("terrain_mesh"):continue
		var pose:=Terrain.transform(r);var local:=pose.affine_inverse()*point;var y:=Terrain.sample(r,local)
		if is_finite(y):return (pose*Vector3(local.x,y,local.z)).y
	return NAN
func run()->void:
	OUT=FINAL_OUT
	if "--publish" in OS.get_cmdline_user_args():await super.run();return
	DirAccess.make_dir_recursive_absolute(OUT)
	var p:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(LAMPS+"/plan.json"))
	check(p.failures==0 and p.formal_sha256==FileAccess.get_sha256(FORMAL),"latest residential/lamp candidate")
	if failed:quit(1);return
	var d=Doc.new();d.records=p.records;d.map_meta=p.metadata;d._next=330000
	var original:Array=d.records.duplicate(true);var metadata:Dictionary=d.map_meta.duplicate(true);d.checkpoint_recovery()
	var source:Dictionary=d.map_meta.building_instances[SAMPLE]
	var members:Array=d.records.filter(func(r):return r.get("building",{}).get("id")==SAMPLE)
	var target:=Vector3(304,0,199);var yaw:=45.
	var motion=preload("res://scripts/world_editor/building_motion.gd").new()
	var proposal:Dictionary=motion.proposal([{"id":SAMPLE,"value":source,"records":members}],target-Blueprint.vec(source.position),Basis(Vector3.UP,deg_to_rad(yaw-source.yaw)),Blueprint.vec(source.position))
	check(proposal.ok,"shared frozen residence transform")
	var candidate:Dictionary=proposal.plans[0];var bounds:=Geometry.bounds(candidate.records)
	var blocked:Array=[]
	for obstacle:Dictionary in d.records:
		if not obstacle.has("building") and not obstacle.has("road_mesh") and not obstacle.has("bridge_mesh") and obstacle.get("kind")!="asset":continue
		if not bounds.intersects(Geometry.bounds([obstacle])):continue
		if Foot.batches_overlap(candidate.occupancy,Foot.record_shapes(obstacle)):blocked.append(obstacle.uuid)
	check(blocked.is_empty(),"infill clear of roads, houses, tree and laundry: "+str(blocked))
	check(not Foot.batches_overlap(candidate.occupancy,preload("res://scripts/world3d/planning_zones.gd").obstacles(d.map_meta)),"infill outside reserved areas")
	for point:Vector3 in [target,target+Vector3(6,0,6),target+Vector3(-6,0,-6),target+Vector3(6,0,-6),target+Vector3(-6,0,6)]:
		check(absf(ground_at(d.records,point))<.08,"infill supported on flat bank")
	if failed:quit(1);return
	var value:Dictionary=candidate.value;value.parts={};value.signatures={}
	for r:Dictionary in candidate.records:
		r.uuid="obj_%d"%d._next;d._next+=1;r.building.id=NEW_HOME;r.editor_group=NEW_HOME;r.editor_group_name="河岸居民房 · 晾衣院后"
		value.parts[r.building.part]=r.uuid;value.signatures[r.building.part]=Blueprint.geometry_signature(r);d.records.append(r)
	d.map_meta.building_instances[NEW_HOME]=value
	var lamp:Dictionary=d._find("obj_200932").duplicate(true)
	var basis:=Basis(Vector3.UP,deg_to_rad(yaw));var old_basis:=Basis(Vector3.UP,deg_to_rad(source.yaw))
	lamp.uuid="obj_%d"%d._next;d._next+=1;lamp.position=Blueprint.arr(target+basis*(old_basis.inverse()*(Blueprint.vec(lamp.position)-Blueprint.vec(source.position))));lamp.rotation=[0,yaw,0]
	lamp.editor_group="group_bridge_infill_lamp";d.records.append(lamp)
	p.lamps.append({"id":lamp.uuid,"house":NEW_HOME,"position":lamp.position})
	p.houses.append({"id":NEW_HOME,"source":SAMPLE,"position":value.position,"yaw":value.yaw,"floors":1,"window_style":value.parameters.window_style,"use":"居民住宅","edge":0,"rear":true,"road_point":[293,0,192]})
	check(Blueprint.valid_ownership(d.map_meta,d.records),"new residence retains floor and fixture ownership")
	for r:Dictionary in original:
		if not equivalent(r,d._find(r.uuid)):check(false,"existing record changed "+r.uuid)
	var final:Array=d.records.duplicate(true);var final_meta:Dictionary=d.map_meta.duplicate(true)
	check(d.undo() and equivalent(d.records,original) and equivalent(d.map_meta,metadata),"infill undo")
	check(d.redo() and equivalent(d.records,final) and equivalent(d.map_meta,final_meta),"infill redo")
	p.records=d.records;p.metadata=d.map_meta;p.next=d._next;p.failures=failed;p.new_home=NEW_HOME
	FileAccess.open(OUT+"/plan.json",FileAccess.WRITE).store_string(JSON.stringify(p))
	print("RIVERSIDE_INFILL failures=",failed," components=",candidate.records.size());quit(failed)
