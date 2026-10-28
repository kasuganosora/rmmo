extends SceneTree
## Headless planning/result contracts; no renderer, real compilation or official writes.
const Migration=preload("res://tools/native_asset_migration.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
var directory:=""
var checks:=0
var failures:Array[String]=[]

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func put(path:String,value:Variant)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(value if value is String else JSON.stringify(value));file.close()
func ok_result()->Dictionary:
	return {"ok":true,"bytes":16,"reused":false,"footprint":{"ok":true,"reused":false},"native_ready":true,"bounds":{"ok":true},"building":{"ok":true,"present":false}}
func finish(plan_:Dictionary,rows:Array,bounds:bool=false,building:bool=false)->Dictionary:
	var report:=Migration.begin_report(plan_,bounds,building)
	for i:int in rows.size():Migration.record_result(report,plan_.models[mini(i,plan_.models.size()-1)].path,rows[i])
	return Migration.finish_report(report)

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):directory=arg.trim_prefix("--output=").replace("\\","/")
	if directory.is_empty() or not directory.is_absolute_path() or directory.begins_with(ProjectSettings.globalize_path("res://")):
		push_error("external --output required");quit(2);return
	var library:=directory.path_join("pack/assets/library.json")
	var base:=library.get_base_dir();var prefab:=base.path_join("prefabs/entry.json")
	for name:String in ["plain","bridge","fortification","tile"]:put(base.path_join(name+".glb"),"fixture-only: not compiled")
	put(prefab,{"format":"rmmo_prefab","version":1,"records":[
		{"kind":"asset","asset_path":"plain.glb"},
		{"kind":"asset","asset_path":"bridge.glb","bridge_mesh":{}},
		{"kind":"box","fortification_art":{"asset_path":base.path_join("fortification.glb")}},
		{"kind":"box","tile3d":{"options":{"kit":{"pieces":{"0":"tile.glb","1":"plain.glb"}}}}},
		{"kind":"asset","asset_path":"removed-provenance.glb","house_prefab":{}}
	]})
	put(library,[{"asset_path":"plain.glb"},{"prefab_path":"prefabs/entry.json"},{"prefab_path":"prefabs/entry.json"}])
	var before:=FileAccess.get_sha256(library)
	var plan_:=Migration.plan([], [library,library], [prefab], [], directory)
	check(plan_.ok and plan_.closure_complete and plan_.models.size()==4,"whole library/prefab closure includes bridge, fortification and tile kit")
	check(plan_.prefab_count==1 and plan_.inputs.size()==2,"repeated libraries/prefabs are read once")
	check(plan_.ignored_derived_provenance.size()==1,"frozen mesh provenance is reported without demanding removed GLB")
	check(plan_.models.any(func(row:Dictionary):return row.path==base.path_join("plain.glb") and row.origins.size()==3),"path dedup retains origins instead of dropping prefab dependencies")
	check(plan_.models.all(func(row:Dictionary):return not row.path.contains("/prefabs/plain.glb")),"prefab relative models resolve against library parent")
	check(before==FileAccess.get_sha256(library) and not DirAccess.dir_exists_absolute(directory.path_join("cache")),"planning leaves source library and native storage untouched")
	var product_source:=base.path_join("plain.glb")
	check(Migration.product_plan(product_source,directory).action=="build","missing native index receives a first import")
	var payload:="fixture metadata only; never loaded as a PackedScene"
	var payload_sha:=payload.sha256_text()
	var payload_path:=Compiled.directory(directory).path_join(payload_sha+".scn")
	var index_path:=Compiled.index_path(product_source,directory)
	put(payload_path,payload)
	put(index_path,{"version":Compiled.VERSION,"source_sha":FileAccess.get_sha256(product_source),"payload_sha":payload_sha,"bytes":payload.to_utf8_buffer().size(),"generator":"older-published-generator"})
	var index_before:=FileAccess.get_sha256(index_path)
	var product_action:=Migration.product_plan(product_source,directory)
	check(product_action.ok and product_action.action=="preserve" and product_action.identity.generator=="older-published-generator","planning preserves older published generator rather than rebuilding")
	check(FileAccess.get_sha256(index_path)==index_before and FileAccess.get_sha256(payload_path)==payload_sha,"preserve planning changes neither index nor product bytes")
	put(product_source,"changed source of the same logical model")
	product_action=Migration.product_plan(product_source,directory)
	check(not product_action.ok and product_action.reason.begins_with("reimport_required:"),"source changes require explicit reimport")
	check(Migration.product_plan(product_source,directory,true).action=="build","explicit reimport permits changed source build")
	check(FileAccess.get_sha256(index_path)==index_before,"changed-source failure keeps previous publication")
	put(product_source,"fixture-only: not compiled")
	put(payload_path,payload+"bad length")
	product_action=Migration.product_plan(product_source,directory)
	check(not product_action.ok and product_action.reason.contains("published_product_invalid_or_missing"),"invalid existing product cannot silently become a fresh import")
	put(index_path,"{broken")
	check(not Migration.product_plan(product_source,directory).ok,"malformed existing index fails preserve planning")
	check(Migration.product_plan(product_source,directory,true).action=="build","explicit reimport permits repair of a broken publication")
	var all_rows:Array=[]
	for row:Dictionary in plan_.models:all_rows.append(ok_result())
	var report:=finish(plan_,all_rows,true,true)
	check(report.ok and report.built==4 and report.footprints_built==4 and report.closure_complete,"complete successful migration reports every product and requested descriptor")
	check(not finish(plan_,all_rows.slice(0,3)).ok,"missing compiler result cannot pass closure")
	var duplicate:=all_rows.duplicate(true);duplicate.append(ok_result())
	check(not finish(plan_,duplicate).ok,"duplicate result cannot pretend full coverage")
	for failure:String in ["unsupported","footprint","native","bounds","building"]:
		var rows:=all_rows.duplicate(true)
		match failure:
			"unsupported":rows[0]={"ok":false,"reason":"unsupported:animations"}
			"footprint":rows[0].footprint={"ok":false,"reason":"measurement_failed"}
			"native":rows[0].native_ready=false
			"bounds":rows[0].bounds={"ok":false,"reason":"source_bounds_unknown"}
			"building":rows[0].building={"ok":false,"reason":"invalid_native_components"}
		report=finish(plan_,rows,true,true)
		check(not report.ok and report.failures==1,"migration fails on "+failure)
		if failure=="unsupported":check(report.unsupported==1 and report.skipped==0,"unsupported is an explicit failure, not an accepted skip")
		if failure=="footprint":check(report.footprints_failed==1,"footprint failure remains separately counted")
	var one:=Migration.plan([base.path_join("plain.glb")],[],[],[],directory)
	var missing_fields:=ok_result();missing_fields.erase("native_ready")
	check(not finish(one,[missing_fields]).ok,"compiler success without native publication proof fails")
	put(library,[{"asset_path":"plain.glb"},{"asset_path":"missing.glb"}])
	check(not finish(plan_,all_rows).ok,"library mutation after planning fails closure identity")
	var missing:=Migration.plan([], [library], [], [], directory)
	check(not missing.ok and missing.errors.size()==1 and missing.models.size()==1,"missing dependency fails plan but retains exact diagnostics")
	put(library,[{"asset_path":"../../../../escape.glb"}])
	check(not Migration.plan([], [library], [], [], directory).ok,"out-of-root dependency rejected before model read")
	put(library,[{"prefab_path":"prefabs/entry.json"}])
	put(prefab,{"format":"rmmo_prefab","version":1,"records":[{"kind":"asset","prefab_path":"entry.json","asset_path":"plain.glb"}]})
	check(not Migration.plan([], [library], [], [], directory).ok,"unsupported nested prefab cannot disappear from closure")
	put(prefab,{"format":"rmmo_prefab","version":1,"records":[{"kind":"box","fortification_art":{"asset_path":"fortification.glb"}}]})
	check(not Migration.plan([], [library], [], [], directory).ok,"relative fortification is rejected rather than inventing consumer resolution")
	put(prefab,"{broken")
	check(not Migration.plan([], [library], [], [], directory).ok,"malformed prefab fails plan")
	var map_records:Array=[{"kind":"asset","asset_path":base.path_join("bridge.glb"),"bridge_mesh":{}},{"kind":"asset","asset_path":"missing.glb","house_prefab":{}}]
	var map_plan:=Migration.plan([],[],[],map_records,directory,directory.path_join("map.gltf"))
	check(map_plan.ok and map_plan.models.size()==1 and map_plan.ignored_derived_provenance.size()==1,"map mode includes bridge consumer and excludes frozen source provenance")
	print("NATIVE_ASSET_MIGRATION ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
