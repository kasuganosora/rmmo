extends "res://tools/probe_market_fortification_terrain.gd"
## Candidate geometry proposal only; the source plan and map remain untouched.
func finish_probe()->void:
	receipt.input_unchanged=FileAccess.get_sha256(MAP)==PIN
	FileAccess.open(OUT+"/market_wall_clearance_fix_probe.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"\t"))
	print("MARKET_WALL_CLEARANCE ",JSON.stringify(receipt));quit(0)
func run()->void:
	if FileAccess.get_sha256(MAP)!=PIN:receipt.error="Candidate revision changed";finish_probe();return
	var doc=Doc.open_file(MAP)
	if doc==null:receipt.error="Native candidate open failed";finish_probe();return
	var settings:Dictionary=City.resolve(doc.map_meta).fortifications[0].settings.duplicate(true)
	var built:=Plan.new().build(settings)
	if not built.ok:receipt.error=built;finish_probe();return
	var original:Array=doc.records.filter(func(r):return r.has("terrain_mesh"))
	var prepared:=Content.prepare(doc)
	if not prepared.ok:receipt.error=prepared;finish_probe();return
	# The original house bearing rectangle moves exactly one 2 m terrain cell.
	prepared.terrain_request.strokes[0].points[0][1]+=2.
	var terrain:Array=original.duplicate(true)
	for stroke:Dictionary in prepared.terrain_request.strokes:
		var seed:Dictionary=terrain.filter(func(r):return r.uuid==stroke.id)[0]
		var batch:=Batch.prepare(terrain,seed,stroke)
		if not batch.ok:receipt.error=batch;finish_probe();return
		for entry:Dictionary in batch.entries:
			for i in terrain.size():
				if terrain[i].uuid==entry.record.uuid:terrain[i]=entry.record;break
		receipt.strokes.append({"stroke":stroke,"changed_cells":batch.cells.size()})
	var baseline:=Fit.fit(built.records,original,settings.base_height,settings.foundation,settings)
	var fitted:=Fit.fit(built.records,terrain,settings.base_height,settings.foundation,settings)
	receipt.baseline_ok=baseline.ok;receipt.final_ok=fitted.ok;receipt.error=fitted.get("error","")
	if not fitted.ok:receipt.first_failure=diagnose_fit(built.records,terrain,settings.base_height,settings.foundation,settings)
	if baseline.ok and fitted.ok:
		receipt.fortification_fit_unchanged=City.token(baseline.records)==City.token(fitted.records)
		receipt.changed_fortification_parts=[]
		for i in baseline.records.size():
			if City.token(baseline.records[i])!=City.token(fitted.records[i]):receipt.changed_fortification_parts.append(baseline.records[i].fortification.part)
	receipt.proposal={"house":"north_market_home_1","from_xz":[120.2,60.],"to_xz":[120.2,62.],"blend_margin_unchanged":4.,"original_lane_node_unchanged":true}
	finish_probe()
