extends "res://tools/apply_axel_reference_layout.gd"
## Native S2 assembly; dependency handoff and exact formal root are required.
var baseline:Dictionary={}
func before_placements(recipe:Dictionary)->void:
	report.scene_id="S2"
	report.scope="S2 missing props and textile variants; preserve all residential buildings, S1, S12, terrain and roads"
	check(FileAccess.get_sha256(recipe.root_source.path)==recipe.root_source.sha256,"formal root unchanged before S2 assembly")
	check(not recipe.get("art_evidence",[]).is_empty(),"accepted model review evidence is required before candidate assembly")
	for witness:Dictionary in recipe.get("art_evidence",[]):
		check(FileAccess.get_sha256(witness.path)==witness.sha256,"exact accepted model review "+str(witness.path))
	report.formal_library_validation_pending_at_authoring=recipe.get("formal_library_validation_pending_at_authoring",false)
	if failed:return
	baseline=Doc.open_file(recipe.root_source.path).recovery_snapshot()
	report.root_source_sha256=recipe.root_source.sha256
	await operation("select_objects",{"ids":["obj_851","obj_852"]})
	await operation("delete_selection",{})
	check(editor._doc._find("obj_851").is_empty() and editor._doc._find("obj_852").is_empty(),"incorrect S1 long pennants removed only from S2")
func after_placements(recipe:Dictionary)->void:
	await super.after_placements(recipe)
	if failed:return
	var allowed:Dictionary={"obj_851":true,"obj_852":true}
	for row:Dictionary in report.placements:allowed[row.id]=true
	report.changed_records=[];report.deleted_records=[];report.new_records=[]
	var previous:Dictionary={}
	for old:Dictionary in baseline.records:
		previous[old.uuid]=true
		var now:Dictionary=editor._doc._find(old.uuid)
		if City.token(old)==City.token(now):continue
		check(allowed.has(old.uuid),"change restricted to S2 instances "+str(old.uuid))
		if now.is_empty():report.deleted_records.append(old.uuid)
		else:report.changed_records.append(old.uuid)
	for row:Dictionary in editor._doc.records:
		if previous.has(row.uuid):continue
		check(allowed.has(row.uuid),"new object has explicit S2 ownership "+str(row.uuid))
		report.new_records.append(row.uuid)
	check(City.token(baseline.map_meta)==City.token(editor._doc.map_meta),"S1, S12, roads, spawn, terrain and building metadata unchanged")
