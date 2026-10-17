extends "res://tools/apply_axel_reference_layout.gd"
## Add only missing S2 props from the verified library; preserve every existing record.
var original_snapshot:Dictionary={}
func before_placements(_recipe:Dictionary)->void:
	original_snapshot=editor._doc.recovery_snapshot()
	report.scene_id="S2"
	report.scope="S2 existing-library props only; all original houses, S1, S12, roads, terrain and metadata preserved"
func after_placements(recipe:Dictionary)->void:
	await super.after_placements(recipe)
	if failed:return
	var allowed:Dictionary={}
	for row:Dictionary in report.placements:allowed[row.id]=true
	for old:Dictionary in original_snapshot.records:
		check(City.token(old)==City.token(editor._doc._find(old.uuid)),"original record preserved "+str(old.uuid))
	check(City.token(original_snapshot.map_meta)==City.token(editor._doc.map_meta),"all original metadata preserved")
	for row:Dictionary in report.placements:
		if not str(row.key).contains("background_tree"):continue
		var crown:AABB=Foot.record_shape(editor._doc._find(row.id)).bounds.grow(.15)
		for part:Dictionary in original_snapshot.records:
			if not part.has("building"):continue
			check(not crown.intersects(Foot.record_shape(part).bounds),"tree crown clears existing house component "+str(part.uuid))
	report.new_records=allowed.keys();report.changed_records=[];report.deleted_records=[]
