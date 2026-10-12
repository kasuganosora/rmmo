extends "res://tools/residential_bridge_street.gd"
const LAMP_OUT="D:/code/rmmo_runtime/review_artifacts/bridge_residential_lamps_20261007"
const HOMES_OUT="D:/code/rmmo_runtime/review_artifacts/bridge_residential_street_20261007"
func run()->void:
	OUT=LAMP_OUT
	if "--publish" in OS.get_cmdline_user_args():await super.run();return
	DirAccess.make_dir_recursive_absolute(OUT)
	var published:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(HOMES_OUT+"/published.json"))
	check(published.failures==0 and published.sha256==FileAccess.get_sha256(FORMAL),"latest residential map available")
	if failed:quit(1);return
	var p:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(HOMES_OUT+"/plan.json"))
	var extra:Dictionary=Doc.authoritative_extras(FORMAL).extras
	var d=Doc.new();d.records=extra.rmmo_records;d.map_meta=extra.duplicate(true);d.map_meta.erase("rmmo_records");d._next=int(p.next)
	var original:Array=d.records.duplicate(true);var metadata:Dictionary=d.map_meta.duplicate(true);d.checkpoint_recovery()
	var lamps:Array=d.records.filter(func(r):return r.get("label")=="门旁暖光小壁灯")
	var changed:Array=[];var placements:Array=[]
	for house:Dictionary in p.houses:
		var h:Dictionary=d.map_meta.building_instances[house.id];var at:=Blueprint.vec(h.position);var basis:=Basis(Vector3.UP,deg_to_rad(h.yaw))
		var expected:=at+basis*Vector3(1.8,2.35,-h.parameters.depth/2-.08)
		var candidates:Array=lamps.filter(func(r):return Blueprint.vec(r.position).distance_to(expected)<.02)
		check(candidates.size()==1,"existing facade lamp identified "+house.id)
		if candidates.size()!=1:quit(1);return
		var lamp:Dictionary=candidates[0];check(not lamp.get("editor_locked",false),"lamp editable "+lamp.uuid)
		var door:Dictionary=d.records.filter(func(r):return r.get("building",{}).get("id")==house.id and r.get("fixture",{}).get("id")=="f0/north/entrance/door")[0]
		var door_local:=basis.inverse()*(Blueprint.vec(door.position)-at);var local:=basis.inverse()*(Blueprint.vec(lamp.position)-at)
		local.x=door_local.x+1.25;lamp.position=Blueprint.arr(at+basis*local);changed.append(lamp.uuid)
		# Inner side of the doorway, outside its opening and stone reveal. Existing
		# mounting depth, height, orientation and warm-light metadata stay intact.
		var gap:float=local.x-.165-(door_local.x+h.parameters.door_width/2+.12)
		check(gap>.15,"lamp clear of door trim "+lamp.uuid)
		placements.append({"id":lamp.uuid,"house":house.id,"position":lamp.position,"door_side_gap":gap})
	check(changed.size()==26,"all 26 facade lamps moved beside residential doors")
	for r:Dictionary in original:
		if r.uuid not in changed and not equivalent(r,d._find(r.uuid)):check(false,"unrelated record changed "+r.uuid)
	check(equivalent(d.map_meta,metadata),"building and road metadata preserved")
	var final:Array=d.records.duplicate(true)
	check(d.undo() and equivalent(d.records,original),"lamp placement batch undo")
	check(d.redo() and equivalent(d.records,final),"lamp placement batch redo")
	p.records=d.records;p.metadata=d.map_meta;p.next=d._next;p.failures=failed;p.formal_sha256=published.sha256;p.lamps=placements;p.changed=changed
	FileAccess.open(OUT+"/plan.json",FileAccess.WRITE).store_string(JSON.stringify(p))
	print("RESIDENTIAL_LAMPS failures=",failed);quit(failed)
