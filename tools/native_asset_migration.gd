extends RefCounted
## Explicit offline migration planning. Never called by a model consumer.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const MAX_METADATA_BYTES=64*1024*1024

static func _path(path:String,base:String="")->String:
	if path.is_empty():return ""
	return (path if path.is_absolute_path() else base.path_join(path)).replace("\\","/").simplify_path()

static func _error(plan_:Dictionary,reason:String,origin:String)->void:
	plan_.errors.append({"reason":reason,"origin":origin})

static func _json(plan_:Dictionary,path:String)->Variant:
	if not Paths.allowed(path,plan_.content_root):_error(plan_,"metadata_outside_root",path);return null
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()<=0 or file.get_length()>MAX_METADATA_BYTES:
		_error(plan_,"metadata_missing_or_size",path);return null
	var bytes:=file.get_buffer(file.get_length());file.close()
	var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(bytes)
	plan_.inputs[path]=hash_.finish().hex_encode()
	var parser:=JSON.new()
	if parser.parse(bytes.get_string_from_utf8())!=OK:_error(plan_,"metadata_json",path);return null
	var value:Variant=parser.data
	if value==null:_error(plan_,"metadata_json",path)
	return value

static func _model(plan_:Dictionary,value:Variant,base:String,origin:String)->void:
	if not value is String or value.is_empty():_error(plan_,"model_path_missing",origin);return
	var path:=_path(value,base)
	if not path.is_absolute_path() or not Paths.allowed(path,plan_.content_root):_error(plan_,"model_outside_root",origin);return
	if path.get_extension().to_lower()!="glb":_error(plan_,"unsupported_model_extension",origin);return
	var key:=path.to_lower() if OS.get_name()=="Windows" else path
	if plan_._models.has(key):
		plan_._models[key].origins.append(origin)
		return
	if not FileAccess.file_exists(path):_error(plan_,"model_missing:"+path,origin);return
	plan_._models[key]={"path":path,"origins":[origin]}

static func _records(plan_:Dictionary,records:Variant,base:String,origin:String)->void:
	if not records is Array:_error(plan_,"records_not_array",origin);return
	for index:int in records.size():
		var record:Variant=records[index];var at:=origin+"#record:"+str(index)
		if not record is Dictionary:_error(plan_,"record_not_object",at);continue
		# Stored prefabs contain flat editable records, not nested prefab links.
		if record.has("prefab_path"):_error(plan_,"nested_prefab_record_unsupported",at)
		if record.has("house_prefab"):
			# WorldDocument._mesh returns the frozen mesh before any old model/kit.
			# This inventory does not certify that mesh's geometry or authoring data.
			plan_.ignored_derived_provenance.append({"origin":at,"path":record.get("asset_path",""),"reason":"house_prefab_owns_geometry"})
			continue
		if record.get("kind")=="asset" or record.has("bridge_mesh"):
			# A bridge consumes its GLB kit even though its final mesh is derived.
			_model(plan_,record.get("asset_path"),base,at+".asset_path")
		if record.has("fortification_art"):
			var art:Variant=record.fortification_art
			if not art is Dictionary:_error(plan_,"fortification_art_not_object",at)
			elif not art.get("asset_path") is String or not str(art.asset_path).is_absolute_path():
				# PrefabLibrary.read only relocates ordinary asset and tile-kit paths.
				_error(plan_,"fortification_path_must_be_absolute",at)
			else:_model(plan_,art.asset_path,"",at+".fortification_art.asset_path")
		if not record.has("tile3d"):continue
		var tile:Variant=record.tile3d
		if not tile is Dictionary:_error(plan_,"tile3d_not_object",at);continue
		var options:Variant=tile.get("options",{})
		if not options is Dictionary:_error(plan_,"tile_options_not_object",at);continue
		if not options.has("kit"):continue
		var kit:Variant=options.kit
		if not kit is Dictionary or not kit.get("pieces") is Dictionary:_error(plan_,"tile_kit_pieces_not_object",at);continue
		for piece:Variant in kit.pieces:
			_model(plan_,kit.pieces[piece],base,at+".tile3d.options.kit.pieces."+str(piece))

static func _prefab(plan_:Dictionary,value:Variant,base:String,origin:String)->void:
	if not value is String or value.is_empty():_error(plan_,"prefab_path_missing",origin);return
	var path:=_path(value,base)
	var key:=path.to_lower() if OS.get_name()=="Windows" else path
	if plan_._prefabs.has(key):return
	plan_._prefabs[key]=true
	var raw:Variant=_json(plan_,path)
	if raw==null:return
	if not raw is Dictionary or raw.get("format")!="rmmo_prefab" or raw.get("version")!=1 or not raw.get("records") is Array:
		_error(plan_,"unsupported_prefab",path);return
	# Matches PrefabLibrary.read: <library>/prefabs/*.json references its library.
	_records(plan_,raw.records,path.get_base_dir().get_base_dir(),path)

static func plan(assets:Array,libraries:Array,prefabs:Array,map_records:Array,content_root:String,map_origin:String="")->Dictionary:
	var result:={"version":1,"scope":"offline native model dependency closure","content_root":_path(content_root),"inputs":{},"models":[],"errors":[],"ignored_derived_provenance":[],"_models":{},"_prefabs":{}}
	if result.content_root.is_empty() or not result.content_root.is_absolute_path():_error(result,"content_root_required",content_root)
	else:
		for asset:Variant in assets:_model(result,asset,"","--asset")
		var seen_libraries:Dictionary={}
		for library:Variant in libraries:
			if not library is String or not library.is_absolute_path():_error(result,"library_absolute_path_required",str(library));continue
			var path:=_path(library);var key:=path.to_lower() if OS.get_name()=="Windows" else path
			if seen_libraries.has(key):continue
			seen_libraries[key]=true
			var entries:Variant=_json(result,path)
			if entries==null:continue
			if not entries is Array:_error(result,"library_not_array",path);continue
			for index:int in entries.size():
				var entry:Variant=entries[index];var at:=path+"#entry:"+str(index)
				if not entry is Dictionary:_error(result,"library_entry_not_object",at);continue
				if not entry.has("asset_path") and not entry.has("prefab_path"):_error(result,"unsupported_library_entry",at)
				if entry.has("asset_path"):_model(result,entry.asset_path,path.get_base_dir(),at+".asset_path")
				if entry.has("prefab_path"):_prefab(result,entry.prefab_path,path.get_base_dir(),at+".prefab_path")
		for prefab:Variant in prefabs:
			if not prefab is String or not prefab.is_absolute_path():_error(result,"prefab_absolute_path_required",str(prefab));continue
			_prefab(result,prefab,"","--prefab")
		if not map_origin.is_empty():_records(result,map_records,map_origin.get_base_dir(),map_origin)
	result.models=result._models.values();result.models.sort_custom(func(a:Dictionary,b:Dictionary):return a.path<b.path)
	result.prefab_count=result._prefabs.size();result.erase("_models");result.erase("_prefabs")
	result.ok=result.errors.is_empty();result.closure_complete=result.ok
	return result

static func inputs_unchanged(plan_:Dictionary)->bool:
	for path:String in plan_.inputs:
		if not Paths.allowed(path,plan_.content_root) or FileAccess.get_sha256(path)!=plan_.inputs[path]:return false
	return true

## Migration defaults to preserving published native products, including older
## producer generations. Only this explicit offline operation reads the source.
## A broken existing publication is not permission to overwrite its index.
static func product_plan(path:String,content_root:String,reimport:bool=false)->Dictionary:
	if reimport:return {"ok":true,"action":"build","reason":"explicit_reimport"}
	var index:=Compiled.index_path(path,content_root)
	if not FileAccess.file_exists(index):return {"ok":true,"action":"build","reason":"first_import"}
	var identity:=Footprint._identity(path,content_root,true)
	if identity.is_empty():return {"ok":false,"reason":"published_product_invalid_or_missing:explicit_reimport_required"}
	var source_sha:=FileAccess.get_sha256(path)
	if not Compiled._sha(source_sha) or source_sha!=identity.source_sha:
		return {"ok":false,"reason":"reimport_required:source_changed_or_missing"}
	return {"ok":true,"action":"preserve","reason":"published_product","identity":identity,"source_sha":source_sha}

static func begin_report(plan_:Dictionary,refresh_bounds:bool=true,refresh_building:bool=true)->Dictionary:
	return {"version":1,"plan":plan_,"plan_only":false,"refresh_bounds_requested":refresh_bounds,"refresh_building_requested":refresh_building,"models":[],"built":0,"reused":0,"failures":plan_.errors.size(),"unsupported":0,"skipped":0,"footprints_built":0,"footprints_reused":0,"footprints_failed":0,"bounds_failed":0,"building_failed":0,"bytes":0,"footprint_elapsed_us":0,"source_assets_modified":false,"ok":false}

static func record_result(report:Dictionary,path:String,result:Dictionary)->void:
	var row:=result.duplicate(true);row.path=path
	var product_ok:bool=row.get("ok",false)
	row.product_ok=product_ok
	if product_ok:
		report["reused" if row.get("reused",false) else "built"]+=1
		report.bytes+=int(row.get("bytes",0))
		var footprint:Variant=row.get("footprint",{})
		var footprint_ok:bool=footprint is Dictionary and footprint.get("ok",false)
		report.footprint_elapsed_us+=int(row.get("footprint_elapsed_us",0))
		if footprint_ok:report["footprints_reused" if footprint.get("reused",false) else "footprints_built"]+=1
		else:report.footprints_failed+=1
		var bounds_ok:bool=not report.refresh_bounds_requested or (row.get("bounds") is Dictionary and row.bounds.get("ok",false))
		if not bounds_ok:report.bounds_failed+=1
		var building_ok:bool=not report.refresh_building_requested or (row.get("building") is Dictionary and row.building.get("ok",false))
		if not building_ok:report.building_failed+=1
		row.ok=footprint_ok and bounds_ok and building_ok and row.get("native_ready",false) and int(row.get("bytes",0))>0
		if not row.ok:row.migration_error="footprint_failed" if not footprint_ok else ("bounds_failed" if not bounds_ok else ("building_failed" if not building_ok else "native_product_incomplete"))
	if not row.get("ok",false):
		report.failures+=1
		if str(row.get("reason","")).contains("unsupported"):report.unsupported+=1
	report.models.append(row)

static func finish_report(report:Dictionary)->Dictionary:
	var paths:Dictionary={}
	for row:Dictionary in report.models:paths[str(row.path)]=true
	var expected:Dictionary={}
	for row:Dictionary in report.plan.models:expected[str(row.path)]=true
	report.closure_complete=report.plan.get("closure_complete",false) and paths==expected and report.models.size()==expected.size()
	report.inputs_unchanged=inputs_unchanged(report.plan)
	report.ok=report.failures==0 and report.closure_complete and report.inputs_unchanged
	return report
