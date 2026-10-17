extends "res://tools/apply_axel_reference_layout.gd"
## Replace explicitly reviewed assets using ordinary delete/place operations.
## Keep the previous layout transaction and all unrelated records unchanged.
var replacement_entry:Dictionary={}
var removed_ids:Array=[]
func before_placements(recipe:Dictionary)->void:
	replacement_entry=editor._doc.recovery_snapshot()
	report.scope="S12 reviewed asset replacement within the accepted exterior layout"
	report.executed_sources={}
	for path:String in ["res://tools/apply_axel_reference_asset_replacement.gd","res://tools/apply_axel_reference_layout.gd"]:
		report.executed_sources[path]=FileAccess.get_sha256(path)
	check(report.has("root_source_sha256"),"replacement retains full native authoring ancestry")
	for row:Dictionary in recipe.get("replacements",[]):
		var record:Dictionary=editor._doc._find(row.id)
		check(not record.is_empty() and record.get("asset_path","")==row.old_asset and FileAccess.get_sha256(row.old_asset)==row.old_sha256,"exact old asset instance "+str(row.id))
		check(FileAccess.get_sha256(row.review.path)==row.review.sha256,"exact replacement model review")
		if failed:return
		await operation("select_objects",{"ids":[row.id]})
		await operation("delete_selection",{})
		check(editor._doc._find(row.id).is_empty(),"old instance removed by native editor")
		removed_ids.append(row.id)
		report.placements=report.placements.filter(func(p):return p.id!=row.id)
		if not report.deleted_records.has(row.id):report.deleted_records.append(row.id)
		report.new_records.erase(row.id)
		report.changed_records.erase(row.id)
func after_placements(recipe:Dictionary)->void:
	await super.after_placements(recipe)
	if failed:return
	var old_ids:Dictionary={};var permitted_new:Dictionary={}
	for row:Dictionary in report.placements:permitted_new[row.id]=true
	for row:Dictionary in replacement_entry.records:
		old_ids[row.uuid]=true
		if removed_ids.has(row.uuid):continue
		check(City.token(row)==City.token(editor._doc._find(row.uuid)),"unaffected replacement-stage instance "+str(row.uuid))
	for row:Dictionary in editor._doc.records:
		if old_ids.has(row.uuid):continue
		check(permitted_new.has(row.uuid),"replacement new instance has explicit placement ownership")
		if not report.new_records.has(row.uuid):report.new_records.append(row.uuid)
	check(City.token(replacement_entry.map_meta)==City.token(editor._doc.map_meta),"all layout metadata preserved during source replacement")
