extends "res://tools/apply_axel_reference_layout.gd"
## S2 instance-only refinement; keep S1 and S12 under their existing ownership.
var baseline:Dictionary={}
func before_placements(recipe:Dictionary)->void:
	report.scene_id="S2"
	report.scope="S2 pole, textile and lamp alignment; all houses, S1, S12, roads and terrain unchanged"
	check(FileAccess.get_sha256(recipe.root_source.path)==recipe.root_source.sha256,"formal revision unchanged")
	for witness:Dictionary in recipe.art_evidence:
		check(FileAccess.get_sha256(witness.path)==witness.sha256,"exact completed formal asset delivery")
	if failed:return
	baseline=Doc.open_file(recipe.root_source.path).recovery_snapshot()
	report.root_source_sha256=recipe.root_source.sha256
	var left:=Vector3(365,0,266)
	left.y=Props.ground(editor._doc,left)+6.433398-.2
	var right:Vector3=City.vec(editor._doc._find("obj_790").position)+Vector3(0,6.433398-.2,0)
	var delta:=right-left
	var horizontal:=Vector2(delta.x,delta.z).length()
	for row:Dictionary in recipe.placements:
		if row.id!="obj_1538":continue
		row.point=City.xyz((left+right)*.5)
		row.rotation=[0,rad_to_deg(atan2(-delta.z,delta.x)),rad_to_deg(atan2(delta.y,horizontal))]
		var uniform:=delta.length()/8.
		row.scale=[uniform,uniform,uniform]
	report.festoon_anchors={"left":City.xyz(left),"right":City.xyz(right)}
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
		check(allowed.has(old.uuid),"change belongs to explicit S2 instance "+str(old.uuid))
		if now.is_empty():report.deleted_records.append(old.uuid)
		else:report.changed_records.append(old.uuid)
	for row:Dictionary in editor._doc.records:
		if previous.has(row.uuid):continue
		check(allowed.has(row.uuid),"new instance belongs to S2 "+str(row.uuid))
		report.new_records.append(row.uuid)
	check(City.token(baseline.map_meta)==City.token(editor._doc.map_meta),"all original houses, roads, terrain, spawn and metadata identical")
