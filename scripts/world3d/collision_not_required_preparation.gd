extends RefCounted
## Worker-only, record-scoped absence proof. This is neither a geometry Batch
## nor render/physics readiness. No model import, image decode or face expansion.
const Adapter=preload("res://scripts/world3d/collision_instance_preparation.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Ownership=preload("res://scripts/world3d/dependency_index_proof.gd")
const Manifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Source=preload("res://scripts/world3d/collision_asset_descriptor.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const MAX_RECORDS:=32
const MAX_ESTIMATED_BYTES:=512*1024*1024
const WORKSPACE_BYTES:=32*1024*1024
const RECEIPT_BYTES:=65536
const VERSION:=1
const VISUAL_EXTRAS=["uuid","rmmo_collision","rmmo_grass","rmmo_leaf_backlight","rmmo_visibility_range","rmmo_wind"]

class Receipt extends RefCounted:
	static var _issuer:=RefCounted.new()
	var _seal:RefCounted
	var _ownership:Ownership
	var _index:Dictionary
	var _path:=""
	var _root:=""
	var _map_sha:=""
	var _asset:=""
	var _source_sha:=""
	var _record:Dictionary
	var _at:=-1
	var _bounds:=AABB()
	var _pose:=Transform3D.IDENTITY
	func _valid()->bool:return _seal!=null and is_same(_seal,_issuer)
	func uuid()->String:return str(_record.get("uuid","")) if _valid() else ""
	func map_path()->String:return _path if _valid() else ""
	func map_sha()->String:return _map_sha if _valid() else ""
	func asset_path()->String:return _asset if _valid() else ""
	func source_sha()->String:return _source_sha if _valid() else ""
	func record_index()->int:return _at if _valid() else -1
	func record_sha()->String:return str(_record.rmmo_ref.sha256) if _valid() else ""
	func record_identity()->Dictionary:return _record.duplicate(true) if _valid() else {}
	func bounds()->AABB:return _bounds if _valid() else AABB()
	func pose()->Transform3D:return _pose if _valid() else Transform3D.IDENTITY
	func rule_version()->int:return VERSION if _valid() else 0
	# The sealed catalog/compact record is borrowed, not copied or discounted by
	# this receipt. No restored definition, source JSON or source buffer survives.
	func retained_bytes()->int:return RECEIPT_BYTES if _valid() else 0
	func matches_context(index:Dictionary,path:String,root:String,proof:Ownership)->bool:
		return _valid() and path==_path and root==_root and is_same(index,_index) and is_same(proof,_ownership) and Index.validate_index_ownership(index,root,proof,path) and index.source_sha256==_map_sha
	func matches_entry(entry:Dictionary)->bool:
		return _valid() and entry.get("record_index")==_at and entry.get("asset_path")==_asset and entry.get("bounds")==_bounds and entry.get("group_id","")=="" and entry.get("compact_record")==_record

static func _worker()->bool:return OS.get_thread_caller_id()!=OS.get_main_thread_id()
static func _fail(reason:String,cancelled:bool=false)->Dictionary:
	return {"ok":false,"reason":reason,"cancelled":cancelled,"fallback_required":not cancelled}
static func _cancelled(token:RefCounted)->bool:return token!=null and token.is_cancelled()

static func _checked_hash(path:String,root:String,token:RefCounted,phase:String)->Dictionary:
	var began:=Time.get_ticks_usec() if Trace.enabled else 0
	var result:=Source._hash_source(path,root,token)
	if Trace.enabled:Trace.elapsed("collision.none."+phase,began,{"path":path,"ok":result.get("ok",false)})
	return result

static func _source_header(path:String,root:String)->Dictionary:
	if not Paths.allowed(path,root) or path.get_extension().to_lower()!="glb":return _fail("source_path")
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()<28:return _fail("source_header")
	var length:=file.get_length();var header:=file.get_buffer(20);file.close()
	if header.size()!=20 or header.decode_u32(0)!=0x46546c67 or header.decode_u32(4)!=2 or header.decode_u32(8)!=length or header.decode_u32(16)!=0x4e4f534a:return _fail("source_header")
	var json_bytes:int=header.decode_u32(12)
	if json_bytes<4 or json_bytes>Manifest.MAX_JSON or json_bytes%4!=0 or json_bytes+28>length:return _fail("source_json_limit")
	return {"ok":true,"file_length":length,"json_bytes":json_bytes}

static func plan(index:Dictionary,entries:Array,path:String,root:String,proof:Ownership)->Dictionary:
	if not _worker():return _fail("worker_required")
	if entries.is_empty() or entries.size()>MAX_RECORDS:return _fail("request_limit")
	var checked:=Adapter._positions(index,entries,path,root,proof)
	if not checked.ok:return checked
	var compact:Array=[];var asset:=""
	for at:int in checked.positions:
		var candidate:String=index.rows[at].asset_path
		if not asset.is_empty() and candidate!=asset:return _fail("mixed_sources")
		asset=candidate;compact.append(index.extras.rmmo_records[at])
	var references:=Adapter._reference_charge(compact,path,root)
	if not references.ok:return references
	var header:=_source_header(asset,root)
	if not header.ok:return header
	if not index.models.has(asset) or int(index.models[asset].file_length)!=header.file_length:return _fail("source_manifest_changed")
	# One source JSON, including parser containers, traversal scratch and result
	# copies; no compressed-image or vertex decoding. SHA uses bounded blocks.
	var estimate:int=WORKSPACE_BYTES+header.json_bytes*64+int(references.bytes)+compact.size()*RECEIPT_BYTES
	if estimate>MAX_ESTIMATED_BYTES:return _fail("batch_budget")
	return {"ok":true,"index":index,"proof":proof,"path":path,"root":root,"requested":entries.duplicate(true),"positions":checked.positions,"asset_path":asset,"source_header":header,"reference_headers":references.headers,"estimated_bytes":estimate,"retained_upper_bytes":compact.size()*RECEIPT_BYTES}

static func _supported(record:Dictionary)->bool:
	if not record.has("collision") or record.collision!="none" or not Adapter._supported_record(record):return false
	return true

static func _visual_metadata(value:Variant,depth:int=0)->bool:
	if depth>64:return false
	if value is Dictionary:
		for key:Variant in value:
			if key=="extras":
				if not value[key] is Dictionary:return false
				for field:Variant in value[key]:
					if field not in VISUAL_EXTRAS:return false
			if not _visual_metadata(value[key],depth+1):return false
	elif value is Array:
		for child:Variant in value:
			if not _visual_metadata(child,depth+1):return false
	return true

static func _manifest(path:String,root:String,header:Dictionary)->Dictionary:
	# Read only the admitted JSON envelope from this file handle. A larger
	# replacement must be rejected before allocating/parsing its larger JSON.
	if not Paths.allowed(path,root):return _fail("source_path")
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()!=header.file_length:return _fail("source_changed")
	var current:=file.get_buffer(20)
	if current.size()!=20 or current.decode_u32(0)!=0x46546c67 or current.decode_u32(4)!=2 or current.decode_u32(8)!=header.file_length or current.decode_u32(12)!=header.json_bytes or current.decode_u32(16)!=0x4e4f534a:return _fail("source_changed")
	var bytes:=file.get_buffer(header.json_bytes);var bin_header:=file.get_buffer(8);file.close()
	if bytes.size()!=header.json_bytes or bin_header.size()!=8 or bin_header.decode_u32(4)!=0x004e4942 or bin_header.decode_u32(0)%4!=0 or header.json_bytes+28+bin_header.decode_u32(0)!=header.file_length:return _fail("source_changed")
	var parsed:=JSON.new()
	if parsed.parse(bytes.get_string_from_utf8())!=OK or not parsed.data is Dictionary:return _fail("source_json")
	if not _visual_metadata(parsed.data):return _fail("unsupported_source_semantics")
	var manifest:=Manifest.from_json(parsed.data,bin_header.decode_u32(0))
	if not manifest.get("known",false):return _fail("unsupported_source:"+str(manifest.get("reason","")))
	manifest.json_sha256=Store._sha(bytes);manifest.file_length=header.file_length
	return {"ok":true,"manifest":manifest}

static func prepare(prepared_plan:Dictionary,admitted_bytes:int,token:RefCounted=null)->Dictionary:
	if not _worker():return _fail("worker_required")
	if _cancelled(token):return _fail("cancelled",true)
	if not prepared_plan.get("ok",false) or not prepared_plan.get("index") is Dictionary or not prepared_plan.get("requested") is Array or not prepared_plan.get("proof") is Ownership:return _fail("plan")
	var index:Dictionary=prepared_plan.index;var ownership:Ownership=prepared_plan.proof
	var path:=str(prepared_plan.get("path",""));var root:=str(prepared_plan.get("root",""))
	var current:=plan(index,prepared_plan.requested,path,root,ownership)
	if not current.ok:return current
	for key:String in ["positions","asset_path","source_header","reference_headers","estimated_bytes","retained_upper_bytes"]:
		if current[key]!=prepared_plan.get(key):return _fail("plan_changed")
	if admitted_bytes<int(current.estimated_bytes):return _fail("budget_not_admitted")
	var profile:Dictionary={"source_sha_calls":0,"map_sha_calls":0,"records":current.positions.size(),"render_imports":0,"image_decodes":0,"face_expansions":0}
	var map_source:=_checked_hash(path,root,token,"map_sha_before");profile.map_sha_calls+=1
	if not map_source.ok:return map_source
	if map_source.sha!=index.source_sha256:return _fail("map_changed")
	var compact:Array=[];var dependencies:Dictionary={}
	for at:int in current.positions:
		var record:Dictionary=index.extras.rmmo_records[at]
		compact.append(record);dependencies[record.rmmo_ref.uri]=record.rmmo_ref.sha256
	var trusted_package:=preload("res://scripts/world3d/runtime_package_policy.gd").trusted()
	var restored:=Store.read_records(compact,path,root,dependencies,1,trusted_package)
	if not restored.get("ok",false):return _fail("reference:"+str(restored.get("reason","")))
	if _cancelled(token):return _fail("cancelled",true)
	var fallbacks:Dictionary={};var eligible:Array=[];var material_checks:Dictionary={};var assets:Dictionary={};var ids:Dictionary={}
	for i:int in restored.records.size():
		var record:Dictionary=restored.records[i]
		if not _supported(record):fallbacks[record.uuid]="collision_not_explicit_none" if not record.has("collision") or record.get("collision")!="none" else "unsupported_record_semantics";continue
		var issue:=Cursor.asset_record_issue(record,material_checks,compact[i].rmmo_ref.sha256,assets,root)
		if issue.is_empty():issue=Cursor.document_record_issue(record,ids)
		if not issue.is_empty():fallbacks[record.uuid]="record:"+issue;continue
		eligible.append(i)
	var selected:=Index.validate_selected(index,restored.records,root,ownership)
	if not selected.ok:return _fail("selected_closure:"+str(selected.reason))
	var source:Dictionary={};var models:Dictionary={};var facts:Array=[]
	if not eligible.is_empty():
		source=_checked_hash(current.asset_path,root,token,"source_sha_before");profile.source_sha_calls+=int(source.get("hashed",true))
		if not source.ok:return source
		var loaded:=_manifest(current.asset_path,root,current.source_header)
		if not loaded.ok:return loaded
		var manifest:Dictionary=loaded.manifest;var expected:Dictionary=index.models[current.asset_path]
		if manifest.json_sha256!=expected.json_sha256 or manifest.file_length!=int(expected.file_length) or manifest.local_bounds!=expected.local_bounds:return _fail("source_manifest_changed")
		models[current.asset_path]={"json_sha256":manifest.json_sha256,"file_length":manifest.file_length,"local_bounds":manifest.local_bounds}
		for i:int in eligible:
			var record:Dictionary=restored.records[i];var row:Dictionary=index.rows[current.positions[i]]
			var actual:=Index._classify(record,root,models)
			if actual.reason!="model_accessor_bounds" or not actual.owner_keys.is_empty() or not actual.bounds_known or not actual.bounds.is_equal_approx(row.bounds) or actual.asset_path!=row.asset_path:return _fail("record_geometry_identity")
			var pose:=Adapter.record_pose(record)
			if not pose.is_finite():return _fail("record_transform")
			facts.append({"at":current.positions[i],"pose":pose,"bounds":row.bounds})
		if _cancelled(token):return _fail("cancelled",true)
		var final_source:=_checked_hash(current.asset_path,root,token,"source_sha_after");profile.source_sha_calls+=int(final_source.get("hashed",true))
		if not final_source.ok:return final_source
		if final_source.sha!=source.sha:return _fail("asset_changed")
	if not trusted_package and not Store.verify_dependencies(dependencies,path,root,1):return _fail("reference_changed")
	map_source=_checked_hash(path,root,token,"map_sha_after");profile.map_sha_calls+=1
	if not map_source.ok:return map_source
	if map_source.sha!=index.source_sha256 or not Index.validate_index_ownership(index,root,ownership,path):return _fail("map_changed")
	if _cancelled(token):return _fail("cancelled",true)
	var proofs:Dictionary={};var retained:=0
	for fact:Dictionary in facts:
		var receipt:=Receipt.new();receipt._index=index;receipt._ownership=ownership;receipt._path=path;receipt._root=root;receipt._map_sha=map_source.sha
		receipt._record=index.extras.rmmo_records[fact.at];receipt._at=fact.at;receipt._asset=current.asset_path;receipt._source_sha=source.sha
		receipt._pose=fact.pose;receipt._bounds=fact.bounds;receipt._seal=Receipt._issuer
		proofs[receipt.uuid()]=receipt;retained+=receipt.retained_bytes()
	profile.proofs=proofs.size();profile.fallbacks=fallbacks.size()
	return {"ok":true,"proofs":proofs,"fallbacks":fallbacks,"estimated_bytes":current.estimated_bytes,"retained_bytes":retained,"selected_closure_verified":true,"closure_complete":false,"profile":profile,"render_imports":0,"image_decodes":0,"face_expansions":0}
