extends RefCounted
## A worker-only bridge from a collision Asset to a verified selected map
## namespace. No scene import, Mesh, texture or PhysicsServer work occurs here.
## Batch means source/selected-closure verified, never physics/render ready.
const Descriptor=preload("res://scripts/world3d/collision_asset_descriptor.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Proof=preload("res://scripts/world3d/dependency_index_proof.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Native=preload("res://scripts/world3d/native_model_product.gd")
const MAX_RECORDS:=32
const MAX_ASSETS:=8
const MAX_ROWS:=8192
const MAX_ESTIMATED_BYTES:=1024*1024*1024
const RECORD_FIELDS=["uuid","kind","position","rotation","size","collision","surface_id","asset_path","asset_id","asset_name","name","label","thumbnail_path","bounds_position","bounds_size","category","tags","editor_group","editor_group_name","editor_name","editor_hidden","editor_locked"]

class Batch extends RefCounted:
	var _sealed:=false
	var _path:=""
	var _sha:=""
	var _instances:Array=[]
	var _bytes:=0
	var _proof:RefCounted
	var _assets:Dictionary={}
	func map_path()->String:return _path if _sealed else ""
	func map_sha()->String:return _sha if _sealed else ""
	func instances()->Array:return _instances.duplicate(true) if _sealed else []
	func retained_bytes()->int:return _bytes if _sealed else 0

static func _fail(reason:String,cancelled:bool=false)->Dictionary:
	return {"ok":false,"reason":reason,"cancelled":cancelled,"fallback_required":not cancelled}
static func _cancelled(token:RefCounted)->bool:return token!=null and token.is_cancelled()

## Map authority is separate from model identity. Keep bounded map hashing
## here so the producer-only GLB audit helper is never called by consumers.
static func checked_map_identity(path:String,root:String,token:RefCounted)->Dictionary:
	if _cancelled(token):return _fail("cancelled",true)
	if path.get_extension().to_lower()!="gltf" or not Paths.allowed(path,root):return _fail("map_path")
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return _fail("map_missing")
	var length:=file.get_length();var left:=length
	var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256)
	while left>0:
		if _cancelled(token):return _fail("cancelled",true)
		var bytes:=file.get_buffer(mini(left,Descriptor.HASH_BLOCK_BYTES))
		if bytes.is_empty():return _fail("map_read")
		hash_.update(bytes);left-=bytes.size()
	if file.get_length()!=length or file.get_error() not in [OK,ERR_FILE_EOF]:return _fail("map_changed")
	file.close()
	if _cancelled(token):return _fail("cancelled",true)
	if not Paths.allowed(path,root):return _fail("map_path")
	return {"ok":true,"sha":hash_.finish().hex_encode()}

## Small published facts only. Shared by geometry and explicit-none workers;
## no optional source GLB or graphical resource is opened here.
static func published_model(path:String,root:String)->Dictionary:
	var metadata:=Native.read(path,root)
	if metadata.is_empty():return {}
	return {"source_sha":metadata.native_source_sha,"payload_sha":metadata.native_payload_sha,
		"json_sha256":metadata.json_sha256,"file_length":metadata.file_length,"local_bounds":metadata.local_bounds,
		"none_safe":bool(metadata.get("native_candidate",{}).get("collision_none_safe",false))}

static func _positions(index:Dictionary,requested:Array,path:String,root:String,proof:Proof)->Dictionary:
	# A dictionary with a matching checksum is not an ownership receipt. Only
	# the current Index reader can issue a proof for this exact sealed directory.
	if proof==null or not Index.validate_index_ownership(index,root,proof,path):return _fail("index_proof")
	if requested.is_empty() or requested.size()>MAX_RECORDS or not Paths.allowed(path,root):return _fail("request")
	var positions:Array=[];var seen:Dictionary={}
	for entry:Variant in requested:
		if not entry is Dictionary or not entry.get("record_index") is int:return _fail("entry")
		var at:int=entry.record_index
		if at<0 or at>=index.rows.size() or seen.has(at):return _fail("record_index")
		var row:Dictionary=index.rows[at];var source:Dictionary=index.extras.rmmo_records[at]
		if entry.get("compact_record")!=source or entry.get("bounds")!=row.bounds or entry.get("group_id","")!=row.group_id or entry.get("asset_path","")!=row.asset_path:return _fail("entry_identity")
		# Whole buildings/fixtures/unknown bounds remain on the full pipeline.
		if not row.group_id.is_empty() or not row.owner_keys.is_empty() or row.reason!="model_accessor_bounds" or not row.bounds_known or row.asset_path.is_empty():return _fail("unsupported_record")
		seen[at]=true;positions.append(at)
	positions.sort()
	return {"ok":true,"positions":positions}

static func _reference_charge(compact:Array,path:String,root:String)->Dictionary:
	var headers:Dictionary={};var bytes:=0
	for record:Dictionary in compact:
		var ref:Dictionary=record.rmmo_ref
		var location:=Store._location(ref.uri,ref.sha256,path,root)
		if location.is_empty():return _fail("reference_path")
		if not headers.has(location):
			var file:=FileAccess.open(location,FileAccess.READ)
			if file==null or file.get_length()<16 or file.get_length()>Store.MAX_FILE_BYTES:return _fail("reference_length")
			var length:=file.get_length();var header:=file.get_buffer(16);file.close()
			if header.size()!=16 or header.slice(0,8).get_string_from_ascii()!=Store.MAGIC:return _fail("reference_header")
			var raw:int=header.decode_u64(8)
			if raw<=0 or raw>Store.MAX_RAW_BYTES:return _fail("reference_raw_length")
			headers[location]={"raw":raw,"length":length}
			# Compressed buffers, raw decode and expanded Variant containers.
			# The later Store SHA check binds this header before any decompression.
			bytes+=length*2+raw*16+65536
		# Each restored instance owns a separate definition container copy.
		bytes+=int(headers[location].raw)*16+65536
		if bytes>MAX_ESTIMATED_BYTES:return _fail("reference_budget")
	return {"ok":true,"bytes":bytes,"headers":headers}

static func plan(index:Dictionary,requested_entries:Array,path:String,root:String,ownership_proof:Proof)->Dictionary:
	if not Descriptor.Products._worker():return _fail("worker_required")
	var checked:=_positions(index,requested_entries,path,root,ownership_proof)
	if not checked.ok:return checked
	var compact:Array=[];var candidates:Dictionary={};var models:Dictionary={};var retained:=0;var metadata_bytes:=0
	for at:int in checked.positions:
		compact.append(index.extras.rmmo_records[at])
		var asset:String=index.rows[at].asset_path
		if not candidates.has(asset):
			if candidates.size()>=MAX_ASSETS:return _fail("asset_limit")
			var candidate:=Descriptor.candidate(asset,root)
			if candidate.is_empty():return _fail("collision_asset_missing")
			var model:=published_model(asset,root)
			if model.is_empty() or model.source_sha!=candidate.source_sha:return _fail("native_product_missing_or_changed")
			models[asset]=model
			candidates[asset]=candidate;retained+=int(candidate.retained_bytes)
		# Descriptor byte length bounds its names, selectors and pose rows. Charge
		# expanded containers and copied instance metadata per placement, even
		# when the underlying PackedFaces are uniquely shared between placements.
		metadata_bytes+=maxi(65536,int(candidates[asset].descriptor_bytes)*32)
	var references:=_reference_charge(compact,path,root)
	if not references.ok:return references
	# One sequential product reader workspace; unique outputs persist across
	# instances. Metadata comes from validated bounded envelope/file lengths,
	# rather than an untrusted caller row count or compressed-file multiplier.
	var estimate:int=Descriptor.WORKSPACE_BYTES+retained+int(references.bytes)+metadata_bytes
	if estimate>MAX_ESTIMATED_BYTES:return _fail("batch_budget")
	return {"ok":true,"index":index,"proof":ownership_proof,"path":path,"root":root,
		"requested":requested_entries.duplicate(true),"positions":checked.positions,
		"candidates":candidates,"native_models":models,"reference_headers":references.headers,
		"estimated_bytes":estimate,"retained_upper_bytes":retained+int(references.bytes)+metadata_bytes}

static func _supported_record(record:Dictionary)->bool:
	if record.get("kind")!="asset" or record.get("collision","") not in ["","none","walk","block"]:return false
	for key in record:
		if key not in RECORD_FIELDS:return false
	# surface_id is a palette selection for generated primitives, not an
	# override in WorldDocument._asset. Source Mesh interaction extras are
	# separately rejected by Descriptor v2 before a directory is written.
	return true

static func prepare(prepared_plan:Dictionary,admitted_bytes:int,token:RefCounted=null)->Dictionary:
	if not Descriptor.Products._worker():return _fail("worker_required")
	if _cancelled(token):return _fail("cancelled",true)
	if not prepared_plan.get("ok",false) or not prepared_plan.get("index") is Dictionary or not prepared_plan.get("requested") is Array or not prepared_plan.get("proof") is Proof:return _fail("plan")
	var path:String=str(prepared_plan.get("path",""));var root:String=str(prepared_plan.get("root",""))
	var index:Dictionary=prepared_plan.index;var proof:Proof=prepared_plan.proof
	# Recompute file/header-based admission and frozen descriptor identities;
	# changing a scalar estimate or a dictionary hint never grants a budget.
	var current:=plan(index,prepared_plan.requested,path,root,proof)
	if not current.ok:return current
	for key:String in ["positions","candidates","native_models","reference_headers","estimated_bytes","retained_upper_bytes"]:
		if current[key]!=prepared_plan.get(key):return _fail("plan_changed")
	if admitted_bytes<int(current.estimated_bytes):return _fail("budget_not_admitted")
	var map_source:=checked_map_identity(path,root,token)
	if not map_source.ok:return map_source
	if map_source.sha!=index.source_sha256:return _fail("map_changed")
	var compact:Array=[];var dependencies:Dictionary={}
	for at:int in current.positions:
		var source:Dictionary=index.extras.rmmo_records[at]
		compact.append(source);dependencies[source.rmmo_ref.uri]=source.rmmo_ref.sha256
	var trusted_package:=preload("res://scripts/world3d/runtime_package_policy.gd").trusted()
	var restored:=Store.read_records(compact,path,root,dependencies,1,trusted_package)
	if not restored.get("ok",false):return _fail("reference:"+str(restored.get("reason","")))
	if _cancelled(token):return _fail("cancelled",true)
	var material_checks:Dictionary={};var asset_paths:Dictionary={};var ids:Dictionary={};var manifests:Dictionary=current.native_models.duplicate()
	for asset_path:String in current.native_models:asset_paths[asset_path]=true
	for i:int in restored.records.size():
		var record:Dictionary=restored.records[i];var expected:Dictionary=index.rows[current.positions[i]]
		if not _supported_record(record):return _fail("unsupported_record_semantics")
		var issue:=Cursor.asset_record_issue(record,material_checks,compact[i].rmmo_ref.sha256,asset_paths,root)
		if issue.is_empty():issue=Cursor.document_record_issue(record,ids)
		if not issue.is_empty():return _fail("record:"+issue)
		var actual:=Index._classify(record,root,manifests,{},true)
		if actual.reason!="model_accessor_bounds" or not actual.owner_keys.is_empty() or not actual.bounds_known or not actual.bounds.is_equal_approx(expected.bounds) or actual.asset_path!=expected.asset_path:return _fail("record_geometry_identity")
	var ownership:=Index.validate_selected(index,restored.records,root,proof)
	if not ownership.ok:return _fail("selected_closure:"+str(ownership.reason))
	var assets:Dictionary={};var retained:=0
	for asset_path:String in current.candidates:
		var candidate:Dictionary=current.candidates[asset_path]
		var result:=Descriptor.read(candidate,root,int(candidate.estimated_bytes),token)
		if not result.ok:return result
		assets[asset_path]=result.asset;retained+=result.asset.retained_bytes()
	var instances:Array=[];var row_count:=0;var uuids:Dictionary={}
	for i:int in restored.records.size():
		if _cancelled(token):return _fail("cancelled",true)
		var record:Dictionary=restored.records[i];var asset:Descriptor.Asset=assets[record.asset_path]
		var pose:=record_pose(record)
		if not Descriptor._finite_pose(pose):return _fail("record_transform")
		var rows:Array=[]
		for entry:Dictionary in asset.entries():
			row_count+=1
			if row_count>MAX_ROWS:return _fail("row_limit")
			var geometry:=asset.geometry(int(entry.product))
			var uuid:String=str(record.uuid)+"__"+entry.node_path.replace("/","__")
			if uuids.has(uuid):return _fail("namespace_collision")
			uuids[uuid]=true
			var mode:String=str(record.get("collision",""))
			if mode.is_empty():mode=entry.collision
			var transform:Transform3D=pose*entry.transform
			if not Descriptor._finite_pose(transform):return _fail("instance_transform")
			rows.append({"uuid":uuid,"selector":entry.selector,"transform":transform,"collision":mode,
				"kind":geometry.kind,"faces":geometry.faces,"box":geometry.box,"bounds":geometry.bounds})
		instances.append({"uuid":record.uuid,"record_index":current.positions[i],"record_sha":compact[i].rmmo_ref.sha256,
			"asset_path":record.asset_path,"source_sha":asset.source_sha(),"pose":pose,
			"record_identity":compact[i].duplicate(true),"rows":rows})
	# Recheck one published source/payload identity per unique model. Never open
	# authoring GLB; selected rmres/map authority remains separately required.
	for asset_path:String in assets:
		if _cancelled(token):return _fail("cancelled",true)
		if published_model(asset_path,root)!=current.native_models[asset_path]:return _fail("native_product_changed")
	if not trusted_package and not Store.verify_dependencies(dependencies,path,root,1):return _fail("reference_changed")
	map_source=checked_map_identity(path,root,token)
	if not map_source.ok:return map_source
	if map_source.sha!=index.source_sha256 or not Index.validate_index_ownership(index,root,proof,path):return _fail("map_changed")
	if _cancelled(token):return _fail("cancelled",true)
	var batch:=Batch.new();batch._path=path;batch._sha=map_source.sha;batch._instances=instances
	# Keep the admitted metadata/container upper bound while the Batch lives;
	# callers must not discount a shared Asset until all its consumers release.
	batch._bytes=int(current.retained_upper_bytes)
	batch._proof=proof;batch._assets=assets;batch._sealed=true
	return {"ok":true,"batch":batch,"estimated_bytes":current.estimated_bytes,"retained_bytes":batch.retained_bytes(),"selected_closure_verified":true,"closure_complete":false,"render_imports":0,"image_decodes":0}

static func record_pose(record:Dictionary)->Transform3D:
	# Match Node3D.rotation_degrees exactly: one real_t vector multiplication.
	# Multiplying by PI and then dividing rounds twice; scalar deg_to_rad uses
	# GDScript doubles and also differs from the engine's float vector path.
	return Transform3D(Basis.from_euler(Index._vec(record.rotation)*(PI/180.0)).scaled_local(Index._vec(record.size)),Index._vec(record.position))
