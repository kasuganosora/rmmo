extends "res://tools/probe_axel_fortification_recipe.gd"
## Pure native data probe; no scene rendering, no map writes.
const Content=preload("res://tools/axel_market_layout_content.gd")
const MAP="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf"
const PIN="1632fecd683cbdccbb1cea8c0862b555175c7552c4ace14f1bf34f320db71ef2"
var receipt:Dictionary={"input_sha256":PIN,"read_only":true,"strokes":[]}
func finish_probe()->void:
	receipt.input_unchanged=FileAccess.get_sha256(MAP)==PIN
	FileAccess.open(OUT+"/market_fortification_terrain_probe.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"\t"))
	print("MARKET_FORT_TERRAIN ",JSON.stringify(receipt));quit(0)
func test_fit(records:Array,terrains:Array,settings:Dictionary)->Dictionary:
	var fitted:=Fit.fit(records,terrains,settings.base_height,settings.foundation,settings)
	var result:={"ok":fitted.ok,"error":fitted.get("error","")}
	if not fitted.ok:result.first_failure=diagnose_fit(records,terrains,settings.base_height,settings.foundation,settings)
	return result
func run()->void:
	if FileAccess.get_sha256(MAP)!=PIN:receipt.error="Candidate revision changed";finish_probe();return
	var doc=Doc.open_file(MAP)
	if doc==null:receipt.error="Native candidate open failed";finish_probe();return
	var regions:Array=City.resolve(doc.map_meta).fortifications
	var settings:Dictionary=regions[0].settings.duplicate(true)
	var built:=Plan.new().build(settings)
	if not built.ok:receipt.error=built;finish_probe();return
	var original:Array=doc.records.filter(func(r):return r.has("terrain_mesh"))
	receipt.baseline=test_fit(built.records,original,settings)
	print("BASELINE ",JSON.stringify(receipt.baseline))
	if not receipt.baseline.ok:finish_probe();return
	var prepared:=Content.prepare(doc)
	if not prepared.ok:receipt.error=prepared;finish_probe();return
	var terrain:Array=original.duplicate(true);var index:=0
	for stroke:Dictionary in prepared.terrain_request.strokes:
		var seed:Dictionary=terrain.filter(func(r):return r.uuid==stroke.id)[0]
		var batch:=Batch.prepare(terrain,seed,stroke)
		if not batch.ok:receipt.error=batch;finish_probe();return
		for entry:Dictionary in batch.entries:
			for i in terrain.size():
				if terrain[i].uuid==entry.record.uuid:terrain[i]=entry.record;break
		var row:={"index":index,"stroke":stroke,"changed_cells":batch.cells.size(),"fit":test_fit(built.records,terrain,settings)}
		receipt.strokes.append(row);print("STROKE ",JSON.stringify(row));index+=1
	receipt.final=receipt.strokes[-1].fit
	finish_probe()
