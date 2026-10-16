extends "res://tools/propose_axel_functional_grass.gd"
## Read-only final Batch/Plan/Fit and exact bearing review; no map save or GPU.
func run()->void:
	output=OUT+"/functional_building_support_final_review.json"
	grass_moves_path=OUT+"/functional_building_grass_proposal.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--expected-sha="):expected_sha=arg.trim_prefix("--expected-sha=")
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	prepare_inputs()
	check(expected_sha.length()==64 and FileAccess.get_sha256(target)==expected_sha,"exact current candidate pin")
	if stop():return
	var actual_input_sha:=FileAccess.get_sha256(target)
	var doc=Doc.open_file(target);check(doc!=null,"native read-only candidate opens")
	if stop():return
	before=doc.recovery_snapshot();editor=Context.new();editor._doc=doc
	report.input_sha256=expected_sha;report.map=target;report.read_only=true
	report.proposal={"guardhouse_origin_y":7.37,"guardhouse_grading_target_y":sources.guardhouse.site.grading.target_height,"site_file_not_changed":true}
	sources.guardhouse.site.position[1]=7.37
	for move:Dictionary in grass_plan.moves:
		var record:Dictionary=doc._find(move.id)
		check(City.token(record)==move.before_token,"pinned old grass record "+str(move.id))
		record.position=move.position.duplicate()
		check(City.token(record)==move.after_token,"private grass proposal exact target "+str(move.id))
	if stop():return
	terrain_cache(doc.records);add_buildings();prepare_ground()
	if stop():return
	prepare_roads()
	if stop():return
	var ids:Array=proposed_building_records.map(func(r):return r.uuid)
	doc.records.append_array(proposed_building_records)
	report.road_contacts=[];report.building_envelopes=[]
	for i:int in KEYS.size():
		var key:String=KEYS[i];var record:Dictionary=proposed_building_records[i]
		var full:=complete_source_shape(key,record);var pieces:=part_shapes(key,record)
		verify_space(key,record,ids)
		var hits:Array=[]
		for road:Dictionary in proposed_roads:
			var shapes:=road_shapes(road)
			if not Foot.batches_overlap([full],shapes):continue
			for piece:Dictionary in pieces:
				if Foot.batches_overlap([piece],shapes):hits.append({"road":road.get("uuid",road.road_source),"part":piece.part})
		check(hits.is_empty(),"actual final road and kerb clear full source parts/door sweeps "+key)
		report.road_contacts.append({"key":key,"hits":hits})
		report.building_envelopes.append({"key":key,"position":record.position,"rotation":record.rotation,"source_sha256":sources[key].source_sha256,"hinge_sweep_envelopes":hinge_envelopes(key,record),"world_min":City.xyz(full.bounds.position),"world_max":City.xyz(full.bounds.end)})
	for row:Dictionary in report.support:
		row.minimum_embed_m=float(row.terrain.min)-float(row.base_y)
		row.maximum_embed_m=float(row.terrain.max)-float(row.base_y)
	for row:Dictionary in report.outdoor_access:
		row.threshold_above_exterior_ground_m=float(row.threshold[1])-float(row.ground_y)
		var endpoint:Array=row.access_endpoint_xz;var endpoint_ground:=ground(Vector2(endpoint[0],endpoint[1]))
		row.path_endpoint_ground_y=endpoint_ground
		row.threshold_above_path_surface_m=float(row.threshold[1])-endpoint_ground-float(report.road_geometry.settings.lift)
	check(FileAccess.get_sha256(target)==actual_input_sha,"candidate bytes untouched")
	verify_live_building_inputs()
	report.phase="read_only_final_support_and_clearance_complete";report.saved=false
	report.limits=["Actual native terrain Batch and road Plan/Fit in private memory; no map save or GPU.","All three actual source ground-bearing polygons were clipped against final terrain triangles; outdoor runtime remains pending.","Only guard model origin is lowered; its terrain grading, XZ, rotation and published model remain unchanged."]
	persist();print("FUNCTIONAL_SUPPORT_FINAL ",JSON.stringify({"failures":failed,"support":report.support,"access":report.outdoor_access,"road_contacts":report.road_contacts}));editor.free();quit(0 if failed==0 else 1)
