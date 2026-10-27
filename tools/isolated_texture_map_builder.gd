extends RefCounted
## Offline benchmark-fixture builder. Reads an explicitly inventoried map and
## writes only a newly created external review root. It does not publish assets.
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Compressed=preload("res://scripts/world3d/compressed_texture_source.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
const REVIEW_ROOT:="D:/code/rmmo_runtime/review_artifacts"

static func _fail(reason:String)->Dictionary:return {"ok":false,"error":reason}

static func _strict_prefab_valid(record:Dictionary)->bool:
	# Fixture conversion is offline and single-threaded; this is not a runtime
	# package check. Verify exposed paint matches the serialized prefab packet.
	var previous:=Policy.verify_packages;Policy.verify_packages=true
	var result:=Prefab.valid(record);Policy.verify_packages=previous
	return result

static func _normalize(path:String)->String:
	if path.is_empty():return ""
	return path.replace("\\","/").simplify_path().trim_suffix("/")

static func _sidecar_suffix_valid(source:String,target:String,normal:bool,flip:bool)->bool:
	var suffix:=target.trim_prefix(source) if target.begins_with(source) else ""
	if flip:return normal and suffix in [".flip.bc5.dds",".flip.dxt1.dds",".flip.dxt5.dds"]
	if normal:return suffix in [".bc5.dds",".dxt1.dds",".dxt5.dds"]
	return suffix in [".dxt1.dds",".dxt5.dds"]

static func _png_size(path:String)->Vector2i:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return Vector2i.ZERO
	var bytes:=file.get_buffer(24);file.close()
	if bytes.size()!=24 or bytes.slice(0,8)!=PackedByteArray([137,80,78,71,13,10,26,10]) or bytes.slice(12,16).get_string_from_ascii()!="IHDR":return Vector2i.ZERO
	return Vector2i((int(bytes[16])<<24)|(int(bytes[17])<<16)|(int(bytes[18])<<8)|int(bytes[19]),(int(bytes[20])<<24)|(int(bytes[21])<<16)|(int(bytes[22])<<8)|int(bytes[23]))

static func _dds_evidence(path:String,header:Dictionary)->Dictionary:
	if path.is_empty() or header.is_empty():return {}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {}
	file.seek(84);var fourcc:=file.get_buffer(4).get_string_from_ascii();file.close()
	return {"width":header.width,"height":header.height,"mip_count":header.mip_count,"bytes":header.source_bytes,"fourcc":fourcc,"format":header.format}

static func _path_category(key:String)->String:
	if key in ["record.asset_path","record.fortification_art.asset_path"]:return "runtime_model"
	if key=="record.thumbnail_path":return "editor_thumbnail"
	if key=="extras.editor_layout.vegetation[].settings.asset_ids[]":return "editor_layout"
	if key in ["extras.town_reference.road_layout.source_plan","extras.town_reference.fortification_layout.source","extras.town_reference.landmarks.placements[].asset_path","extras.town_reference.functional_buildings.placements[].asset_path","extras.town_reference.functional_buildings.placements[].publication.path","extras.town_reference.market_functional_layout.props[].asset_path"]:return "reference_provenance"
	var editor_before:=key.begins_with("extras.terrain_rivers[].terrains[].before.")
	var editor_after:=key.begins_with("extras.terrain_rivers[].terrains[].after.")
	if editor_before or editor_after:
		var suffix:=key.trim_prefix("extras.terrain_rivers[].terrains[].before.") if editor_before else key.trim_prefix("extras.terrain_rivers[].terrains[].after.")
		for field:String in Paint.MAP_FIELDS:
			if suffix in ["terrain_material."+field,"terrain_slope_blend.rock_material."+field,"terrain_slope_blend.transition_material."+field,"terrain_regions.materials[]."+field]:return "editor_river_snapshot"
	for field:String in Paint.MAP_FIELDS:
		var prefixes:=["record.terrain_material","record.terrain_slope_blend.rock_material","record.terrain_slope_blend.transition_material","record.terrain_regions.materials[]","record.bridge_materials.deck","record.bridge_materials.masonry","record.bridge_materials.trim","record.prefab_materials[]","record.road_kerb_material","record.surface_paint[].material"]
		for prefix:String in prefixes:
			if key==prefix+"."+field:return "runtime_material"
	return ""

static func _relative(path:String,root:String)->String:
	path=_normalize(path);root=_normalize(root)
	if not Paths.allowed(path,root) or not path.to_lower().begins_with(root.to_lower()+"/"):return ""
	return path.substr(root.length()+1)

static func _json(path:String)->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null

static func _copy(source:String,target:String,target_root:String,expected:String="")->Dictionary:
	if not Paths.allowed(target,target_root) or not FileAccess.file_exists(source):return _fail("copy path invalid: "+source)
	var source_sha:=FileAccess.get_sha256(source)
	if source_sha.is_empty() or (not expected.is_empty() and source_sha!=expected):return _fail("source identity changed: "+source)
	if FileAccess.file_exists(target):
		if FileAccess.get_sha256(target)!=source_sha:return _fail("conflicting target: "+target)
		return {"ok":true,"source":source,"target":target,"sha256":source_sha,"bytes":FileAccess.get_file_as_bytes(target).size(),"reused":true}
	if DirAccess.make_dir_recursive_absolute(target.get_base_dir())!=OK:return _fail("cannot create target parent")
	if not Paths.allowed(target,target_root) or DirAccess.copy_absolute(source,target)!=OK:return _fail("cannot copy target: "+target)
	if FileAccess.get_sha256(target)!=source_sha or FileAccess.get_sha256(source)!=source_sha:return _fail("copy identity changed: "+source)
	var file:=FileAccess.open(target,FileAccess.READ)
	var bytes:=file.get_length() if file!=null else -1
	return {"ok":true,"source":source,"target":target,"sha256":source_sha,"bytes":bytes,"reused":false}

static func build(source_map:String,source_root:String,audit_path:String,stage_dir:String,target_root:String,native_manifest_path:String="")->Dictionary:
	if not Thread.is_main_thread():return _fail("offline builder requires main thread")
	source_map=_normalize(source_map);source_root=_normalize(source_root);audit_path=_normalize(audit_path);stage_dir=_normalize(stage_dir);target_root=_normalize(target_root)
	if _relative(source_map,source_root).is_empty() or not FileAccess.file_exists(source_map):return _fail("invalid source map")
	if not Paths.allowed(audit_path,REVIEW_ROOT) or not Paths.allowed(stage_dir,REVIEW_ROOT):return _fail("audit and stage must be external review artifacts")
	if _relative(target_root,REVIEW_ROOT).is_empty() or DirAccess.dir_exists_absolute(target_root) or FileAccess.file_exists(target_root):return _fail("target must be a new external review root")
	var audit:Variant=_json(audit_path);var staged:Variant=_json(stage_dir.path_join("manifest.json"))
	if not audit is Dictionary or not staged is Dictionary or not FileAccess.file_exists(stage_dir.path_join("COMPLETE")):return _fail("missing complete inventory or stage")
	var source_sha:=FileAccess.get_sha256(source_map)
	var expected_native:Dictionary={};var native_manifest_sha:="";var authoring_paths:Array=[];var audited_path_fields:=0
	if not native_manifest_path.is_empty():
		native_manifest_path=_normalize(native_manifest_path)
		if not Paths.allowed(native_manifest_path,REVIEW_ROOT):return _fail("native inventory must be external")
		var native_manifest:Variant=_json(native_manifest_path)
		if not native_manifest is Dictionary or _normalize(str(native_manifest.get("map","")))!=source_map or _normalize(str(native_manifest.get("source_root","")))!=source_root or native_manifest.get("map_sha256","")!=source_sha or not native_manifest.get("errors") is Array or not native_manifest.errors.is_empty() or not native_manifest.get("models") is Array or int(native_manifest.get("requested",-1))!=native_manifest.models.size() or int(native_manifest.get("passed",-1))!=native_manifest.models.size():return _fail("native inventory does not match source map")
		for item:Variant in native_manifest.models:
			if not item is Dictionary or not item.get("model") is String or expected_native.has(item.model):return _fail("native inventory contains duplicate or invalid model")
			expected_native[item.model]=item
		if native_manifest.has("inventory"):
			var path_inventory:=_normalize(str(native_manifest.inventory))
			if not Paths.allowed(path_inventory,REVIEW_ROOT) or FileAccess.get_sha256(path_inventory)!=native_manifest.get("inventory_sha256",""):return _fail("path inventory identity changed")
			var path_data:Variant=_json(path_inventory)
			if not path_data is Dictionary or path_data.get("map_sha256","")!=source_sha or not path_data.get("path_fields") is Dictionary:return _fail("invalid map path inventory")
			for key:String in path_data.path_fields:
				var category:=_path_category(key)
				if category.is_empty():return _fail("unhandled serialized path field: "+key)
				audited_path_fields+=1
				if category not in ["runtime_model","runtime_material"]:authoring_paths.append({"field":key,"category":category,"evidence":"mesh-only game path does not open this authoring/reference metadata; preserved unchanged","count":path_data.path_fields[key]["count"],"values":path_data.path_fields[key]["values"]})
		native_manifest_sha=FileAccess.get_sha256(native_manifest_path)
	if not audit.get("map_unchanged",false) or not audit.get("errors") is Array or not audit.errors.is_empty() or _normalize(str(audit.get("map","")))!=source_map or audit.get("map_sha256","")!=source_sha:return _fail("inventory does not match source map")
	if (staged.has("errors") and (not staged.errors is Array or not staged.errors.is_empty())) or _normalize(str(staged.get("map","")))!=source_map or staged.get("map_sha256","")!=source_sha or staged.get("audit_sha256","")!=FileAccess.get_sha256(audit_path):return _fail("stage does not match inventory")
	var pack_root:=_normalize(str(staged.get("pack_root","")))
	if _relative(pack_root,source_root).is_empty():return _fail("pack root outside source root")
	if not audit.get("texture_variants") is Array or not staged.get("targets") is Array or not staged.get("blobs") is Array:return _fail("invalid inventory schema")
	if DirAccess.make_dir_recursive_absolute(target_root)!=OK:return _fail("cannot create target root")
	var copied:Array=[];var mapping:Dictionary={};var declarations:Dictionary={};var source_paths:Dictionary={};var sidecars:Dictionary={};var variant_rows:Array=[];var variant_keys:Dictionary={}
	for row:Variant in audit.texture_variants:
		if not row is Dictionary or not row.get("source") is String or not row.get("normal_role") is bool or not row.get("flip_normal_green") is bool:return _fail("invalid texture inventory row")
		var source:=_normalize(row.source);var relative:=_relative(source,source_root)
		if relative.is_empty() or not Paths.allowed(source,pack_root):return _fail("texture source outside inventoried pack")
		var target:=target_root.path_join(relative);mapping[source]=target;source_paths[source]=true
		if not FileAccess.file_exists(source):return _fail("inventoried texture source missing: "+source)
		var selected:=_normalize(str(row.get("selected_sidecar","")))
		var width:=int(row.get("width",0));var height:=int(row.get("height",0))
		if not selected.is_empty() and (width<=0 or height<=0):return _fail("inventoried sidecar dimensions missing")
		declarations[[source,bool(row.normal_role),bool(row.flip_normal_green)]]={"width":width,"height":height}
		var physical:=Compressed.sidecar_path(source,bool(row.flip_normal_green),bool(row.normal_role))
		var plan:=Compressed.plan(source,bool(row.flip_normal_green),bool(row.normal_role),source_root)
		if _normalize(physical)!=selected or (not selected.is_empty() and (plan.is_empty() or _normalize(str(plan.sidecar))!=selected or int(plan.width)!=int(row.width) or int(plan.height)!=int(row.height))):return _fail("inventoried sidecar changed or invalid: "+source)
		var variant_key:=[source,bool(row.normal_role),bool(row.flip_normal_green)]
		if variant_keys.has(variant_key):return _fail("duplicate texture variant")
		variant_keys[variant_key]=variant_rows.size()
		var baseline:=target_root.path_join(_relative(selected,source_root)) if not selected.is_empty() else ""
		variant_rows.append({"source":target,"normal":bool(row.normal_role),"flip":bool(row.flip_normal_green),"baseline_sidecar":baseline,"baseline_header":_dds_evidence(selected,plan),"candidate_sidecar":"","candidate_header":{}})
		if not selected.is_empty():
			if _relative(selected,source_root).is_empty() or not _sidecar_suffix_valid(source,selected,row.normal_role,row.flip_normal_green):return _fail("sidecar does not belong to inventoried role")
			sidecars[selected]=true
	for source:String in source_paths:
		var result:=_copy(source,mapping[source],target_root)
		if not result.ok:return result
		copied.append(result)
	for sidecar:String in sidecars:
		var result:=_copy(sidecar,target_root.path_join(_relative(sidecar,source_root)),target_root)
		if not result.ok:return result
		copied.append(result)
	var candidate_files:Array=[];var copied_blobs:Dictionary={};var staged_blobs:Dictionary={}
	for blob:Variant in staged.blobs:
		if not blob is Dictionary or not blob.get("path") is String or not blob.get("sha256") is String:return _fail("invalid staged blob")
		staged_blobs[blob.path]=blob
	for row:Variant in staged.targets:
		if not row is Dictionary or not row.get("source") is String or not row.get("target") is String or not row.get("blob") is String:return _fail("invalid staged target")
		var src:=pack_root.path_join(row.source).simplify_path();var dest:=pack_root.path_join(row.target).simplify_path();var blob_path:=stage_dir.path_join(row.blob).simplify_path()
		if not mapping.has(src) or _relative(dest,pack_root).is_empty() or _relative(blob_path,stage_dir).is_empty() or not staged_blobs.has(row.blob):return _fail("staged target escapes or mismatches inventory")
		var normal:bool=row.get("role","")=="normal";var flip:bool=row.get("flip",false)
		if row.get("role","") not in ["normal","color"] or not row.get("flip",null) is bool or not _sidecar_suffix_valid(src,dest,normal,flip) or not declarations.has([src,normal,flip]):return _fail("staged role not declared")
		var source_sha_now:=FileAccess.get_sha256(src);var blob:Dictionary=staged_blobs[row.blob]
		if source_sha_now!=row.get("source_sha256","") or blob.sha256!=row.get("blob_sha256","") or blob.get("source_sha256","")!=source_sha_now or blob.get("role","")!=row.role or blob.get("flip",null)!=flip:return _fail("staged source/blob identity mismatch")
		var staged_file:=FileAccess.open(blob_path,FileAccess.READ)
		if staged_file==null:return _fail("staged blob missing")
		var blob_size:=staged_file.get_length();var header:=Compressed._header(staged_file.get_buffer(mini(blob_size,148)),blob_size,normal);staged_file.close()
		var declared:Dictionary=declarations[[src,normal,flip]]
		var source_size:=_png_size(src)
		if header.is_empty() or source_size.x<=0 or source_size.y<=0 or int(header.width)!=source_size.x or int(header.height)!=source_size.y or int(blob.get("width",0))!=source_size.x or int(blob.get("height",0))!=source_size.y or (declared.width>0 and (declared.width!=source_size.x or declared.height!=source_size.y)):return _fail("staged sidecar header/role mismatch")
		var candidate:=target_root.path_join("candidate_blobs").path_join(row.blob.get_file())
		if not copied_blobs.has(row.blob):
			var copied_blob:=_copy(blob_path,candidate,target_root,blob.sha256)
			if not copied_blob.ok:return copied_blob
			copied_blobs[row.blob]=copied_blob;copied.append(copied_blob)
		var installed:=target_root.path_join(_relative(dest,source_root))
		if FileAccess.file_exists(installed):return _fail("candidate target already exists")
		var variant:Dictionary=variant_rows[variant_keys[[src,normal,flip]]]
		if not variant.candidate_sidecar.is_empty():return _fail("multiple candidates for one texture variant")
		variant.candidate_sidecar=installed;variant.candidate_header=_dds_evidence(blob_path,header)
		candidate_files.append({"source":mapping[src],"target":installed,"blob":candidate,"sha256":blob.sha256,"role":row.role,"flip":flip})
	var gltf:Variant=_json(source_map)
	if not gltf is Dictionary or not gltf.get("nodes") is Array or gltf.nodes.is_empty() or not gltf.nodes[0].get("extras") is Dictionary:return _fail("invalid source map structure")
	var extra:Dictionary=gltf.nodes[0].extras
	if not extra.get("rmmo_records") is Array or not extra.get("rmmo_resource_dependencies") is Dictionary:return _fail("missing compact reference closure")
	# Strict offline fixture read avoids creating any bundle/cache in source_root.
	var restored:=Store.read_records(extra.rmmo_records,source_map,source_root,extra.rmmo_resource_dependencies,1,false)
	if not restored.ok:return _fail("cannot read source records: "+str(restored.get("reason","")))
	var material_edits:=0;var prefab_edits:=0;var model_paths:Dictionary={}
	for record:Dictionary in restored.records:
		var changed:=false
		for material:Dictionary in Paint.definitions(record):
			for field:String in Paint.MAP_FIELDS:
				var path:=_normalize(str(material.get(field,"")))
				if path.is_empty():continue
				var is_normal:bool=field=="normal_path";var flip:bool=is_normal and material.get("normal_format","opengl")=="directx"
				if not mapping.has(path) or not declarations.has([path,is_normal,flip]):return _fail("material dependency missing from inventory: "+path)
				material[field]=mapping[path];material_edits+=1;changed=true
		if changed and record.has("house_prefab"):
			Prefab.retarget_materials(record);prefab_edits+=1
			if not _strict_prefab_valid(record):return _fail("retargeted prefab is invalid")
		if record.has("asset_path"):
			var old:=_normalize(str(record.asset_path));var relative:=_relative(old,source_root)
			if relative.is_empty():return _fail("asset outside source root: "+old)
			record.asset_path=target_root.path_join(relative)
			if not record.has("house_prefab") and (record.get("kind")=="asset" or record.has("model_building")):model_paths[old]=record.asset_path
		if record.has("fortification_art"):
			var art:Dictionary=record.fortification_art;var old:=_normalize(str(art.get("asset_path","")));var relative:=_relative(old,source_root)
			if relative.is_empty():return _fail("fortification asset outside source root")
			art.asset_path=target_root.path_join(relative)
			if not record.has("house_prefab") and art.get("module","")!="tower_stair":model_paths[old]=art.asset_path
	var native_files:Array=[]
	if not native_manifest_path.is_empty():
		if model_paths.size()!=expected_native.size():return _fail("native inventory count does not match map")
		for old:String in model_paths:
			if not expected_native.has(old):return _fail("native inventory does not cover model: "+old)
	if not model_paths.is_empty():
		var rekey:Script=load("res://tools/isolated_native_cache.gd")
		if rekey==null:return _fail("native cache rekey helper missing")
		Controls.enable_native_geometry_only()
		for old:String in model_paths:
			var result:Dictionary=rekey.rekey(old,model_paths[old],source_root,target_root)
			if not result.get("ok",false):return _fail("native cache rekey failed: "+old+" "+str(result.get("reason","")))
			if not native_manifest_path.is_empty():
				var expected:Dictionary=expected_native[old]
				if result.source_sha256!=expected.get("source_sha256","") or result.payload_sha256!=expected.get("product_sha256","") or result.product_bytes!=int(expected.get("bytes",-1)):return _fail("native product changed from inventory: "+old)
				for item:Dictionary in result.files:
					var field:String={"index":"index","metadata":"descriptor","payload":"product"}.get(item.kind,"")
					if field.is_empty() or item.source!=expected.get(field,"") or item.sha256!=expected.get(field+"_sha256",""):return _fail("native file changed from inventory: "+old)
			native_files.append(result)
	var map_relative:=_relative(source_map,source_root);var target_map:=target_root.path_join(map_relative)
	if DirAccess.make_dir_recursive_absolute(target_map.get_base_dir())!=OK:return _fail("cannot create map directory")
	var written:=Store.write_records(restored.records,target_map,target_root)
	if not written.ok:return _fail("cannot write target records: "+str(written.get("reason","")))
	extra.rmmo_records=written.records;extra.rmmo_resource_dependencies=written.dependencies
	var file:=FileAccess.open(target_map,FileAccess.WRITE)
	if file==null:return _fail("cannot write target map")
	file.store_string(JSON.stringify(gltf));file.close()
	if FileAccess.get_sha256(source_map)!=source_sha:return _fail("source map changed during build")
	var output:Dictionary={"ok":true,"source_map":source_map,"source_map_sha256":source_sha,"target_root":target_root,"target_map":target_map,"target_map_sha256":FileAccess.get_sha256(target_map),"record_count":restored.records.size(),"resource_count":written.dependencies.size(),"resource_dependencies":written.dependencies,"material_edits":material_edits,"prefab_edits":prefab_edits,"copied":copied,"native":native_files,"native_inventory":native_manifest_path,"native_inventory_sha256":native_manifest_sha,"audited_path_fields":audited_path_fields,"authoring_only_paths":authoring_paths,"texture_variants":variant_rows,"candidate_targets":candidate_files,"full_map_closure_verified":false,"contract":"Experimental mesh-only fixture: inventoried authoring provenance is preserved and is not an editor dependency closure; no OS-level IO trace has proved full process closure. Candidate sidecars are not installed; source files are not modified."}
	var manifest:=FileAccess.open(target_root.path_join("fixture_manifest.json"),FileAccess.WRITE)
	if manifest==null:return _fail("cannot write fixture manifest")
	manifest.store_string(JSON.stringify(output,"\t"));manifest.close()
	return output
