extends SceneTree
## One reviewed S2 green pennant post -> the actual shared default library.
## No map writes. --syntax-only is safe headlessly; --publish requires the
## private-desktop GPU runner. Every input identity is supplied at invocation.
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Compile=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const Packs=preload("res://scripts/world_editor/resource_pack_catalog.gd")
const Embedded=preload("res://scripts/world3d/embedded_glb.gd")
const BOUNDS_JSON_EPSILON:=1e-12
var options:Dictionary={}
var audit:Dictionary={"checks":[],"items":[],"failures":[],"completed":false,"ok":false,"formal_library_modified":false,"formal_map_modified":false}
var guards:Dictionary={}
var output:=""
var thumbs:Node
var thumbnail_results:Dictionary={}

func _initialize()->void:run.call_deferred()

func canonical(path:String)->String:
	return ProjectSettings.globalize_path(path).replace("\\","/").simplify_path()

func check(ok:bool,label:String)->bool:
	audit.checks.append({"ok":ok,"label":label})
	if not ok:audit.failures.append(label)
	print("PASS " if ok else "FAIL ",label)
	return ok

func read_dict(path:String)->Dictionary:
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func same_entry(actual:Dictionary,expected:Dictionary)->bool:
	# AssetLibrary serializes bounds at JSON's default precision. This is the
	# only numeric tolerance: metadata, paths and the complete key set stay exact.
	if actual.size()!=expected.size():return false
	for key:Variant in expected:
		if not actual.has(key):return false
		if key in ["bounds_position","bounds_size"]:
			if not actual[key] is Array or not expected[key] is Array or actual[key].size()!=3 or expected[key].size()!=3:return false
			for axis in 3:
				var a:Variant=actual[key][axis];var b:Variant=expected[key][axis]
				if typeof(a) not in [TYPE_INT,TYPE_FLOAT] or typeof(b) not in [TYPE_INT,TYPE_FLOAT]:return false
				if not is_finite(float(a)) or not is_finite(float(b)):return false
				if absf(float(a)-float(b))>BOUNDS_JSON_EPSILON*maxf(1.0,maxf(absf(float(a)),absf(float(b)))):return false
		elif typeof(actual[key])!=typeof(expected[key]) or actual[key]!=expected[key]:return false
	return true

func contains_entry(entries:Array,expected:Dictionary)->bool:
	return entries.any(func(entry):return entry is Dictionary and same_entry(entry,expected))

func entry_guard_self_test()->void:
	var source:Dictionary={"asset_path":"D:/fixture/asset.glb","thumbnail_path":"D:/fixture/thumb.png","label":"runtime","category":"导入模型","bounds_position":[-0.31882554292678833,0.0,-0.28340864181518555],"bounds_size":[0.6519860625267029,3.063523054122925,0.5668175220489502]}
	var rounded:Dictionary=JSON.parse_string(JSON.stringify(source))
	check(same_entry(rounded,source),"guard: actual JSON bounds roundtrip accepted")
	for field:String in ["asset_path","thumbnail_path","label","category"]:
		var changed:=rounded.duplicate(true);changed[field]+="changed"
		check(not same_entry(changed,source),"guard: independent "+field+" edit rejected")
	var moved:=rounded.duplicate(true);moved.bounds_size[0]+=1e-7
	check(not same_entry(moved,source),"guard: real bounds edit rejected")
	var added:=rounded.duplicate(true);added.extra=true
	check(not same_entry(added,source),"guard: new metadata key rejected")
	var removed:=rounded.duplicate(true);removed.erase("bounds_size")
	check(not same_entry(removed,source),"guard: removed metadata key rejected")
	var mistyped:=rounded.duplicate(true);mistyped.bounds_size[0]=str(mistyped.bounds_size[0])
	check(not same_entry(mistyped,source),"guard: nonnumeric bounds rejected")
	var short_bounds:=rounded.duplicate(true);short_bounds.bounds_size.pop_back()
	check(not same_entry(short_bounds,source),"guard: incomplete bounds rejected")
	print("S2_GREEN_POST_ENTRY_GUARDS checks=",audit.checks.size()," failures=",audit.failures.size())
	quit(0 if audit.failures.is_empty() else 1)

func validate_resume(folder:String,target:String,matches:Array)->Dictionary:
	var path:String=options["resume-receipt"]
	var confined:bool=Paths.allowed(path,canonical("res://review_artifacts")) or Paths.allowed(path,Paths.external_root().path_join("review_artifacts"))
	if not check(confined and FileAccess.file_exists(path),"existing confined failed receipt for explicit resume"):return {}
	var prior:=read_dict(path)
	if not check(prior.get("ok")==false and prior.get("completed")==false and prior.get("import_result") is Dictionary and prior.get("catalog_entries_before") is Array,"resume receipt records an incomplete import attempt"):return {}
	if not check(prior.get("id")==options.id and prior.get("source_path")==options.source and prior.get("source_sha256")==options.sha256 and prior.get("catalog_path")==folder.path_join("library.json"),"resume cannot switch model, source identity or catalog"):return {}
	var imported:Dictionary=prior.import_result
	if not check(imported.get("ok",false) and imported.get("entry") is Dictionary and imported.get("compiled_asset",{}).get("ok",false) and imported.get("compiled_asset",{}).get("footprint",{}).get("ok",false),"prior receipt confirms source/native/footprint import succeeded"):return {}
	var entry:Dictionary=imported.entry
	if not check(entry.get("asset_path")==target and imported.get("import_preparation",{}).get("source_sha")==options.sha256 and FileAccess.get_sha256(target)==options.sha256,"resume imported target is the exact accepted content SHA"):return {}
	if not check(entry.get("label")==str(options.source).get_file().get_basename() and entry.get("category")=="导入模型","resume is limited to this importer's initial default naming"):return {}
	if not check(not prior.catalog_entries_before.any(func(old):return old is Dictionary and canonical(str(old.get("asset_path","")))==target),"failed attempt originally introduced this target"):return {}
	if not check(matches.size()==1 and same_entry(matches[0],entry),"resume current entry still matches failed import; independent edits rejected"):return {}
	var old_proof:String=str(prior.get("review_path",""));var old_sha:String=str(prior.get("review_sha256",""))
	if not check(Compile._sha(old_sha) and FileAccess.file_exists(old_proof) and FileAccess.get_sha256(old_proof)==old_sha,"original acceptance bytes remain bound to failed receipt"):return {}
	guards[path]=FileAccess.get_sha256(path);guards[old_proof]=old_sha
	audit.resume={"receipt_path":path,"receipt_sha256":guards[path],"original_review_path":old_proof,"original_review_sha256":old_sha,"source_path":options.source,"source_sha256":options.sha256,"entry_before":entry.duplicate(true),"review_reissued":old_proof!=options.review,"bounds_json_relative_epsilon":BOUNDS_JSON_EPSILON}
	return entry.duplicate(true)

func flush()->bool:
	if output.is_empty():return false
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file:=FileAccess.open(output+".tmp",FileAccess.WRITE)
	if file==null:return check(false,"publication receipt staging open")
	file.store_string(JSON.stringify(audit,"  ",true,true));file.flush()
	var error:=file.get_error();file.close()
	return check(error==OK and Atomic.publish(output+".tmp",output)==OK,"publication receipt persisted")

func finish()->void:
	for path:String in guards:check(FileAccess.get_sha256(path)==guards[path],"protected source/review/map unchanged "+path.get_file())
	if audit.has("catalog_path"):audit.catalog_sha_after=FileAccess.get_sha256(audit.catalog_path)
	audit.completed=audit.failures.is_empty() and audit.items.size()==1
	audit.ok=audit.completed
	var persisted:=flush()
	print("S2_GREEN_POST_IMPORT completed=",audit.completed," receipt_persisted=",persisted)
	quit(0 if audit.completed and persisted else 1)

func parse_options()->bool:
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--publish":options.publish=true;continue
		if not arg.begins_with("--") or not arg.contains("="):return check(false,"expected --key=value arguments")
		var key:=arg.substr(2).get_slice("=",0)
		if key not in ["source","sha256","review","review-sha256","out","id","label","category","resume-receipt"] or options.has(key):return check(false,"known unique argument "+key)
		options[key]=arg.substr(arg.find("=")+1)
	for key:String in ["source","sha256","review","review-sha256","out","label","category"]:
		if not check(not str(options.get(key,"")).is_empty(),"required argument "+key):return false
	for key:String in ["source","review","out"]:options[key]=canonical(options[key])
	if options.has("resume-receipt"):options["resume-receipt"]=canonical(options["resume-receipt"])
	options.id=str(options.get("id","s2_green_post"))
	if not check(str(options.id).is_valid_filename(),"safe single model ID"):return false
	var allowed:bool=Paths.allowed(options.out,canonical("res://review_artifacts")) or Paths.allowed(options.out,Paths.external_root().path_join("review_artifacts"))
	if not check(allowed and str(options.out).get_extension()=="json" and not FileAccess.file_exists(options.out) and not FileAccess.file_exists(str(options.out)+".tmp"),"fresh confined receipt path"):return false
	output=options.out
	return true

func make_thumbnail(entry:Dictionary)->bool:
	var path:String=entry.thumbnail_path
	if FileAccess.file_exists(path):
		var image:=Image.load_from_file(path)
		if image!=null and image.get_width()==96 and image.get_height()==80 and not image.is_invisible():return true
	thumbs=preload("res://scripts/world_editor/asset_thumbnails.gd").new();root.add_child(thumbs)
	thumbs.import_finished.connect(func(key:String,_path:String,error:int):thumbnail_results[key]=error)
	thumbs.queue_import(entry)
	for frame in 12000:
		await process_frame
		if thumbnail_results.has(entry.asset_path):
			if thumbnail_results[entry.asset_path]!=OK:return false
			var image:=Image.load_from_file(path)
			return image!=null and image.get_width()==96 and image.get_height()==80 and not image.is_invisible()
	return false

func save_name(folder:String,target:String,imported_entry:Dictionary)->bool:
	# Only the imported entry is patched. A new snapshot/revision is obtained
	# for each retry; unrelated concurrent additions are never overwritten.
	for attempt in 3:
		var library:=Library.new(folder)
		var matches:Array=library.entries.filter(func(entry):return canonical(str(entry.get("asset_path","")))==target)
		if not check(matches.size()==1,"single imported catalog entry before naming"):return false
		var entry:Dictionary=matches[0]
		var desired:=imported_entry.duplicate(true);desired.label=options.label;desired.category=options.category
		if same_entry(entry,desired):return true
		if not check(same_entry(entry,imported_entry),"imported entry has not been independently edited"):return false
		var before:Array=library.entries.duplicate(true)
		entry.label=options.label;entry.category=options.category
		var error:=library.save()
		if error==ERR_BUSY:
			audit.get_or_add("catalog_revision_retries",[]).append({"attempt":attempt+1,"revision":library._revision})
			await process_frame;continue
		if not check(error==OK,"revision-checked atomic named catalog save"):return false
		var fresh:=Library.new(folder)
		for old:Dictionary in before:
			if canonical(str(old.get("asset_path","")))!=target:
				if not check(contains_entry(fresh.entries,old),"concurrent/preexisting named-save entry retained "+str(old.label)):return false
		return true
	return check(false,"catalog remained busy; no stale snapshot written")

func run()->void:
	if "--syntax-only" in OS.get_cmdline_user_args():print("S2_GREEN_POST_IMPORT syntax only");quit();return
	if OS.get_cmdline_user_args()==PackedStringArray(["--guard-self-test"]):entry_guard_self_test();return
	if not parse_options():quit(2);return
	if not check(options.get("publish",false) and DisplayServer.get_name()!="headless","explicit publication on private GPU desktop"):finish();return
	Engine.max_fps=60;root.size=Vector2i(420,320)
	var source:String=options.source;var expected:String=options.sha256;var proof:String=options.review
	if not check(Paths.allowed(source) and source.get_extension().to_lower()=="glb" and Compile._sha(expected) and FileAccess.get_sha256(source)==expected,"explicit accepted source GLB SHA"):finish();return
	if not check(Compile._sha(options["review-sha256"]) and FileAccess.get_sha256(proof)==options["review-sha256"],"explicit review receipt SHA"):finish();return
	var review:=read_dict(proof)
	var identity:Dictionary=review.get("identity",{}) if review.get("identity") is Dictionary else {}
	var reviewed_path:=canonical(str(review.get("source_path",identity.get("path",""))))
	var reviewed_sha:=str(review.get("source_sha256",identity.get("sha256","")))
	if not check(review.get("passed",false) and reviewed_path==source and reviewed_sha==expected,"passed review is bound to exact source identity"):finish();return
	# Do not publish a re-exported byte identity without its own visual review.
	if not check(Embedded.can_copy(source),"self-contained byte-copy GLB is supported by normal importer"):finish();return
	guards[source]=expected;guards[proof]=options["review-sha256"]
	var external:=Paths.external_root();var folder:=external.path_join("packs/default/assets")
	var target:=folder.path_join(expected+".glb");var catalog:=folder.path_join("library.json")
	if not check(Packs.new().packs().any(func(pack):return canonical(pack.root)==canonical(folder.get_base_dir()) and pack.shared),"actual shared default pack registered"):finish();return
	var original:=Library.new(folder)
	var prior_matches:Array=original.entries.filter(func(entry):return canonical(str(entry.get("asset_path","")))==target)
	var resumed_entry:Dictionary={}
	if options.has("resume-receipt"):
		resumed_entry=validate_resume(folder,target,prior_matches)
		if resumed_entry.is_empty():finish();return
	elif not check(prior_matches.size()<=1 and (prior_matches.is_empty() or (prior_matches[0].label==options.label and prior_matches[0].get("category")==options.category)),"no existing differently named asset will be overwritten"):finish();return
	if FileAccess.file_exists(target) and not check(FileAccess.get_sha256(target)==expected,"preexisting immutable target intact"):finish();return
	var user_map:=external.path_join("maps/medieval_river_town/map.gltf")
	if FileAccess.file_exists(user_map):guards[user_map]=FileAccess.get_sha256(user_map)
	audit.merge({"id":options.id,"source_path":source,"source_sha256":expected,"review_path":proof,"review_sha256":guards[proof],"catalog_path":catalog,"catalog_sha_before":original._revision,"catalog_entries_before":original.entries.duplicate(true),"generator":Compile.generator(),"scope":"One formal-library import; no user map placement. UI AssetLibrary importer is shared; current MCP has no generic file-import endpoint."})
	if not flush():quit(1);return
	var library:=Library.new(folder)
	var imported:=library.import_file(source)
	audit.import_result=imported
	if not check(imported.get("ok",false),"normal UI AssetLibrary import succeeded"):finish();return
	audit.formal_library_modified=library._revision!=original._revision
	var entry:Dictionary=imported.entry
	if not check(canonical(entry.asset_path)==target and FileAccess.get_sha256(target)==expected,"formal target byte-identical to reviewed GLB"):finish();return
	if not resumed_entry.is_empty() and not check(same_entry(entry,resumed_entry),"resumed entry remained unchanged during native import"):finish();return
	var compiled:Dictionary=imported.get("compiled_asset",{})
	if not check(compiled.get("ok",false) and compiled.get("footprint",{}).get("ok",false),"real native product and footprint complete; no fallback pass"):finish();return
	if not await save_name(folder,target,resumed_entry if not resumed_entry.is_empty() else entry.duplicate(true)):finish();return
	var fresh:=Library.new(folder)
	var named:Array=fresh.entries.filter(func(value):return canonical(str(value.get("asset_path","")))==target)
	if not check(named.size()==1 and named[0].label==options.label and named[0].category==options.category,"named formal item reopens exactly once"):finish();return
	entry=named[0]
	var native:=Library._verified_compiled_identity(target)
	if not check(not native.is_empty() and native.source_sha==expected,"native identity validates actual source and generator"):finish();return
	var product:=Compile.read(target)
	var hit:bool=product.get("hit",false);Drainer.dispose_result(product)
	if not check(hit,"closed production native actually reopens"):finish();return
	if not check(await make_thumbnail(entry),"production UI thumbnail ready"):finish();return
	var final_catalog:=Library.new(folder)
	for old:Dictionary in original.entries:
		var expected_entry:=old.duplicate(true)
		if not resumed_entry.is_empty() and old.get("asset_path")==target:
			expected_entry.label=options.label;expected_entry.category=options.category
		if not check(contains_entry(final_catalog.entries,expected_entry),"original catalog entry retained with only authorized naming "+str(old.label)):finish();return
	audit.formal_library_modified=final_catalog._revision!=original._revision
	audit.items.append({"id":options.id,"source_path":source,"target":target,"sha256":expected,"label":options.label,"category":options.category,"entry":entry,"native_identity":native,"native_manifest":read_dict(Compile.index_path(target)),"compiled_asset":compiled,"thumbnail_path":entry.thumbnail_path,"thumbnail_sha256":FileAccess.get_sha256(entry.thumbnail_path),"acceptance_report":proof,"acceptance_report_sha256":guards[proof]})
	audit.catalog_count_after=final_catalog.entries.size()
	if thumbs!=null:thumbs.queue_free();await process_frame
	finish()
