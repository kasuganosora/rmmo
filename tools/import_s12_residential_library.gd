extends "res://tools/import_s2_green_post.gd"
## Reuse the normal UI importer and strict publication guards. JSON reload turns
## model_building integers into floats and rounds numeric coordinates; compare
## only that descriptor semantically, without permitting a changed key or text.
func descriptor_equal(a:Variant,b:Variant)->bool:
	if typeof(a) in [TYPE_INT,TYPE_FLOAT] and typeof(b) in [TYPE_INT,TYPE_FLOAT]:
		return is_finite(float(a)) and is_finite(float(b)) and absf(float(a)-float(b))<=1e-12*maxf(1.,maxf(absf(float(a)),absf(float(b))))
	if typeof(a)!=typeof(b):return false
	if a is Dictionary:
		if a.size()!=b.size():return false
		for key:Variant in a:
			if not b.has(key) or not descriptor_equal(a[key],b[key]):return false
		return true
	if a is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not descriptor_equal(a[i],b[i]):return false
		return true
	return a==b

func same_entry(actual:Dictionary,expected:Dictionary)->bool:
	if actual.has("model_building")!=expected.has("model_building"):return false
	if not actual.has("model_building"):return super.same_entry(actual,expected)
	if not descriptor_equal(actual.model_building,expected.model_building):return false
	var a:=actual.duplicate(true);var b:=expected.duplicate(true)
	a.erase("model_building");b.erase("model_building")
	return super.same_entry(a,b)

func validate_resume(folder:String,target:String,matches:Array)->Dictionary:
	# Capacity exhaustion may occur after the source/catalog were atomically
	# imported. Resume only that untouched entry; the main importer below must
	# still rebuild and verify actual native + footprint before naming it.
	var path:String=options["resume-receipt"]
	var prior:=read_dict(path)
	if prior.get("import_result",{}).get("compiled_asset",{}).get("reason")!="cache_capacity":
		return super.validate_resume(folder,target,matches)
	var confined:=Paths.allowed(path,canonical("res://review_artifacts")) or Paths.allowed(path,Paths.external_root().path_join("review_artifacts"))
	if not check(confined and FileAccess.file_exists(path),"confined capacity-failure receipt"):return {}
	if not check(prior.get("ok")==false and prior.get("completed")==false and prior.get("catalog_entries_before") is Array,"incomplete capacity import receipt"):return {}
	if not check(prior.get("id")==options.id and prior.get("source_path")==options.source and prior.get("source_sha256")==options.sha256 and prior.get("catalog_path")==folder.path_join("library.json"),"capacity resume preserves exact model/source/catalog"):return {}
	var imported:Dictionary=prior.import_result
	if not check(imported.get("ok",false) and imported.get("entry") is Dictionary and imported.compiled_asset.get("ok")==false,"source import succeeded but native capacity failed"):return {}
	var entry:Dictionary=imported.entry
	if not check(entry.get("asset_path")==target and imported.get("import_preparation",{}).get("source_sha")==options.sha256 and FileAccess.get_sha256(target)==options.sha256,"capacity resume immutable source intact"):return {}
	if not check(entry.get("label")==str(options.source).get_file().get_basename() and entry.get("category")=="导入模型","capacity resume only original default naming"):return {}
	if not check(not prior.catalog_entries_before.any(func(old):return old is Dictionary and canonical(str(old.get("asset_path","")))==target),"capacity failure originally introduced this target"):return {}
	if not check(matches.size()==1 and same_entry(matches[0],entry),"capacity entry unchanged; independent edits rejected"):return {}
	var proof:String=str(prior.get("review_path",""));var digest:String=str(prior.get("review_sha256",""))
	if not check(proof==options.review and digest==options["review-sha256"] and Compile._sha(digest) and FileAccess.get_sha256(proof)==digest,"same immutable acceptance on capacity resume"):return {}
	guards[path]=FileAccess.get_sha256(path);guards[proof]=digest
	audit.resume={"receipt_path":path,"receipt_sha256":guards[path],"reason":"cache_capacity","entry_before":entry.duplicate(true),"native_must_be_rebuilt_and_verified":true}
	return entry.duplicate(true)

func run()->void:
	if "--descriptor-guard-self-test" in OS.get_cmdline_user_args():
		var fixture:Dictionary={"label":"house","model_building":{"version":1,"source_sha":"unchanged","floors":[0,1],"extent":[3.25,6.45]}}
		var reloaded:Dictionary=JSON.parse_string(JSON.stringify(fixture))
		check(same_entry(fixture,reloaded),"descriptor JSON int/float roundtrip")
		var changed:=reloaded.duplicate(true);changed.model_building.extent[0]+=1e-7
		check(not same_entry(fixture,changed),"real coordinate change rejected")
		changed=reloaded.duplicate(true);changed.model_building.source_sha="different"
		check(not same_entry(fixture,changed),"source identity change rejected")
		changed=reloaded.duplicate(true);changed.model_building.floors[0]="0"
		check(not same_entry(fixture,changed),"numeric string rejected")
		changed=reloaded.duplicate(true);changed.model_building.new_key=true
		check(not same_entry(fixture,changed),"new descriptor key rejected")
		quit(0 if audit.failures.is_empty() else 1);return
	await super.run()
