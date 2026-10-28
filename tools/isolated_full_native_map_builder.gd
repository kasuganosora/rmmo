extends SceneTree
## Builds a private, full-material copy of an authored map. Only serialized
## roots and prefab-internal texture roots change. Original products stay put.
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Product=preload("res://scripts/world3d/native_model_product.gd")
const Compressed=preload("res://scripts/world3d/compressed_texture_source.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const REVIEW_ROOT:="D:/code/rmmo_runtime/review_artifacts"

static func _fail(reason:String)->Dictionary:return {"ok":false,"error":reason}
static func _norm(path:String)->String:return "" if path.is_empty() else path.replace("\\","/").simplify_path().trim_suffix("/")
static func _relative(path:String,root:String)->String:
	path=_norm(path);root=_norm(root)
	if not Paths.allowed(path,root) or not path.to_lower().begins_with(root.to_lower()+"/"):return ""
	return path.substr(root.length()+1)

# Only schema-declared runtime resource fields are paths. Do not rewrite an
# unrelated note/provenance string just because it happens to contain a path.
static func _replace_path(value:Variant,from:String,to:String)->Variant:
	if not value is String:return value
	var normalized:=str(value).replace("\\","/")
	return to+normalized.substr(from.length()) if normalized.to_lower().begins_with(from.to_lower()+"/") else value

static func _relocate_record(record:Dictionary,from:String,to:String)->Dictionary:
	var copy:=record.duplicate(true)
	if copy.has("asset_path"):copy.asset_path=_replace_path(copy.asset_path,from,to)
	if copy.has("fortification_art") and copy.fortification_art is Dictionary and copy.fortification_art.has("asset_path"):
		copy.fortification_art.asset_path=_replace_path(copy.fortification_art.asset_path,from,to)
	for material:Dictionary in Paint.definitions(copy):
		for field:String in Paint.MAP_FIELDS:
			if material.has(field):material[field]=_replace_path(material[field],from,to)
	return copy

static func _record_semantics(record:Dictionary,root:String)->Dictionary:
	var copy:=_relocate_record(record,root,"$ROOT")
	if copy.has("house_prefab"):
		var data:=Prefab.decode(copy.house_prefab)
		if data.is_empty():return {"ok":false,"reason":"prefab_decode"}
		# Encoded packet hash/length necessarily change when a texture path moves;
		# compare all decoded geometry and material values, normalizing only paths.
		for material:Dictionary in data.get("materials",[]):
			var paint:Variant=material.get("paint")
			if paint is Dictionary:
				for field:String in Paint.MAP_FIELDS:
					if paint.has(field):paint[field]=_replace_path(paint[field],root,"$ROOT")
		copy.house_prefab=data
	return {"ok":true,"value":copy}

# Preserve original JSON bytes outside the two unique reference members. Godot's
# default JSON writer rounds unrelated floats, including editor bookmarks.
static func _json_value_end(text:String,start:int)->int:
	if start<0 or start>=text.length() or text.unicode_at(start) not in [91,123]:return -1
	var depth:=0;var quoted:=false;var escaped:=false
	for i:int in range(start,text.length()):
		var ch:=text.unicode_at(i)
		if quoted:
			if escaped:escaped=false
			elif ch==92:escaped=true
			elif ch==34:quoted=false
		elif ch==34:quoted=true
		elif ch==91 or ch==123:depth+=1
		elif ch==93 or ch==125:
			depth-=1
			if depth==0:return i+1
	return -1

static func _replace_member(text:String,key:String,expected:Variant,replacement:Variant)->String:
	var token:=JSON.stringify(key)
	if text.count(token)!=1:return ""
	var cursor:=text.find(token)+token.length()
	while cursor<text.length() and text.unicode_at(cursor) in [9,10,13,32]:cursor+=1
	if cursor>=text.length() or text.unicode_at(cursor)!=58:return ""
	cursor+=1
	while cursor<text.length() and text.unicode_at(cursor) in [9,10,13,32]:cursor+=1
	var end:=_json_value_end(text,cursor)
	if end<0 or JSON.parse_string(text.substr(cursor,end-cursor))!=expected:return ""
	return text.substr(0,cursor)+JSON.stringify(replacement,"",false,true)+text.substr(end)

static func _copy(source:String,target:String,target_root:String)->Dictionary:
	if _relative(source,target_root)!="":return _fail("source and target overlap")
	if _relative(target,target_root).is_empty() or not FileAccess.file_exists(source):return _fail("missing texture or target outside staging: "+source)
	var source_sha:=FileAccess.get_sha256(source)
	if source_sha.is_empty():return _fail("texture unreadable: "+source)
	if FileAccess.file_exists(target):
		if FileAccess.get_sha256(target)!=source_sha:return _fail("target conflicts: "+target)
	else:
		if DirAccess.make_dir_recursive_absolute(target.get_base_dir())!=OK or DirAccess.copy_absolute(source,target)!=OK:return _fail("texture copy failed: "+source)
		if FileAccess.get_sha256(target)!=source_sha or FileAccess.get_sha256(source)!=source_sha:return _fail("texture changed while copying: "+source)
	var file:=FileAccess.open(target,FileAccess.READ)
	return {"ok":true,"source":source,"target":target,"sha256":source_sha,"bytes":file.get_length() if file!=null else -1}

static func build(source_map:String,source_root:String,target_root:String,audit_path:String,target_name:String="")->Dictionary:
	source_map=_norm(source_map);source_root=_norm(source_root);target_root=_norm(target_root);audit_path=_norm(audit_path)
	if not Thread.is_main_thread():return _fail("builder requires main thread")
	if Controls.discard_map_textures:return _fail("full material mode required")
	if _relative(source_map,source_root).is_empty() or not FileAccess.file_exists(source_map):return _fail("source map is invalid")
	if _relative(target_root,REVIEW_ROOT).is_empty() or not DirAccess.dir_exists_absolute(target_root) or not Paths.allowed(audit_path,REVIEW_ROOT):return _fail("staging or audit outside review root")
	var target_map:=target_root.path_join(_relative(source_map,source_root));var manifest_path:=target_root.path_join("full_fixture_manifest.json")
	if not target_name.is_empty():
		if target_name.get_file()!=target_name or target_name.get_extension().to_lower()!="gltf":return _fail("invalid alternate target map name")
		target_map=target_map.get_base_dir().path_join(target_name)
	if FileAccess.file_exists(target_map) or FileAccess.file_exists(manifest_path):return _fail("target map or manifest already exists")
	var map_sha:=FileAccess.get_sha256(source_map)
	var audit:Variant=JSON.parse_string(FileAccess.get_file_as_string(audit_path))
	if not audit is Dictionary or _norm(str(audit.get("map","")))!=source_map or audit.get("current_map_sha256")!=map_sha or not audit.get("fixture_native_model_identity") is Dictionary:return _fail("map audit does not match source")
	var source_text:=FileAccess.get_file_as_string(source_map)
	var source_document:Variant=JSON.parse_string(source_text)
	if not source_document is Dictionary or not source_document.get("nodes") is Array or source_document.nodes.is_empty() or not source_document.nodes[0].get("extras") is Dictionary:return _fail("source map structure")
	var extra:Dictionary=source_document.nodes[0].extras
	if not extra.get("rmmo_records") is Array or not extra.get("rmmo_resource_dependencies") is Dictionary:return _fail("missing source resource references")
	var restored:=Store.read_records(extra.rmmo_records,source_map,source_root,extra.rmmo_resource_dependencies,1,false)
	if not restored.get("ok",false):return _fail("cannot read source records: "+str(restored.get("reason","")))
	if restored.records.size()!=int(audit.get("source_record_count",-1)):return _fail("record count differs from audit")
	var original:Array=restored.records;var relocated:Array=[];var model_paths:Dictionary={};var texture_files:Dictionary={};var variant_rows:Array=[];var variants:Dictionary={}
	var prefab_count:=0
	for record:Dictionary in original:
		var moved:Dictionary=_relocate_record(record,source_root,target_root)
		if record.has("house_prefab") and moved.get("prefab_materials",[])!=record.get("prefab_materials",[]):
			if not Prefab.valid(record):return _fail("source prefab invalid: "+str(record.uuid))
			Prefab.retarget_materials(moved);prefab_count+=1
			if not Prefab.valid(moved):return _fail("relocated prefab invalid: "+str(record.uuid))
		var before:=_record_semantics(record,source_root);var after:=_record_semantics(moved,target_root)
		if not before.ok or not after.ok or before.value!=after.value:return _fail("record differs beyond path relocation: "+str(record.uuid))
		relocated.append(moved)
		if record.get("kind")=="asset" and not record.has("house_prefab"):
			var old:=_norm(str(record.get("asset_path","")));var relative:=_relative(old,source_root)
			if relative.is_empty():return _fail("model outside source root: "+old)
			model_paths[old]=target_root.path_join(relative)
		if record.has("fortification_art") and not record.has("house_prefab") and record.fortification_art.get("module","")!="tower_stair":
			var old:=_norm(str(record.fortification_art.get("asset_path","")));var relative:=_relative(old,source_root)
			if relative.is_empty():return _fail("fortification outside source root: "+old)
			model_paths[old]=target_root.path_join(relative)
		for material:Dictionary in Paint.definitions(record):
			for field:String in Paint.MAP_FIELDS:
				var source:=_norm(str(material.get(field,"")))
				if source.is_empty():continue
				var relative:=_relative(source,source_root)
				if relative.is_empty():return _fail("texture outside source root: "+source)
				texture_files[source]=target_root.path_join(relative)
				var normal:bool=field=="normal_path";var flip:bool=normal and material.get("normal_format","opengl")=="directx"
				var key:=[source,normal,flip]
				if variants.has(key):continue
				variants[key]=true
				var sidecar:=Compressed.sidecar_path(source,flip,normal)
				if not sidecar.is_empty():
					var sidecar_relative:=_relative(sidecar,source_root)
					if sidecar_relative.is_empty():return _fail("sidecar outside source root: "+sidecar)
					texture_files[sidecar]=target_root.path_join(sidecar_relative)
				variant_rows.append({"source":source,"target":target_root.path_join(relative),"normal":normal,"flip":flip,"sidecar":target_root.path_join(_relative(sidecar,source_root)) if not sidecar.is_empty() else ""})
	var audited:Dictionary=audit.fixture_native_model_identity
	if model_paths.size()!=audited.size():return _fail("runtime model set does not match map audit")
	var models:Array=[];var product_hashes:Dictionary={}
	for old:String in model_paths:
		if not audited.has(old):return _fail("runtime model absent from audit: "+old)
		var logical:String=model_paths[old];var metadata:=Product.read(logical,target_root)
		if metadata.is_empty() or metadata.get("native_source_sha")!=audited[old]:return _fail("missing or mismatched staged full native product: "+old)
		var product_path:String=metadata.native_product_path
		if not product_hashes.has(product_path):product_hashes[product_path]=FileAccess.get_sha256(product_path)
		if product_hashes[product_path]!=metadata.native_payload_sha:return _fail("staged native product bytes do not match published identity: "+old)
		models.append({"source":old,"logical_source":logical,"source_sha256":metadata.native_source_sha,"product_path":product_path,"payload_sha256":metadata.native_payload_sha,"product_bytes":metadata.native_product_bytes,"index_path":metadata.native_index_path,"index_sha256":FileAccess.get_sha256(metadata.native_index_path),"descriptor_path":metadata.native_descriptor_path,"descriptor_sha256":FileAccess.get_sha256(metadata.native_descriptor_path)})
	var copied:Array=[]
	for source:String in texture_files:
		var row:=_copy(source,texture_files[source],target_root)
		if not row.get("ok",false):return row
		copied.append(row)
	if DirAccess.make_dir_recursive_absolute(target_map.get_base_dir())!=OK:return _fail("cannot create target map folder")
	var written:=Store.write_records(relocated,target_map,target_root)
	if not written.get("ok",false):return _fail("cannot write relocated records: "+str(written.get("reason","")))
	var target_text:=_replace_member(source_text,"rmmo_records",extra.rmmo_records,written.records)
	if target_text.is_empty():return _fail("cannot locate unique original record member")
	target_text=_replace_member(target_text,"rmmo_resource_dependencies",extra.rmmo_resource_dependencies,written.dependencies)
	if target_text.is_empty():return _fail("cannot locate unique original dependency member")
	var file:=FileAccess.open(target_map,FileAccess.WRITE)
	if file==null:return _fail("cannot write target map")
	file.store_string(target_text);file.flush();var error:=file.get_error();file.close()
	if error!=OK:return _fail("target map write failed")
	var disk_document:Variant=JSON.parse_string(FileAccess.get_file_as_string(target_map))
	if not disk_document is Dictionary or not disk_document.get("nodes") is Array or disk_document.nodes.is_empty() or not disk_document.nodes[0].get("extras") is Dictionary:return _fail("target map cannot be reopened")
	var source_except_records:Dictionary=source_document.duplicate(true);var target_except_records:Dictionary=disk_document.duplicate(true)
	for document:Dictionary in [source_except_records,target_except_records]:
		document.nodes[0].extras.erase("rmmo_records");document.nodes[0].extras.erase("rmmo_resource_dependencies")
	if source_except_records!=target_except_records:return _fail("map metadata differs beyond regenerated reference closure")
	var target_extra:Dictionary=disk_document.nodes[0].extras
	var reopened:=Store.read_records(target_extra.rmmo_records,target_map,target_root,target_extra.rmmo_resource_dependencies,1,false)
	if not reopened.get("ok",false) or reopened.records.size()!=original.size():return _fail("target records cannot be reopened")
	var differences:Array=[]
	for i:int in original.size():
		var before:=_record_semantics(original[i],source_root);var after:=_record_semantics(reopened.records[i],target_root)
		if not before.ok or not after.ok or before.value!=after.value:differences.append({"index":i,"uuid":str(original[i].get("uuid",""))})
	if not differences.is_empty():return _fail("reopened records differ after root normalization: "+JSON.stringify(differences.slice(0,10)))
	if FileAccess.get_sha256(source_map)!=map_sha:return _fail("source map changed during build")
	var result:={"ok":true,"scope":"full_native_model_materials","source_map":source_map,"source_map_sha256":map_sha,"target_root":target_root,"target_map":target_map,"target_map_sha256":FileAccess.get_sha256(target_map),"record_count":original.size(),"models":models,"textures":copied,"texture_variants":variant_rows,"resource_count":written.dependencies.size(),"resource_dependencies":written.dependencies,"offline_product_sha_verified":true,"unique_products_verified":product_hashes.size(),"relocation_semantics_verified":true,"relocation_semantics_scope":{"record_count":original.size(),"different_records":0,"method":"reopen every record; normalize schema-declared model/material roots and compare all fields, decoded prefab data including geometry and all material parameters","prefab_packets_retargeted":prefab_count,"material_parameters_rewritten":false,"map_metadata_except_reference_closure_equal":true},"limits":"Only files referenced by runtime material definitions and their selected existing DDS sidecars are copied. Editor/reference provenance paths remain unchanged and are not claimed as an editor closure. Native model content is bound to staged published full products; source GLB removal is a separate staging step."}
	file=FileAccess.open(manifest_path,FileAccess.WRITE)
	if file==null:return _fail("cannot write full fixture manifest")
	file.store_string(JSON.stringify(result,"\t"));file.flush();error=file.get_error();file.close()
	if error!=OK:return _fail("manifest write failed")
	return result

func _initialize()->void:
	var args:Dictionary={}
	for raw:String in OS.get_cmdline_user_args():
		if raw.begins_with("--") and raw.contains("="):
			args[raw.get_slice("=",0).trim_prefix("--")]=raw.substr(raw.find("=")+1)
	var result:=build(str(args.get("source-map","")),str(args.get("source-root","")),str(args.get("target-root","")),str(args.get("audit","")),str(args.get("map-name","")))
	print("FULL_NATIVE_MAP_BUILD ",JSON.stringify({"ok":result.get("ok",false),"error":result.get("error",""),"target_map":result.get("target_map",""),"record_count":result.get("record_count",0),"models":result.get("models",[]).size()}))
	quit(0 if result.get("ok",false) else 1)
