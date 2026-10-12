extends "res://tools/test_house_town_editor_incremental.gd"
## Post-publication default catalog + real HTTP acceptance. Private GPU only.
## --map=<immutable cache copy> --expected-sha=<published SHA>
## [--catalog-receipt=<runtime review JSON>] [--output=<review JSON>]
## Inherits all town checks; extra saves target a NEW small disposable map.
const RECEIPT="D:/code/rmmo_runtime/review_artifacts/joint_model_validation_20261011/publish_preferred_v2_receipt.json"
const CatalogLibrary=preload("res://scripts/world_editor/asset_library.gd")
const PackCatalog=preload("res://scripts/world_editor/resource_pack_catalog.gd")
var receipt_path:=RECEIPT
var receipt_sha:=""
var receipt:Dictionary={}
var catalog_audit:Array=[]
var all_checks:Array=[]
var guards:Dictionary={}
var small_save_path:=""
var thumbnail_results:Dictionary={}

func check(ok:bool,label:String)->void:
	super.check(ok,label)
	all_checks.append({"ok":ok,"label":label})

func persist()->void:
	report.publication_receipt={"path":receipt_path,"sha256":receipt_sha,"published_sha256":receipt.get("published_sha256"),"catalog_sha_after":receipt.get("catalog_sha_after")}
	report.catalog_audit=catalog_audit;report.checks=all_checks
	report.full_rebuilds_scope="town_full_rebuilds is captured after all town transactions; full_rebuilds also includes the later explicit small-map opens. Catalog source SHA reads and thumbnail preparation are outside load_start_epoch_s..load_end_epoch_s."
	super.persist()

func canonical(path:String)->String:
	return ProjectSettings.globalize_path(path).replace("\\","/").simplify_path()

func valid_sha(value:Variant)->bool:
	if not value is String or value.length()!=64:return false
	for character in value:
		if character not in "0123456789abcdef":return false
	return true

func read_receipt()->Dictionary:
	var file:=FileAccess.open(receipt_path,FileAccess.READ)
	if file==null or file.get_length()>4*1024*1024:return {}
	var value:Variant=JSON.parse_string(file.get_as_text());file.close()
	return value if value is Dictionary else {}

func prepare_catalog()->bool:
	var before:=failed
	receipt_path=canonical(receipt_path)
	check(Paths.allowed(receipt_path,Paths.external_root().path_join("review_artifacts")) and receipt_path.get_extension()=="json" and FileAccess.file_exists(receipt_path),"published receipt is an existing confined JSON")
	if failed!=before:return false
	receipt=read_receipt()
	check(receipt.get("ok")==true and receipt.get("map_published")==true and receipt.get("choice")=="preferred" and receipt.get("mode")=="published_reference_map","receipt confirms successful preferred formal publication")
	check(valid_sha(receipt.get("published_sha256")) and valid_sha(receipt.get("catalog_sha_after")) and canonical(str(receipt.get("source","")))==canonical(SOURCE),"receipt binds exact formal map and final catalog identities")
	var rows:Variant=receipt.get("model_plan")
	check(rows is Array and rows.size()==11 and receipt.get("expected_counts",{}).get("model_types")==11 and receipt.get("expected_changed_instances")==59,"receipt declares the accepted eleven-model, 59-instance publication")
	if failed!=before:return false
	var pack_root:=Paths.external_root().path_join("packs/default")
	var library_root:=pack_root.path_join("assets")
	check(PackCatalog.new().packs().any(func(pack):return canonical(str(pack.root))==canonical(pack_root)),"default resource pack is registered")
	# Construct a fresh catalog reader, independent of the publisher's objects.
	var fresh:=CatalogLibrary.new(library_root)
	check(fresh._revision==receipt.catalog_sha_after,"fresh default catalog matches the published revision")
	receipt_sha=FileAccess.get_sha256(receipt_path)
	guards[receipt_path]=receipt_sha;guards[canonical(LIBRARY_PATH)]=receipt.catalog_sha_after
	var targets:Dictionary={};var pennants:Array=[]
	for value:Variant in rows:
		if not value is Dictionary:check(false,"model receipt row is a dictionary");continue
		var row:Dictionary=value
		var target:=canonical(str(row.get("target","")))
		var digest:Variant=row.get("candidate_sha256")
		var label:Variant=row.get("published_catalog_label")
		var declared_label:=str(row.get("label",""))
		var usable:bool=valid_sha(digest) and label is String and not str(label).strip_edges().is_empty() and not valid_sha(label) and label!=declared_label and not str(label).begins_with("obj_") and not str(label).contains("\n")
		check(usable and Paths.allowed(target,library_root) and target.get_file()==str(digest)+".glb" and not targets.has(target),"unique immutable target and human catalog label: "+declared_label)
		if not usable or not Paths.allowed(target,library_root) or targets.has(target):continue
		targets[target]=true
		# Sequential full reads BEFORE load_start_epoch_s, never concurrent with it.
		check(FileAccess.get_sha256(target)==digest,"published target full SHA: "+declared_label)
		guards[target]=digest
		var matching:Array=fresh.entries.filter(func(entry):return canonical(str(entry.get("asset_path","")))==target)
		check(matching.size()==1 and matching[0].get("label")==label,"fresh catalog has one exact target with published label: "+declared_label)
		if matching.size()!=1:continue
		var entry:Dictionary=matching[0]
		var thumb:=canonical(str(entry.get("thumbnail_path","")))
		check(Paths.allowed(thumb,library_root) and thumb.get_extension()=="png","catalog thumbnail declares a confined PNG destination: "+declared_label)
		# import_file may only declare the thumbnail path. Missing PNGs are
		# requested through the actual editor queue AFTER the town load timer.
		var exists:=FileAccess.file_exists(thumb)
		if exists:guards[thumb]=FileAccess.get_sha256(thumb)
		catalog_audit.append({"label":declared_label,"published_label":label,"target":target,"source_sha256":digest,"thumbnail":thumb,"thumbnail_existed":exists})
		if declared_label=="pennant_quality":pennants.append({"path":target,"label":label})
	check(targets.size()==11 and catalog_audit.size()==11 and pennants.size()==1,"all eleven published assets audited and one new pennant selected")
	if failed!=before:return false
	model_path=pennants[0].path;model_name=pennants[0].label
	return true

func run()->void:
	var map_arg:=false;var expected_arg:=false;var explicit_formal:=""
	output_path=Paths.external_root().path_join("review_artifacts/joint_model_validation_20261011/joint_published_catalog.json")
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--catalog-receipt" or arg.begins_with("--catalog-receipt="):receipt_path=arg.trim_prefix("--catalog-receipt=")
		elif arg.begins_with("--map="):map_arg=true
		elif arg.begins_with("--expected-sha="):expected_arg=true;expected_sha=arg.trim_prefix("--expected-sha=").to_lower()
		elif arg=="--formal-sha" or arg.begins_with("--formal-sha="):explicit_formal=arg.trim_prefix("--formal-sha=").to_lower()
	check(map_arg and expected_arg,"explicit immutable post-publication test map and SHA required")
	if failed>0 or not prepare_catalog():quit(1);return
	check(expected_sha==receipt.published_sha256 and (explicit_formal.is_empty() or explicit_formal==receipt.published_sha256),"temporary checkpoint and formal expectations bind the published map SHA")
	if failed>0:quit(1);return
	formal_sha=receipt.published_sha256;formal_sha_explicit=true
	await super.run()

func model_asset_id()->String:
	if not await ensure_catalog_thumbnails():return ""
	var selected:=""
	for row:Dictionary in catalog_audit:
		var listed:=await call_tool("list_assets",{"query":row.published_label,"limit":200})
		# Old and new editions may intentionally share a human label. Select by
		# immutable asset_id, not the first search result or globally unique name.
		var matches_:Array=listed.get("assets",[]).filter(func(item):return item.get("asset_id")==row.target and item.get("name")==row.published_label)
		check(matches_.size()==1,"real HTTP exposes exact published catalog asset: "+str(row.label))
		if matches_.size()==1:
			check(matches_[0].get("thumbnail",{}).get("status")=="ready" and canonical(str(matches_[0].get("thumbnail",{}).get("path","")))==row.thumbnail,"HTTP thumbnail matches reloaded catalog: "+str(row.label))
			if row.target==model_path:selected=matches_[0].asset_id
	return selected

func thumbnail_finished(key:String,path:String,error:int)->void:
	thumbnail_results[key]={"path":canonical(path),"error":error}

func ensure_catalog_thumbnails()->bool:
	var before:=failed
	var missing:Array=[]
	for row:Dictionary in catalog_audit:
		if not FileAccess.file_exists(row.thumbnail):missing.append(row.target)
	if not missing.is_empty():
		mark("published_catalog_thumbnail_queue")
		editor._thumbnails.import_finished.connect(thumbnail_finished)
		var started:=Time.get_ticks_usec()
		var requested:=await timed_tool("repair_asset_thumbnails",{"asset_ids":missing})
		check(requested.get("ok",false) and requested.get("queued")==missing.size(),"real HTTP queues only missing published thumbnails through native editor rendering")
		if requested.get("ok",false):
			var deadline:=Time.get_ticks_msec()+180000
			while missing.any(func(key):return not thumbnail_results.has(key)) and Time.get_ticks_msec()<deadline:await process_frame
		for row:Dictionary in catalog_audit:
			if not missing.has(row.target):continue
			var result:Dictionary=thumbnail_results.get(row.target,{})
			check(result.get("error",ERR_TIMEOUT)==OK and result.get("path")==row.thumbnail,"native thumbnail queue completes successfully: "+str(row.label))
		editor._thumbnails.import_finished.disconnect(thumbnail_finished)
		report.thumbnail_preparation={"requested":missing.size(),"ms":(Time.get_ticks_usec()-started)/1000.,"results":thumbnail_results.duplicate(true),"scope":"After measured town load; missing PNGs only, no catalog/source/map rewrite."}
	for row:Dictionary in catalog_audit:
		var pixels:Image=Image.load_from_file(row.thumbnail) if FileAccess.file_exists(row.thumbnail) else null
		check(pixels!=null and not pixels.is_empty() and not pixels.get_data().is_empty() and not pixels.is_invisible(),"published thumbnail has readable nonempty visible pixels: "+str(row.label))
		if pixels!=null:
			row.width=pixels.get_width();row.height=pixels.get_height()
			if not guards.has(row.thumbnail):guards[row.thumbnail]=FileAccess.get_sha256(row.thumbnail)
	return failed==before

func model_evidence(uuid:String)->Dictionary:
	var holder:Node=editor._view.get_node_or_null(NodePath(uuid))
	var evidence:={"meshes":0,"surfaces":0,"materials":0,"textures":0,"vertices":0,"picking_shapes":0,"valid":holder!=null,"scope":"Real scene descriptors; thumbnail pixels audited separately; no full model texture readback."}
	if holder==null:return evidence
	for mesh_node:MeshInstance3D in ModelPaint.meshes(holder):
		if mesh_node.mesh==null:evidence.valid=false;continue
		evidence.meshes+=1
		for slot in mesh_node.mesh.get_surface_count():
			evidence.surfaces+=1;evidence.vertices+=mesh_node.mesh.surface_get_array_len(slot)
			var material:Material=mesh_node.get_active_material(slot)
			if material==null:evidence.valid=false;continue
			evidence.materials+=1
			var textures:Array=[]
			if material is BaseMaterial3D:
				for texture_slot in BaseMaterial3D.TEXTURE_MAX:
					var texture:Texture2D=material.get_texture(texture_slot)
					if texture!=null:textures.append(texture)
			elif material is ShaderMaterial and material.shader!=null:
				for uniform:Dictionary in material.shader.get_shader_uniform_list():
					var value:Variant=material.get_shader_parameter(uniform.name)
					if value is Texture2D:textures.append(value)
			for texture:Texture2D in textures:
				evidence.textures+=1
				if texture.get_width()<=0 or texture.get_height()<=0:evidence.valid=false
	for body:Node in editor._bodies_by_uuid.get(uuid,[]):
		for child:Node in body.get_children():
			if child is CollisionShape3D and child.shape!=null:evidence.picking_shapes+=1
	evidence.valid=evidence.valid and evidence.meshes>0 and evidence.materials>0 and evidence.textures>0 and evidence.vertices>24 and evidence.picking_shapes>0
	return evidence

func after_town_transactions(model_id:String,model_record:Dictionary,pristine:Dictionary)->void:
	mark("published_pennant_delete_undo")
	await timed_tool("undo")
	check(equivalent(editor._doc._find(model_id),model_record) and model_evidence(model_id).valid,"new published pennant deletion undo restores UUID, actual material geometry and picking")
	retained("published pennant deletion undo")
	await timed_tool("redo")
	matches(pristine,"published pennant deletion redo");retained("published pennant deletion redo")
	report.town_full_rebuilds=editor.full_rebuilds
	report.town_incremental=editor.incremental.duplicate(true)
	if failed>0:return
	# Saving a fresh two-record map covers the new catalog model without another
	# full-town Save As. The original checkpoint/formal world are never saved.
	mark("published_catalog_small_save")
	small_save_path=directory.path_join("catalog_small/map.gltf")
	check(Paths.allowed(small_save_path,directory) and not FileAccess.file_exists(small_save_path),"catalog save uses a new fixture-owned small map")
	if failed>0:return
	DirAccess.make_dir_recursive_absolute(small_save_path.get_base_dir())
	var small:=Doc.new();small.add_box("block",Vector3.ZERO,Vector3.ONE)
	check(small.save(small_save_path)==OK,"small catalog fixture created independently of the town")
	if not await open_small():return
	var listed:=await call_tool("list_assets",{"query":model_name,"limit":200})
	var matches_:Array=listed.get("assets",[]).filter(func(row):return row.get("asset_id")==model_path and row.get("name")==model_name)
	check(matches_.size()==1,"reloaded small-map catalog discovers the exact new pennant")
	if matches_.size()!=1:return
	var placed:=await timed_tool("place_asset",{"asset_id":matches_[0].asset_id,"position":[5.,1.,0.]})
	check(placed.get("ids",[]).size()==1,"new published catalog pennant added to small save fixture")
	if placed.get("ids",[]).size()!=1:return
	var uuid:String=placed.ids[0]
	var authored:Dictionary=editor._doc.recovery_snapshot()
	check(editor._doc.records.size()==2 and editor._doc._find(uuid).get("asset_path")==model_path and model_evidence(uuid).valid,"small-map pennant has the correct source and real render/picking resources")
	var saved:=await timed_tool("save_world",{"path":small_save_path,"background":true})
	if not saved.get("ok",false):return
	while editor._save_job.active:await process_frame
	var result:Dictionary=editor._save_job.result.duplicate(true)
	report.catalog_small_save={"path":small_save_path,"uuid":uuid,"result":result}
	var exported:Dictionary=result.get("timings",{}).get("export",{})
	check(result.get("saved",false) and result.get("path")==small_save_path,"actual HTTP saves only the two-record fixture")
	check(exported.get("images_written",-1)==0 and exported.get("texture_export_passes",-1)==0,"published model remains external with zero image/texture export")
	if not await open_small():return
	check(equivalent(authored.records,editor._doc.records) and equivalent(authored.map_meta,editor._doc.map_meta) and model_evidence(uuid).valid,"small save/reopen preserves complete author state, UUID, new source, material and picking")
	report.catalog_small_save.record_count=editor._doc.records.size()
	report.catalog_small_save.full_rebuilds_after=editor.full_rebuilds

func open_small()->bool:
	var opened:=await timed_tool("open_world",{"path":small_save_path,"background":true,"discard_changes":true})
	if not opened.get("ok",false):return false
	while editor._load_job.active:await process_frame
	check(editor._load_job.result.get("ok",false),"real HTTP opens the owned small catalog map")
	editor._ground_batches.flush();await settle()
	return editor._load_job.result.get("ok",false)

func finish()->void:
	# This is after the load/operation timing window. No parallel model hashing.
	for path:String in guards:
		check(FileAccess.get_sha256(path)==guards[path],"published asset/catalog/thumbnail/receipt remains byte-identical: "+path.get_file())
	await super.finish()
