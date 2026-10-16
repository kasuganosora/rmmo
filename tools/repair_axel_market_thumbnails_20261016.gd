extends SceneTree
## Repair only the three missing formal UI thumbnails through the normal queue.
const Thumbnails=preload("res://scripts/world_editor/asset_thumbnails.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const BASE="D:/code/rmmo_runtime/review_artifacts/axel_market_optimization_20261016"
const PUBLICATION=BASE+"/publication/publish03/publication.json"
const OUT=BASE+"/publication/thumbnail_repair01"
const FORMAL="D:/code/rmmo_runtime/packs/default/assets"
var report:Dictionary={"version":1,"method":"production AssetThumbnails.queue_import with production PrefabLibrary.preview; normal 96x80 camera/lighting/atomic PNG writer","checks":[],"failures":[],"items":[],"map_modified":false,"catalog_modified":false,"model_modified":false}
var thumbs:Node
var finished:Dictionary={}
var guards:Dictionary={}

func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	report.checks.append({"check":label,"ok":ok})
	if not ok:report.failures.append(label);push_error(label)
	return ok
func read(path:String)->Variant:return JSON.parse_string(FileAccess.get_file_as_string(path))
func guard(path:String)->void:
	if FileAccess.file_exists(path):guards[path]=FileAccess.get_sha256(path)
func finish()->void:
	for path:String in guards:check(FileAccess.get_sha256(path)==guards[path],"unchanged "+path)
	report.protected_file_sha256=guards
	report.ok=report.failures.is_empty()
	DirAccess.make_dir_recursive_absolute(OUT)
	var file:=FileAccess.open(OUT.path_join("receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MARKET_THUMBNAIL_REPAIR ",report.ok," items=",report.items.size())
	quit(0 if report.ok else 1)
func run()->void:
	if "--syntax-only" in OS.get_cmdline_user_args():print("THUMBNAIL_REPAIR_SYNTAX_OK");quit();return
	if not check("--repair" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless","explicit graphical thumbnail repair"):finish();return
	if not check(not FileAccess.file_exists(OUT.path_join("receipt.json")),"fresh receipt path"):quit(2);return
	Engine.max_fps=60;root.size=Vector2i(420,320)
	var publication:Dictionary=read(PUBLICATION)
	if not check(publication.get("ok",false),"accepted formal publication"):finish();return
	guard(PUBLICATION);guard(FORMAL.path_join("library.json"))
	var library:=Library.new(FORMAL)
	var jobs:Array=[]
	for mapping:Dictionary in publication.mapping:
		for field:String in ["new_asset_id","old_asset_id","new_glb","old_glb"]:guard(str(mapping[field]))
		guard(str(mapping.formal_native_identity.product))
		var matches:=library.entries.filter(func(entry):return str(entry.get("prefab_path",""))==mapping.new_asset_id)
		if not check(matches.size()==1,"one formal entry "+mapping.asset):finish();return
		var entry:Dictionary=matches[0]
		if not check(entry.thumbnail_path==mapping.entry.thumbnail_path and Paths.allowed(entry.thumbnail_path) and str(entry.thumbnail_path).get_base_dir()==FORMAL.path_join("thumbnails"),"exact formal output "+mapping.asset):finish();return
		if not check(FileAccess.get_sha256(mapping.new_glb)==mapping.candidate_sha256 and FileAccess.get_sha256(mapping.new_asset_id)==mapping.prefab_sha256,"exact source identities "+mapping.asset):finish();return
		if mapping.asset=="potion":
			check(FileAccess.file_exists(entry.thumbnail_path),"potion thumbnail already exists and is preserved");guard(entry.thumbnail_path)
			continue
		if not check(mapping.asset in ["pottery","scroll","ore"] and not FileAccess.file_exists(entry.thumbnail_path),"only missing target "+mapping.asset):finish();return
		jobs.append({"mapping":mapping,"entry":entry})
	if not check(jobs.size()==3,"exactly three missing thumbnails"):finish();return
	thumbs=Thumbnails.new();root.add_child(thumbs)
	thumbs.import_finished.connect(func(key:String,path:String,error:int):finished[key]={"path":path,"error":error})
	for job:Dictionary in jobs:
		var entry:Dictionary=job.entry;var key:=Thumbnails.key_for(entry)
		thumbs.queue_import(entry)
		var deadline:=Time.get_ticks_msec()+180000
		while not finished.has(key) and Time.get_ticks_msec()<deadline:await process_frame
		if not check(finished.has(key) and finished[key].error==OK,"normal queue finished "+job.mapping.asset):finish();return
		var image:=Image.load_from_file(entry.thumbnail_path)
		if not check(image!=null and image.get_size()==Vector2i(96,80),"normal dimensions "+job.mapping.asset):finish();return
		if not check(thumbs.state(entry).status=="ready","normal UI ready "+job.mapping.asset):finish();return
		report.items.append({"asset":job.mapping.asset,"source_prefab":key,"source_prefab_sha256":FileAccess.get_sha256(key),"source_glb":job.mapping.new_glb,"source_glb_sha256":FileAccess.get_sha256(job.mapping.new_glb),"output":entry.thumbnail_path,"output_sha256":FileAccess.get_sha256(entry.thumbnail_path),"bytes":FileAccess.get_file_as_bytes(entry.thumbnail_path).size(),"dimensions":[96,80],"source_kind":"Fresh production UI render, not an acceptance screenshot substitute","ui_state":thumbs.state(entry)})
	finish()
