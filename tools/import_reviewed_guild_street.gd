extends SceneTree
## Explicit catalog publication of the frozen 64 reviewed assets. No map writes.
## Uses the same importer, native compiler, atomic catalog save and thumbnails as UI.
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Compile=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const Catalog=preload("res://scripts/world_editor/resource_pack_catalog.gd")
const SPEC="res://review_artifacts/guild_reference_recheck_20261013/formal_import_manifest.json"
const OUT="res://review_artifacts/guild_reference_recheck_20261013/formal_import/receipt.json"
var audit:Dictionary={"items":[],"checks":[],"failures":[],"production_map_modified":false,"formal_library_modified":false}
var thumbs:Node
var thumb_results:Dictionary={}
var guards:Dictionary={}

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

func flush()->void:
	var path:=canonical(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:push_error("Publication receipt cannot be written");return
	file.store_string(JSON.stringify(audit,"\t",false,true));file.flush();file.close()
	if Atomic.publish(path+".tmp",path)!=OK:push_error("Publication receipt publish failed")

func finish()->void:
	for path:String in guards:
		check(FileAccess.get_sha256(path)==guards[path],"protected original map/catalog receipt remains unchanged: "+path)
	audit.completed=audit.failures.is_empty() and audit.items.size()==64
	audit.ok=audit.completed
	if audit.has("catalog_path"):audit.catalog_sha_after=FileAccess.get_sha256(audit.catalog_path)
	flush();print("FORMAL_GUILD_STREET_IMPORT ",audit.items.size()," completed=",audit.completed)
	quit(0 if audit.completed else 1)

func thumbnail(entry:Dictionary)->bool:
	var key:String=entry.asset_path
	var image:=Image.load_from_file(str(entry.thumbnail_path)) if FileAccess.file_exists(entry.thumbnail_path) else null
	if image!=null and not image.is_empty():return true
	thumbs.queue_import(entry)
	for _frame in 12000:
		await process_frame
		if thumb_results.has(key):
			if int(thumb_results[key])!=OK:return false
			image=Image.load_from_file(str(entry.thumbnail_path))
			return image!=null and image.get_width()==96 and image.get_height()==80
	return false

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if "--syntax-only" in args:print("FORMAL_IMPORT_SYNTAX_OK");quit();return
	if "--publish" not in args:push_error("Explicit --publish required");quit(2);return
	if not check(DisplayServer.get_name()!="headless","private-desktop graphical import required"):finish();return
	Engine.max_fps=60;root.size=Vector2i(420,320)
	var external:=Paths.external_root()
	var folder:=external.path_join("packs/default/assets")
	var catalog_path:=folder.path_join("library.json")
	if not check(canonical(external)=="D:/code/rmmo_runtime" and Paths.allowed(folder),"expected formal content root"):finish();return
	if not check(Catalog.new().packs().any(func(p):return canonical(p.root)==canonical(external.path_join("packs/default"))),"default pack is registered"):finish();return
	var spec:=read_dict(SPEC)
	var items:Variant=spec.get("items")
	if not check(items is Array and items.size()==64,"frozen 64-item manifest"):finish();return
	var seen:Dictionary={}
	for value:Variant in items:
		if not value is Dictionary:check(false,"manifest item type");finish();return
		var row:Dictionary=value
		var source:String=row.get("source_path","")
		var digest:String=row.get("sha256","")
		var label:String=row.get("label","")
		if not check(Paths.allowed(source) and Compile._sha(digest) and FileAccess.get_sha256(source)==digest and not seen.has(digest) and not label.is_empty(),"accepted source identity "+str(row.get("id"))):finish();return
		seen[digest]=true
		var proof:String=row.get("acceptance_report","")
		if not check(FileAccess.file_exists(proof),"per-asset acceptance exists "+str(row.id)):finish();return
		if row.has("acceptance_report_sha256") and not check(FileAccess.get_sha256(proof)==row.acceptance_report_sha256,"acceptance receipt hash "+str(row.id)):finish();return
		var target:=folder.path_join(digest+".glb")
		if FileAccess.file_exists(target) and not check(FileAccess.get_sha256(target)==digest,"immutable target intact "+str(row.id)):finish();return
	var original:=Library.new(folder)
	audit.merge({"manifest_path":canonical(SPEC),"manifest_sha256":FileAccess.get_sha256(SPEC),"catalog_path":catalog_path,"catalog_sha_before":original._revision,"catalog_entries_before":original.entries.duplicate(true),"catalog_count_before":original.entries.size(),"generator":Compile.generator(),"shared_native_cache":Compile.directory(),"native_cache_limit_bytes":null,"scope":"Formal default-pack catalog import only; user maps are never opened for writing. Existing source/native visual evidence remains tied to original SHA."})
	for path:String in [external.path_join("maps/medieval_river_town/map.gltf")]:
		if FileAccess.file_exists(path):guards[path]=FileAccess.get_sha256(path)
	flush()
	thumbs=preload("res://scripts/world_editor/asset_thumbnails.gd").new()
	root.add_child(thumbs)
	thumbs.import_finished.connect(func(key:String,_path:String,error:int):thumb_results[key]=error)
	for value:Dictionary in items:
		var library:=Library.new(folder) # Fresh revision; concurrent edits must never be overwritten.
		var source:String=value.source_path;var expected:String=value.sha256
		audit.active=value.id;flush()
		var started:=Time.get_ticks_msec()
		var imported:Dictionary=library.import_file(source)
		if not check(imported.get("ok",false),"UI importer registered "+str(value.id)):
			audit.failed_import=imported;finish();return
		audit.formal_library_modified=true
		var entry:Dictionary=imported.entry
		var target:String=entry.asset_path
		if not check(FileAccess.get_sha256(target)==expected and target==folder.path_join(expected+".glb"),"formal byte-exact target "+str(value.id)):finish();return
		var compiled:Dictionary=imported.get("compiled_asset",{})
		if not check(compiled.get("ok",false) and compiled.get("footprint",{}).get("ok",false),"shared native and footprint complete "+str(value.id)):
			audit.failed_native=compiled;finish();return
		entry.label=value.label;entry.category=value.category
		if not check(library.save()==OK,"atomic named catalog save "+str(value.id)):finish();return
		var native:=read_dict(Compile.index_path(target))
		if not check(native.get("source_sha")==expected and native.get("generator")==Compile.generator(),"current formal native manifest "+str(value.id)):finish();return
		var product:=Compile.read(target)
		if not check(product.get("hit",false),"real formal native reopen "+str(value.id)):
			Drainer.dispose_result(product);finish();return
		Drainer.dispose_result(product)
		if not check(await thumbnail(entry),"production thumbnail generated "+str(value.id)):finish();return
		var fresh:=Library.new(folder)
		var matches:Array=fresh.entries.filter(func(e):return e.get("asset_path")==target)
		if not check(matches.size()==1 and matches[0].get("label")==value.label and matches[0].get("category")==value.category,"catalog reopens with one named item "+str(value.id)):finish();return
		if not check(FileAccess.get_sha256(source)==expected,"author source unchanged "+str(value.id)):finish();return
		audit.items.append({"id":value.id,"source_path":source,"target":target,"sha256":expected,"label":value.label,"category":value.category,"thumbnail_path":entry.thumbnail_path,"thumbnail_sha256":FileAccess.get_sha256(entry.thumbnail_path),"native_manifest":native,"compiled_asset":compiled,"acceptance_report":value.acceptance_report,"elapsed_ms":Time.get_ticks_msec()-started})
		audit.catalog_sha_after=fresh._revision;flush();await process_frame
		Drainer.synchronize_transfer()
	var final_library:=Library.new(folder)
	for old:Dictionary in original.entries:
		check(final_library.entries.any(func(e):return e==old),"pre-existing catalog entry preserved "+str(old.get("label")))
	audit.catalog_count_after=final_library.entries.size();audit.erase("active")
	thumbs.queue_free();await process_frame
	finish()
