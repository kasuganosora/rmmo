extends "res://tools/apply_axel_reference_layout.gd"
## Interim S10 tree composition while the dedicated frontage is being delivered.
var baseline:Dictionary={}
func before_placements(recipe:Dictionary)->void:
	baseline=editor._doc.recovery_snapshot()
	report.scene_id="S10"
	report.scope="S10 reviewed fruit tree, independent original-scale planters and low root grass; frontage replacement pending"
	var parent:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(recipe.parent_authoring.path))
	report.background_replacement=parent.background_replacement.duplicate(true)
	check(FileAccess.get_sha256(recipe.root_source.path)==recipe.root_source.sha256,"formal map unchanged before tree composition")
	check(FileAccess.get_sha256(recipe.art_receipt.path)==recipe.art_receipt.sha256,"exact published tree receipt")
	if failed:return
	await operation("select_objects",{"ids":["obj_882"]})
	await operation("delete_selection",{})

func after_placements(recipe:Dictionary)->void:
	await super.after_placements(recipe)
	if failed:return
	var allowed:Dictionary={"obj_882":true,"obj_842":true,"obj_843":true}
	for row:Dictionary in report.placements:allowed[row.id]=true
	for old:Dictionary in baseline.records:
		var now:Dictionary=editor._doc._find(old.uuid)
		if City.token(old)==City.token(now):continue
		check(allowed.has(old.uuid),"interim change belongs to S10 tree or two planters "+str(old.uuid))
	check(City.token(baseline.map_meta)==City.token(editor._doc.map_meta),"all metadata and road graph preserved in tree-only stage")
	report.deleted_records.append("obj_882")
	for id:String in ["obj_842","obj_843"]:
		if not report.changed_records.has(id):report.changed_records.append(id)
