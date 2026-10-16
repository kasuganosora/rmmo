extends "res://tools/test_guild_street_published_catalog.gd"
## Formal-library HTTP acceptance for four immutable market prefabs.
## Only four derived thumbnails are regenerated; no import/capture/catalog save.
const MarketPrefabs=preload("res://scripts/world_editor/prefab_library.gd")
const MARKET_REVIEW="D:/code/rmmo_runtime/review_artifacts/axel_market_realism_20261016"
const MARKET_ART="D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016"
const MARKET_FORMAL="D:/code/rmmo_runtime/packs/default/assets"
const MARKET_IDS=["pottery","scroll","potion","ore"]
var map_roots:PackedStringArray=[]
var formal_map_inventory:Dictionary={}
var previous_session_path:=""
var previous_session_doc:Variant=null

func verify_thumbnail_repair()->void:
	var thumbs=editor._thumbnails
	check(thumbs!=null and editor._preview!=null,"actual editor thumbnail and UI preview services")
	if thumbs==null or editor._preview==null:return
	# Confine the private UI instance to these four existing entries so unrelated
	# missing visible assets are not automatically queued during this fixture.
	var entries:Array=audit.items.map(func(row):return row.entry)
	thumbs.set_visible_entries(entries)
	var ids:Array=audit.items.map(func(row):return row.prefab_path)
	var before_doc:Dictionary=editor._doc.recovery_snapshot();var before_catalog:=FileAccess.get_sha256(catalog_path)
	var before_queue:Array=thumbs._imports.duplicate(true);var before_loads:int=thumbs.model_load_count
	var before_images:Dictionary={}
	for row:Dictionary in audit.items:before_images[row.prefab_path]=FileAccess.get_sha256(row.entry.thumbnail_path)
	var invalid:=await call_tool("repair_asset_thumbnails",{"asset_ids":[ids[0],"invalid_market_thumbnail_id"]},false)
	check(equivalent(before_doc,editor._doc.recovery_snapshot()) and FileAccess.get_sha256(catalog_path)==before_catalog,"invalid mixed thumbnail IDs leave map/catalog unchanged")
	check(equivalent(before_queue,thumbs._imports) and thumbs.model_load_count==before_loads,"invalid mixed thumbnail IDs enqueue no valid-prefix work")
	for row:Dictionary in audit.items:check(FileAccess.get_sha256(row.entry.thumbnail_path)==before_images[row.prefab_path],"invalid thumbnail repair preserves existing image "+row.id)
	var done:Dictionary={}
	var callback:Callable=func(id:String,path:String,error:int):done[id]={"path":path,"error":error,"sha256":FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""}
	thumbs.import_finished.connect(callback)
	var queued:=await call_tool("repair_asset_thumbnails",{"asset_ids":ids})
	check(queued.get("queued")==4 and thumbs._imports.size()==4,"real HTTP queues four explicit production thumbnail renders")
	var environment:Environment=thumbs._camera.environment
	var helper_path:="res://scripts/world_editor/asset_preview_environment.gd"
	check(environment!=null and environment.sky!=null and environment.reflected_light_source==Environment.REFLECTION_SOURCE_SKY and environment.sky.get_meta("asset_preview_environment_version",0)==1,"actual thumbnail camera uses shared reflection recipe")
	var ui_environment:Environment=editor._preview.camera.environment
	check(ui_environment!=null and ui_environment.sky!=null and ui_environment.reflected_light_source==Environment.REFLECTION_SOURCE_SKY and ui_environment.sky.get_meta("asset_preview_environment_version",0)==1,"actual UI preview camera uses shared reflection recipe")
	thumbs.set_process(true)
	var deadline:=Time.get_ticks_msec()+720000
	while done.size()<4 and Time.get_ticks_msec()<deadline:await process_frame
	# Do not leave automatic visible-library repair active during map tests.
	thumbs.set_process(false)
	thumbs.import_finished.disconnect(callback)
	check(done.size()==4 and thumbs.model_load_count-before_loads==4,"four production import_finished signals and actual native preview loads")
	audit.thumbnail_repair={"real_http":true,"request":queued,"invalid_request":invalid,"images":[],"completed_signals":done,"actual_model_load_delta":thumbs.model_load_count-before_loads,"environment_helper_sha256":FileAccess.get_sha256(helper_path),"environment_recipe_version":1,"map_modified":false,"catalog_modified":false,"scope":"Only these four derived formal thumbnails regenerated through the real 3D repair_asset_thumbnails endpoint; UI and thumbnail camera environments inspected directly."}
	DirAccess.make_dir_recursive_absolute(output_dir.path_join("thumbnail_review"));DirAccess.make_dir_recursive_absolute(output_dir.path_join("ui_preview"))
	for row:Dictionary in audit.items:
		var state:Dictionary=thumbs.state(row.entry);var item:Dictionary=done.get(row.prefab_path,{})
		check(item.get("error",FAILED)==OK and state.status=="ready" and canonical(state.path)==canonical(row.entry.thumbnail_path),"production repaired thumbnail reaches ready "+row.id)
		var listing:=await call_tool("list_assets",{"query":row.entry.label,"limit":200})
		var matches:Array=listing.get("assets",[]).filter(func(value):return value.get("asset_id")==row.prefab_path)
		check(matches.size()==1 and matches[0].get("thumbnail",{}).get("status")=="ready","actual HTTP list_assets reports repaired thumbnail ready "+row.id)
		var image:=Image.load_from_file(row.entry.thumbnail_path)
		check(image!=null and image.get_size()==Vector2i(96,80),"actual newly rendered formal thumbnail dimensions "+row.id)
		var snapshot:=output_dir.path_join("thumbnail_review").path_join(row.id+".png")
		if image!=null:check(image.save_png(snapshot)==OK,"own review copy of actual repaired thumbnail "+row.id)
		var new_sha:=FileAccess.get_sha256(row.entry.thumbnail_path)
		# The derived PNG is explicitly writable; all source/catalog/native guards
		# remain unchanged. Bind the completed output as its new guarded identity.
		readonly_guards[canonical(row.entry.thumbnail_path)]=new_sha
		editor._preview.show_prefab(row.entry)
		for frame in 5:await process_frame;await RenderingServer.frame_post_draw
		var preview:Image=editor._preview.viewport_.get_texture().get_image();var preview_path:=output_dir.path_join("ui_preview").path_join(row.id+".png")
		check(editor._preview.scene!=null and preview!=null and preview.get_width()>8 and preview.get_height()>8,"actual UI prefab preview rendered with shared environment "+row.id)
		if preview!=null:check(preview.save_png(preview_path)==OK,"own actual UI preview screenshot "+row.id)
		audit.thumbnail_repair.images.append({"asset":row.id,"asset_id":row.prefab_path,"source_sha256":row.output_sha,"formal_path":row.entry.thumbnail_path,"before_sha256":before_images[row.prefab_path],"after_sha256":new_sha,"review_png":snapshot,"ui_preview_png":preview_path,"dimensions":[96,80]})
	editor._preview.show_asset("")
	check(equivalent(before_doc,editor._doc.recovery_snapshot()) and FileAccess.get_sha256(catalog_path)==before_catalog,"valid thumbnail repair and UI preview leave map/catalog unchanged")
	guard(ProjectSettings.globalize_path(helper_path))
	flush_report()

func read_market_json(path:String)->Dictionary:
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return value if value is Dictionary else {}

func guard(path:String,expected:String="")->void:
	path=canonical(path)
	check(FileAccess.file_exists(path),"read-only guard file exists "+path)
	if not FileAccess.file_exists(path):return
	var actual:=FileAccess.get_sha256(path)
	check(expected.is_empty() or actual==expected,"read-only guard expected SHA "+path.get_file())
	readonly_guards[path]=actual

func map_inventory(directory_:String)->Dictionary:
	var result:Dictionary={}
	if not DirAccess.dir_exists_absolute(directory_):return result
	for filename:String in DirAccess.get_files_at(directory_):
		var path:=directory_.path_join(filename)
		# Author documents and their sidecars; no duplicate map backups are made.
		if filename.get_extension().to_lower() in ["gltf","glb","json","bin"]:result[path]=FileAccess.get_sha256(path)
	for child:String in DirAccess.get_directories_at(directory_):result.merge(map_inventory(directory_.path_join(child)))
	return result

func protect_formal_maps()->void:
	map_roots.append(Paths.external_root().path_join("maps"))
	for pack:Dictionary in Packs.new().packs():
		var maps:=canonical(str(pack.root)).path_join("maps")
		if not map_roots.has(maps):map_roots.append(maps)
	for directory_:String in map_roots:formal_map_inventory.merge(map_inventory(directory_))
	audit.formal_map_files_before=formal_map_inventory.duplicate(true)

func prepare_published_catalog()->bool:
	var initial:=failed
	published=read_market_json(receipt_path)
	check(published.get("ok",false) and published.get("catalog_committed",false) and published.get("status")=="published_maps_unchanged","successful committed market publication receipt")
	var rows:Variant=published.get("mapping",[])
	check(rows is Array and rows.size()==4,"exactly four published market prefab mappings")
	if failed!=initial:return false
	guard(receipt_path)
	var plan_path:=canonical(str(published.get("plan_path","")))
	check(Paths.allowed(plan_path,MARKET_ART) and plan_path.get_file()=="publication_plan.json","versioned plan path inside task art root")
	if failed!=initial:return false
	guard(plan_path,str(published.get("plan_sha256","")))
	var plan:=read_market_json(plan_path)
	catalog_path=MARKET_FORMAL.path_join("library.json")
	guard(catalog_path)
	check(canonical(Paths.external_root().path_join("packs/default/assets"))==MARKET_FORMAL,"actual external content root; no temporary library override")
	check(Packs.new().packs().any(func(pack):return canonical(pack.root)==MARKET_FORMAL.get_base_dir() and pack.shared),"normal discoverable shared default pack")
	var library:=Library.new(MARKET_FORMAL)
	var seen:Dictionary={}
	for mapping:Dictionary in rows:
		var id:=str(mapping.get("asset",""));var target:=canonical(str(mapping.get("new_glb","")));var prefab:=canonical(str(mapping.get("new_asset_id","")));var sha:=str(mapping.get("candidate_sha256",""))
		check(id in MARKET_IDS and not seen.has(id),"unique expected market ID "+id);seen[id]=true
		var safe:=Compile._sha(sha) and target==MARKET_FORMAL.path_join(sha+".glb") and Paths.allowed(prefab,MARKET_FORMAL.path_join("prefabs")) and prefab.get_extension()=="json"
		check(safe,"confined new immutable source/prefab "+id)
		if not safe:continue
		guard(target,sha);guard(prefab,str(mapping.get("prefab_sha256","")))
		var old_rows:Array=plan.get("rows",[]).filter(func(value):return value.get("asset")==id)
		check(old_rows.size()==1,"frozen original market entry "+id)
		if old_rows.size()!=1:continue
		var old:Dictionary=old_rows[0]
		check(canonical(str(mapping.get("old_glb","")))==canonical(old.source) and canonical(str(mapping.get("old_asset_id","")))==canonical(old.existing_prefab.prefab_path) and sha==old.candidate_sha256,"publication mapping matches frozen identities "+id)
		guard(old.source,old.source_sha256);guard(old.existing_prefab.prefab_path,old.existing_prefab.prefab_sha256)
		var matches:Array=library.entries.filter(func(entry):return canonical(str(entry.get("prefab_path","")))==prefab)
		check(matches.size()==1,"formal catalog contains exact new prefab "+id)
		if matches.size()!=1:continue
		var entry:Dictionary=matches[0]
		check(equivalent(entry,mapping.get("entry",{})) and entry.get("label")==old.label and entry.get("category")==old.existing_prefab.entry.category,"formal label/category/entry unchanged from publication "+id)
		check(not library.entries.any(func(value):return canonical(str(value.get("prefab_path","")))==canonical(mapping.old_asset_id)),"original slot replaced without old entry duplication "+id)
		var payload:Dictionary=MarketPrefabs.read(entry)
		check(payload.get("ok",false) and payload.get("records",[]).size()==1 and canonical(str(payload.get("records",[{}])[0].get("asset_path","")))==target,"actual prefab dependency resolves to new GLB "+id)
		var native:Dictionary=Library._verified_compiled_identity(target)
		check(not native.is_empty() and native.get("source_sha")==sha,"actual formal native checksum and current generator "+id)
		var footprint:Dictionary=Footprint.candidate(target,Paths.external_root(),sha)
		check(not footprint.is_empty() and footprint.get("payload_sha")==native.get("payload_sha"),"source-bound formal footprint "+id)
		if not native.is_empty():
			guard(native.product,native.payload_sha)
			guard(Compile.index_path(target,Paths.external_root()))
			guard(Footprint.descriptor_path(target,Paths.external_root()))
		var thumb:=str(entry.get("thumbnail_path",""))
		check(not thumb.is_empty() and FileAccess.file_exists(thumb),"formal changed-appearance thumbnail exists "+id)
		if not thumb.is_empty() and FileAccess.file_exists(thumb):guard(thumb)
		audit.items.append({"id":id,"output_sha":sha,"output_path":target,"prefab_path":prefab,"old_asset_id":mapping.old_asset_id,"entry":entry.duplicate(true),"formal_native_identity":native,"formal_footprint":footprint,"prior_visual_review":published.get("acceptance",{})})
	for master:Dictionary in published.get("source_masters",[]):guard(str(master.get("file","")),str(master.get("sha256","")))
	check(seen.size()==4 and audit.items.size()==4,"all four expected market prefabs verified")
	audit.publication_catalog_sha=published.get("catalog_committed_sha256","")
	audit.catalog_sha_before=readonly_guards.get(catalog_path,"")
	audit.catalog_entries=library.entries.size()
	audit.catalog_revision_policy="Unrelated additions since publication are allowed; all four exact published entries and the current complete catalog stay unchanged during this test."
	protect_formal_maps()
	return failed==initial

func wait_loaded(id:String="")->void:
	var started:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<180000:
		await process_frame
		if editor==null or editor.saving() or editor._view==null:continue
		if editor._load_job!=null and editor._load_job.active:continue
		if not id.is_empty() and not model_evidence(id).get("valid",false):continue
		await settle();return
	check(false,"complete editor/native readiness timeout "+id)

func native_owner_evidence(uuid:String,row:Dictionary)->Dictionary:
	var holder:Node=editor._view.get_node_or_null(NodePath(uuid))
	var owners:Array=[]
	if holder!=null:
		var nodes:Array=[holder];nodes.append_array(holder.find_children("*","",true,false))
		for node:Node in nodes:
			if not node.has_meta("_compiled_resource_owner"):continue
			var owner:Variant=node.get_meta("_compiled_resource_owner")
			if owner is PackedScene:
				owners.append({"node":str(holder.get_path_to(node)),"validated":owner.get_meta("compiled_asset_validated",false),"source_sha":owner.get_meta("_rmmo_source_digest",""),"resource_path":owner.resource_path})
	var valid:=not owners.is_empty() and owners.all(func(owner):return owner.validated and owner.source_sha==row.output_sha)
	return {"valid":valid,"owners":owners,"cached_current_source":Library.has_cached_scene(row.output_path,row.output_sha)}

func verify_item(row:Dictionary,map_path:String)->void:
	var initial:=failed
	audit.active={"id":row.id,"phase":"formal_prefab_http"};flush_report()
	var listing:=await call_tool("list_assets",{"query":row.entry.label,"limit":200})
	var matches:Array=listing.get("assets",[]).filter(func(item):return canonical(str(item.get("asset_id","")))==row.prefab_path and item.get("name")==row.entry.label)
	check(matches.size()==1,"real HTTP discovers exact formal prefab asset_id "+row.id)
	check(editor._doc.records.is_empty(),"owned fixture initially empty "+row.id)
	var snapshot:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("place_asset",{"asset_id":"invalid_market_prefab_id","position":[3,0,-2]},false)
	check(equivalent(snapshot,editor._doc.recovery_snapshot()),"invalid place leaves author state unchanged "+row.id)
	var placed:=await call_tool("place_asset",{"asset_id":row.prefab_path,"position":[3,0,-2]})
	check(placed.get("ids",[]).size()==1 and editor._doc.records.size()==1,"direct formal prefab path placement "+row.id)
	if editor._doc.records.size()!=1:return
	var uuid:String=editor._doc.records[0].uuid;row.test_uuid=uuid
	await wait_loaded(uuid)
	await call_tool("select_objects",{"ids":[uuid]})
	check(editor._selection_tools.ids==[uuid],"actual instance selection "+row.id)
	check(canonical(str(editor._doc._find(uuid).get("asset_path","")))==row.output_path and FileAccess.get_sha256(row.output_path)==row.output_sha,"placed dependency exact new source SHA "+row.id)
	check(equivalent(editor._doc._find(uuid).get("position"),[3,0,-2]),"prefab pivot preserves requested placement "+row.id)
	row.before_save=model_evidence(uuid);row.native_before=native_owner_evidence(uuid,row)
	check(row.before_save.valid and row.native_before.valid and row.native_before.cached_current_source,"actual rendered geometry/collision and source-bound native owner "+row.id)
	await call_tool("undo");await wait_loaded()
	check(editor._doc.records.is_empty(),"prefab placement undo "+row.id)
	await call_tool("redo");await wait_loaded(uuid)
	check(editor._doc.records.size()==1 and equivalent(row.before_save,model_evidence(uuid)),"prefab redo preserves UUID geometry material collision "+row.id)
	row.native_redo=native_owner_evidence(uuid,row);check(row.native_redo.valid,"redo actual native owner "+row.id)
	var authored:Dictionary=editor._doc.recovery_snapshot()
	row.save_result=await call_tool("save_world",{"path":map_path})
	var started:=Time.get_ticks_msec()
	while editor._save_job.active and Time.get_ticks_msec()-started<180000:await process_frame
	check(not editor._save_job.active,"temporary map save completed "+row.id)
	await call_tool("open_world",{"path":map_path});await wait_loaded(uuid)
	check(equivalent(authored.records,editor._doc.records) and equivalent(authored.map_meta,editor._doc.map_meta),"save/open complete author state preserved "+row.id)
	check(editor._doc.missing_assets().is_empty(),"formal dependency resolves after reopen "+row.id)
	row.after_reopen=model_evidence(uuid);row.native_reopen=native_owner_evidence(uuid,row)
	check(row.after_reopen.valid and equivalent(row.before_save,row.after_reopen),"reopened mesh/material/collision unchanged "+row.id)
	check(row.native_reopen.valid and row.native_reopen.cached_current_source,"reopen uses source-bound validated native owner "+row.id)
	var reopened=Doc.open_file(map_path)
	check(reopened!=null and reopened.records.size()==1 and canonical(str(reopened.records[0].get("asset_path","")))==row.output_path,"disk map uses formal new GLB dependency "+row.id)
	check(equivalent(Library._verified_compiled_identity(row.output_path),row.formal_native_identity),"native disk identity unchanged through real reopen "+row.id)
	await call_tool("select_objects",{"ids":[uuid]});await call_tool("delete_selection");await wait_loaded()
	check(editor._doc.records.is_empty(),"delete only owned temporary instance "+row.id)
	row.http_passed=failed==initial
	write_json(output_dir.path_join("items").path_join(row.id+".json"),row)
	audit.erase("active");flush_report()

func finish_market()->void:
	if editor!=null:
		editor._mcp.stop();editor.queue_free();await settle();editor=null
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=previous_session_doc;session.world3d_editor_path=previous_session_path
	for path:String in readonly_guards:check(FileAccess.file_exists(path) and FileAccess.get_sha256(path)==readonly_guards[path],"guard unchanged "+path)
	var maps_after:Dictionary={}
	for directory_:String in map_roots:maps_after.merge(map_inventory(directory_))
	check(equivalent(maps_after,formal_map_inventory),"formal map inventory and bytes unchanged")
	audit.readonly_guards=readonly_guards;audit.formal_map_files_after=maps_after
	audit.catalog_sha_after=FileAccess.get_sha256(catalog_path) if not catalog_path.is_empty() else ""
	audit.completed=true;audit.verified_count=audit.items.filter(func(row):return row.get("http_passed",false)).size()
	check(audit.verified_count==4,"all four formal market prefabs passed real HTTP")
	flush_report();print("AXEL_MARKET_FORMAL_HTTP failures=",failed);quit(0 if failed==0 else 1)

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if "--syntax-only" in args:print("AXEL_MARKET_FORMAL_HTTP syntax only");quit();return
	output_dir="";receipt_path=""
	for arg:String in args:
		if arg.begins_with("--receipt="):receipt_path=canonical(arg.trim_prefix("--receipt="))
		if arg.begins_with("--out="):output_dir=canonical(arg.trim_prefix("--out="))
	if not Paths.allowed(output_dir,MARKET_REVIEW.path_join("formal_http")) or not Paths.allowed(receipt_path,MARKET_REVIEW.path_join("publication")) or DisplayServer.get_name()=="headless":push_error("Explicit new review output, committed publication receipt and private GPU desktop required");quit(2);return
	if FileAccess.file_exists(output_dir.path_join("editor_verification.json")):push_error("Use a fresh verification take; retain previous evidence");quit(2);return
	Engine.max_fps=60;rpc_timeout_ms=120000;root.size=Vector2i(1000,720)
	audit={"checks":[],"items":[],"real_http":true,"formal_catalog_modified":false,"formal_map_modified":false,"formal_source_modified":false,"four_derived_thumbnails_regenerated":true,"receipt_path":receipt_path,"generator":Compile.generator(),"runtime_identity":http_runtime_identity(),"scope":"Direct real formal prefab IDs in an owned temporary map. Four explicit production thumbnails and UI previews rendered with shared environment. No temporary library substitution, import/capture/recompile, formal map edits or whole-town FPS claim."}
	create_timer(1800).timeout.connect(func():audit.timeout=true;flush_report();quit(2))
	if not prepare_published_catalog():flush_report();quit(1);return
	fixture_directory=Paths.cache_directory("axel_market_formal_http_%d"%Time.get_ticks_usec())
	check(not DirAccess.dir_exists_absolute(fixture_directory),"fresh owned temporary map directory")
	check(DirAccess.make_dir_recursive_absolute(fixture_directory)==OK,"create temporary map directory")
	var map_path:=fixture_directory.path_join("map.gltf")
	var doc:=Doc.new();check(doc.save(map_path)==OK,"save new empty temporary map")
	if failed>0:await finish_market();return
	var session=preload("res://scripts/net/net.gd").session();previous_session_path=session.world3d_editor_path;previous_session_doc=session.world3d_editor_doc
	session.world3d_editor_path=map_path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=fixture_directory.path_join("drafts");root.add_child(editor)
	if editor._thumbnails!=null:editor._thumbnails.set_process(false)
	await wait_loaded();editor._safety.enabled=false
	var probe:=TCPServer.new();port=29940
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real private loopback 3D HTTP server")
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var tools_:Array=(await rpc("tools/list")).get("result",{}).get("tools",[])
	var names:Array=tools_.map(func(tool):return tool.name);audit.tool_names=names;audit.port=port;audit.isolated_map=map_path
	for name_:String in ["list_assets","repair_asset_thumbnails","place_asset","select_objects","save_world","open_world","undo","redo","delete_selection"]:check(names.has(name_),"actual current tool discovery "+name_)
	await verify_thumbnail_repair()
	var unfiltered:Array=[];var offset:=0;var total:=1
	while offset<total:
		var page:=await call_tool("list_assets",{"limit":200,"offset":offset})
		total=int(page.get("total",0));unfiltered.append_array(page.get("assets",[]));offset+=200
		if not page.get("ok",false):break
	for row:Dictionary in audit.items:check(unfiltered.any(func(entry):return canonical(str(entry.get("asset_id","")))==row.prefab_path),"unfiltered real catalog discovers prefab "+row.id)
	audit.http_unfiltered_catalog_total=total
	for row:Dictionary in audit.items:
		if failed>0:break
		await verify_item(row,map_path)
	check(equivalent(audit.runtime_identity,http_runtime_identity()),"production runtime code unchanged during HTTP")
	await finish_market()
