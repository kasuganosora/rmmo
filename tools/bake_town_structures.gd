extends "res://tools/place_medieval_town_houses.gd"
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Structures=preload("res://scripts/world3d/structure_prefab.gd")
const Layout=preload("res://scripts/world3d/city_layout.gd")
func run()->void:
	check(FileAccess.get_sha256(SOURCE)==EXPECTED,"formal town unchanged")
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("result.json")))
	check(report.candidate_sha256==FileAccess.get_sha256(CANDIDATE),"staged houses match audit")
	var doc=Doc.open_file(CANDIDATE);check(doc!=null,"load staged town")
	if failures:quit(1);return
	var original:Dictionary={};var fixtures:Dictionary={};var rows:Array=[]
	for r:Dictionary in doc.records:
		if not r.has("fortification") and not r.has("bridge_mesh"):original[r.uuid]=r.duplicate(true)
		if r.has("fortification") and r.has("fixture"):
			var closed:=Transform3D(Basis.from_euler(Frozen.vec(r.rotation)*PI/180),Frozen.vec(r.position))
			var pivot:Vector3=closed*Frozen.vec(r.fixture.pivot)
			fixtures[str([r.fortification.id,r.fixture.id,r.fixture.angle])]={"pivot":pivot,"open":r.fixture.open}
	for region:Dictionary in doc.map_meta.editor_layout.fortifications:
		if region.get("baked",false):continue
		var records:Array=doc.records.filter(func(r):return r.get("fortification",{}).get("id","")==region.settings.id)
		check(region.parts.all(func(p):return Layout.token(doc._find(p.id))==p.signature),"fortification originals unmodified")
		if failures:quit(1);return
		print("BAKING_FORTIFICATION source=",records.size())
		var started:=Time.get_ticks_msec()
		var baked:=preload("res://scripts/world_editor/fortification_tools.gd").freeze(records,region)
		check(baked.ok,"bake exact wall and tower geometry")
		if not baked.ok:print(baked);quit(1);return
		doc.records=doc.records.filter(func(r):return r.get("fortification",{}).get("id","")!=region.settings.id);doc.records.append_array(baked.records)
		rows.append({"type":"fortification","id":region.settings.id,"before":records.size(),"after":baked.records.size(),"bake_ms":Time.get_ticks_msec()-started})
		print("BAKED_FORTIFICATION ",rows[-1])
	for i in doc.records.size():
		var r:Dictionary=doc.records[i]
		if not r.has("bridge_mesh") or r.has("house_prefab"):continue
		var baked:=Structures.bridge(r);check(baked.ok,"bake bridge "+r.uuid)
		if not baked.ok:print(baked);quit(1);return
		doc.records[i]=baked.record;rows.append({"type":"bridge","id":r.uuid,"before":1,"after":1})
	Structures.refresh_bindings(doc.map_meta,doc.records)
	check(original.keys().all(func(id):return doc._find(id)==original[id]),"houses terrain roads reservations unchanged")
	check(doc.records.filter(func(r):return r.has("fortification") or r.has("bridge_mesh")).all(func(r):return r.has("house_prefab") and Frozen.valid(r)),"all structures use serialized immutable meshes")
	var seen:Dictionary={}
	for r:Dictionary in doc.records:
		if not r.has("fortification") or not r.has("fixture"):continue
		var key:=str([r.fortification.id,r.fixture.id,r.fixture.angle]);seen[key]=true
		check(fixtures.has(key) and (Frozen.vec(r.position)+Frozen.vec(r.fixture.pivot)).distance_to(fixtures[key].pivot)<.001 and r.fixture.open==fixtures[key].open,"hinge pivot and open state "+key)
	check(seen.size()==fixtures.size(),"all original gate leaves retained")
	check(doc.validate_save()==OK,"full native validation including bridge bindings")
	if failures:quit(1);return
	print("SAVING_FIXED_TOWN records=",doc.records.size())
	check(doc.save(CANDIDATE)==OK,"atomic candidate save")
	var reopened=Doc.open_file(CANDIDATE)
	check(reopened!=null and equivalent(reopened.records,doc.records) and equivalent(reopened.map_meta,doc.map_meta),"frozen town reopens exactly")
	check(FileAccess.get_sha256(SOURCE)==EXPECTED,"formal town untouched until runtime acceptance")
	report.structure_source_sha256=report.candidate_sha256;report.candidate_sha256=FileAccess.get_sha256(CANDIDATE);report.structures=rows;report.records=doc.records.size();report.failures+=failures
	write_report("result.json",report)
	print("TOWN_STRUCTURES_BAKED failures=",failures);quit(1 if failures else 0)
