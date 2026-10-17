extends "res://tools/apply_axel_reference_layout.gd"
## Correct an authored gate frontage through native transforms and road operations.
var entry_snapshot:Dictionary={}
var permitted:Dictionary={}
func before_placements(recipe:Dictionary)->void:
	entry_snapshot=editor._doc.recovery_snapshot()
	report.scope="S12 gate parallel to courtyard frontage and river-facing house wall; connecting walls and exterior paths only"
	report.executed_sources={}
	for path:String in ["res://tools/apply_axel_s12_gate_alignment.gd","res://tools/apply_axel_reference_layout.gd"]:report.executed_sources[path]=FileAccess.get_sha256(path)
	for row:Dictionary in recipe.placements:
		if row.has("id"):permitted[row.id]=true
func after_placements(recipe:Dictionary)->void:
	for row:Dictionary in report.placements:permitted[row.id]=true
	var layout:=await operation("get_city_layout",{})
	var roads:Dictionary=recipe.road_request.duplicate(true)
	roads.expected_token=layout.road_token
	for node:Dictionary in roads.get("nodes",[]):node.position[1]=Props.ground(editor._doc,City.vec(node.position))
	var changed:=await operation("update_road_graph",roads)
	check(changed.get("ok",false),"native courtyard path update succeeds")
	if failed:return
	await super.after_placements(recipe)
	if failed:return
	var doc=editor._doc
	var gate:Dictionary=doc._find("obj_1504")
	check(absf(gate.rotation[1])<.001 and absf(gate.position[2]-115.03)<.001,"arch spans X, parallel to front wall and river-facing house wall")
	var front:AABB=Foot.record_shape(doc._find("obj_1449")).bounds
	check(absf(front.end.x-341.745)<.01,"front wall joins left gate plinth without crossing the opening")
	var side:AABB=Foot.record_shape(doc._find("obj_1502")).bounds
	check(absf(side.end.z-114.755)<.01,"courtyard return joins back of right gate plinth")
	report.changed_records=[];report.deleted_records=[];report.new_records=[]
	var old_ids:Dictionary={}
	for old:Dictionary in entry_snapshot.records:
		old_ids[old.uuid]=true
		var now:Dictionary=doc._find(old.uuid)
		if City.token(old)==City.token(now):continue
		check(permitted.has(old.uuid) or old.has("road_mesh"),"change limited to gate frontage or native road derivation "+str(old.uuid))
		if now.is_empty():report.deleted_records.append(old.uuid)
		else:report.changed_records.append(old.uuid)
	for row:Dictionary in doc.records:
		if old_ids.has(row.uuid):continue
		check(permitted.has(row.uuid) or row.has("road_mesh"),"new record belongs to scoped frontage operation "+str(row.uuid))
		report.new_records.append(row.uuid)
	var old_meta:Dictionary=entry_snapshot.map_meta.duplicate(true);var new_meta:Dictionary=doc.map_meta.duplicate(true)
	for meta:Dictionary in [old_meta,new_meta]:
		meta.editor_layout.erase("roads");meta.editor_layout.erase("road_surface")
	check(City.token(old_meta)==City.token(new_meta),"all metadata outside local road authoring unchanged")
