extends "res://tools/correct_bridge_spire_courtyard.gd"
const SET_OUT="D:/code/rmmo_runtime/review_artifacts/bridge_frontage_setback_20261007"
func _initialize()->void:OUT=SET_OUT;run.call_deferred()
func run()->void:
	if "--publish-correction" in OS.get_cmdline_user_args():super.run();return
	DirAccess.make_dir_recursive_absolute(OUT)
	var baseline:=FileAccess.get_sha256(FORMAL)
	var extra:Dictionary=Doc.authoritative_extras(FORMAL).extras
	doc=Doc.new();doc.records=extra.rmmo_records;doc.map_meta=extra.duplicate(true);doc.map_meta.erase("rmmo_records")
	var original:Array=doc.records.duplicate(true);var previous:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FIX_OUT+"/plan.json"))
	doc._next=int(previous.next)
	var h:Dictionary=doc.map_meta.building_instances[HOUSE];var basis:=Basis(Vector3.UP,deg_to_rad(h.yaw));var delta:=basis*Vector3(0,0,3.5)
	var parts:Array=doc.records.filter(func(r):return r.get("building",{}).get("id","")==HOUSE)
	check(parts.all(func(r):return not r.get("editor_locked",false)),"whole house editable")
	doc.checkpoint_recovery()
	var motion=preload("res://scripts/world_editor/building_motion.gd").new()
	var proposal:Dictionary=motion.proposal([{"id":HOUSE,"value":h,"records":parts}],delta,Basis.IDENTITY,Vector3.ZERO)
	check(proposal.ok,"shared rigid building translation")
	if not proposal.ok:quit(1);return
	var replacements:Dictionary={}
	for r:Dictionary in proposal.plans[0].records:replacements[r.uuid]=r;changed.append(r.uuid)
	doc.map_meta.building_instances[HOUSE]=proposal.plans[0].value
	# Move the enclosure, its trees, wall-mounted decorations and planted garden
	# with the house. The street festival post/span retains its reference position.
	var attached:Array=["obj_200909","obj_200910","obj_300019","obj_201011","obj_300002","obj_300003","obj_300004","obj_300005","obj_300006","obj_300007"]
	for p:Dictionary in previous.props:attached.append(p.id)
	for id:String in attached:
		var r:Dictionary=doc._find(id).duplicate(true);check(not r.get("editor_locked",false),"attached prop editable "+id)
		r.position=B.arr(B.vec(r.position)+delta);replacements[id]=r;changed.append(id)
	var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FINAL_OUT+"/result.json"))
	for p:Dictionary in old.props:
		if p.source=="curb":removed.append(p.id)
	check(removed.size()==23,"23 physical roadside kerbs identified")
	for id:String in removed:check(not doc._find(id).get("editor_locked",false),"kerb editable "+id)
	doc.records=doc.records.filter(func(r):return r.uuid not in removed)
	for i in doc.records.size():
		if replacements.has(doc.records[i].uuid):doc.records[i]=replacements[doc.records[i].uuid]
	var final:Array=doc.records
	doc.records=doc.records.filter(func(r):return not replacements.has(r.uuid))
	for r:Dictionary in replacements.values():
		check(free_site(r),"setback clear of roads and neighbouring buildings "+r.uuid)
		if not r.has("building") and r.uuid not in ["obj_200909","obj_200910","obj_300019"]:check(absf(ground(doc,B.vec(r.position)))<.08,"relocated garden grounded "+r.uuid)
	doc.records=final
	for r:Dictionary in original:
		if r.uuid not in changed and r.uuid not in removed:check(equivalent(r,doc._find(r.uuid)),"preserved "+r.uuid) if not equivalent(r,doc._find(r.uuid)) else null
	check(doc.records.filter(func(r):return "路缘边石" in r.get("label","")).is_empty(),"physical edge stones removed")
	var final_copy:Array=doc.records.duplicate(true);var final_meta:Dictionary=doc.map_meta.duplicate(true)
	check(doc.undo() and equivalent(doc.records,original),"setback batch undo")
	check(doc.redo() and equivalent(doc.records,final_copy) and equivalent(doc.map_meta,final_meta),"setback batch redo")
	var props_now:Array=previous.props.duplicate(true)
	for p:Dictionary in props_now:p.position=doc._find(p.id).position
	write_report("plan.json",{"failures":failures,"formal_sha256":baseline,"records":doc.records,"metadata":doc.map_meta,"next":doc._next,"houses":previous.houses,"props":props_now,"changed":changed,"removed":removed,"tower_sites":previous.tower_sites,"gate_x":previous.gate_x,"setback_m":3.5,"bridge_id":previous.bridge_id})
	print("SETBACK_PLAN failures=",failures," moved=",changed.size()," removed=",removed.size());quit(failures)
