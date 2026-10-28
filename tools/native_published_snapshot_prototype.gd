extends RefCounted
## Offline/private-root experiment only. NOT used by the editor or game.
## Products are copied before snapshot.json is atomically published. The
## caller must keep the private root immutable after publication; an open
## snapshot does not defend against other processes replacing files.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const ARTIFACT_ROOT:="D:/code/rmmo_runtime/review_artifacts"
const REVISION:=1
const MAX_MODELS:=256
const MAX_MANIFEST_BYTES:=2*1024*1024

static func fail(reason:String)->Dictionary:return {"ok":false,"reason":reason}

static func _root(path:String)->String:
	var value:=path.replace("\\","/").simplify_path().trim_suffix("/")
	if not value.is_absolute_path() or not value.to_lower().begins_with(ARTIFACT_ROOT.to_lower()+"/"):return ""
	return value if Paths.allowed(value,ARTIFACT_ROOT) else ""

static func _key(value:String)->bool:
	if value.is_empty() or value.is_absolute_path() or value.contains(":") or value.contains("\\") or value.begins_with("/"):return false
	for index in value.length():
		if value.unicode_at(index)==0:return false
	for piece:String in value.split("/"):
		if piece.is_empty() or piece in [".",".."]:return false
	return value.length()<=1024

static func _integer(value:Variant,low:int,high:int)->bool:
	return (value is int or value is float) and value>=low and value<=high and float(int(value))==float(value)

static func _json(path:String,limit:int)->Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>limit:return {}
	var value:Variant=JSON.parse_string(file.get_as_text());file.close()
	return value if value is Dictionary else {}

static func _offline_descriptor(asset:String,source_root:String,generator:String,footprint_generator:String)->Dictionary:
	# Asset is a logical old native-cache key. No GLB access is required here.
	if not Paths.asset_key_allowed(asset,source_root):return fail("source_key")
	var folder:=Compiled.directory(source_root)
	var index:=Compiled.index_path(asset,source_root)
	var footprint:=Footprint.descriptor_path(asset,source_root)
	if not Paths.allowed(index,folder) or not Paths.allowed(footprint,folder):return fail("source_path")
	var info:=_json(index,8192)
	if info.get("version")!=Compiled.VERSION or info.get("generator")!=generator or not Compiled._sha(info.get("source_sha")) or not Compiled._sha(info.get("payload_sha")) or not _integer(info.get("bytes"),1,Compiled.MAX_JSON_INTEGER):return fail("old_index")
	var envelope:=_json(footprint,Footprint.MAX_DESCRIPTOR_BYTES)
	var body:Variant=envelope.get("body")
	if envelope.get("version")!=Footprint.VERSION or not body is String or not Compiled._sha(envelope.get("sha256")) or body.sha256_text()!=envelope.sha256:return fail("old_footprint")
	var desc:Variant=JSON.parse_string(body)
	if not desc is Dictionary or desc.get("version")!=Footprint.VERSION or desc.get("footprint_generator")!=footprint_generator:return fail("old_footprint_version")
	for field:String in ["source_sha","payload_sha","generator","bytes"]:
		if desc.get(field)!=info.get(field):return fail("old_identity")
	if str(desc.get("source_path",""))!=asset or not _integer(desc.get("source_bytes"),1,Compiled.MAX_JSON_INTEGER):return fail("old_source")
	var stats:Variant=desc.get("stats")
	if not stats is Dictionary:return fail("old_budget")
	var estimate:=Footprint.estimate_stats(stats)
	if estimate.is_empty() or desc.get("estimated_bytes")!=estimate.estimated_bytes or desc.get("resident_bytes")!=estimate.resident_bytes:return fail("old_budget")
	var product:=folder.path_join(str(info.payload_sha)+".scn")
	if not Paths.allowed(product,folder):return fail("source_product_path")
	var file:=FileAccess.open(product,FileAccess.READ)
	if file==null or file.get_length()!=int(info.bytes):return fail("source_product_missing")
	file.close()
	return {"ok":true,"source_sha":info.source_sha,"payload_sha":info.payload_sha,"product":product,"product_bytes":int(info.bytes),"estimated_bytes":int(estimate.estimated_bytes),"source_bytes":int(desc.source_bytes)}

static func publish(source_root_:String,destination_:String,models:Array)->Dictionary:
	if not Thread.is_main_thread():return fail("main_thread_required")
	var source_root:=_root(source_root_);var destination:=_root(destination_)
	if source_root.is_empty() or destination.is_empty() or not DirAccess.dir_exists_absolute(source_root) or DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination):return fail("root")
	if destination.to_lower().begins_with(source_root.to_lower()+"/") or source_root.to_lower().begins_with(destination.to_lower()+"/"):return fail("root_overlap")
	if models.is_empty() or models.size()>MAX_MODELS:return fail("model_count")
	if DirAccess.make_dir_recursive_absolute(destination.path_join("products"))!=OK:return fail("create_root")
	var generator:=Compiled.generator();var footprint_generator:=Footprint.generator()
	var entries:Dictionary={};var products:Dictionary={};var hashes:=0
	for item:Variant in models:
		if not item is Dictionary or not item.get("key") is String or not item.get("old_asset") is String or not _key(item.key) or entries.has(item.key):return fail("model_key")
		var descriptor:=_offline_descriptor(item.old_asset,source_root,generator,footprint_generator)
		if not descriptor.ok:return descriptor
		var sha:String=descriptor.payload_sha
		if products.has(sha):
			if products[sha].bytes!=descriptor.product_bytes or products[sha].estimated_bytes!=descriptor.estimated_bytes:return fail("shared_budget_mismatch")
		else:
			var target:=destination.path_join("products").path_join(sha+".scn")
			if not Paths.allowed(target,destination) or DirAccess.copy_absolute(descriptor.product,target)!=OK:return fail("product_copy")
			# Verify the actual private copy, not a source observed before copying.
			# Conversion cost only; runtime reader never does this SHA/graph walk.
			if FileAccess.get_sha256(target)!=sha:return fail("source_checksum")
			hashes+=1
			if not ResourceLoader.get_dependencies(target).is_empty():return fail("source_dependencies")
			var resource:Resource=ResourceLoader.load(target,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
			if not resource is PackedScene or not Compiled._valid_packed(resource):return fail("source_schema")
			resource=null
			products[sha]={"bytes":descriptor.product_bytes,"estimated_bytes":descriptor.estimated_bytes}
		entries[item.key]={"source_sha":descriptor.source_sha,"payload_sha":sha,"source_bytes":descriptor.source_bytes}
	var manifest:={"revision":REVISION,"engine_hash":Engine.get_version_info().hash,"old_generator":generator,"models":entries,"products":products}
	var encoded:=JSON.stringify(manifest).to_utf8_buffer()
	if encoded.size()>MAX_MANIFEST_BYTES:return fail("manifest_size")
	var temporary:=destination.path_join("snapshot.json.tmp");var final:=destination.path_join("snapshot.json")
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return fail("manifest_write")
	file.store_buffer(encoded);file.flush();var err:=file.get_error();file.close()
	if err!=OK or Atomic.publish(temporary,final)!=OK:return fail("manifest_publish")
	return {"ok":true,"manifest":final,"models":entries.size(),"products":products.size(),"offline_payload_hashes":hashes}

class Snapshot extends RefCounted:
	var root:String
	var manifest:Dictionary
	var budget:int
	var reserved:int=0
	var scenes:Dictionary={}
	var physical_reads:int=0
	var error:String=""

	func load_model(key:String)->Dictionary:
		if not Thread.is_main_thread():return {"ok":false,"reason":"main_thread_required"}
		if not load("res://tools/native_published_snapshot_prototype.gd")._key(key):return {"ok":false,"reason":"model_key"}
		var model:Dictionary=manifest.models.get(key,{})
		if model.is_empty():return {"ok":false,"reason":"model_missing"}
		var sha:String=model.payload_sha
		if scenes.has(sha):return {"ok":true,"packed":scenes[sha],"source_sha":model.source_sha,"shared":true}
		var product:Dictionary=manifest.products[sha]
		var charge:int=product.estimated_bytes
		if charge>budget-reserved:return {"ok":false,"reason":"budget"}
		var path:=root.path_join("products").path_join(sha+".scn")
		if not Paths.allowed(path,root):return {"ok":false,"reason":"product_path"}
		var file:=FileAccess.open(path,FileAccess.READ)
		if file==null or file.get_length()!=int(product.bytes):return {"ok":false,"reason":"product_missing_or_size"}
		file.close()
		# Published/private root contract: no runtime source GLB, payload SHA,
		# dependency walk or full resource-schema walk. Decode/type errors remain.
		var value:Resource=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		physical_reads+=1
		if not value is PackedScene:return {"ok":false,"reason":"product_decode"}
		value.set_meta("compiled_asset_validated",true)
		scenes[sha]=value;reserved+=charge
		return {"ok":true,"packed":value,"source_sha":model.source_sha,"shared":false}

	func close()->void:
		# Test contract: caller first frees all instances and releases its aliases.
		scenes.clear();reserved=0

static func open_snapshot(root_:String,budget:int)->Dictionary:
	if not Thread.is_main_thread():return fail("main_thread_required")
	var root:=_root(root_)
	if root.is_empty() or budget<=0:return fail("root_or_budget")
	var path:=root.path_join("snapshot.json")
	if not Paths.allowed(path,root):return fail("manifest_path")
	var data:=_json(path,MAX_MANIFEST_BYTES)
	if data.get("revision")!=REVISION or data.get("engine_hash")!=Engine.get_version_info().hash:return fail("version")
	if not data.get("models") is Dictionary or data.models.is_empty() or data.models.size()>MAX_MODELS or not data.get("products") is Dictionary or data.products.is_empty():return fail("manifest")
	if not Compiled._sha(data.get("old_generator")):return fail("generator_identity")
	for sha:Variant in data.products:
		var row:Variant=data.products[sha]
		if not Compiled._sha(sha) or not row is Dictionary or not _integer(row.get("bytes"),1,Compiled.MAX_JSON_INTEGER) or not _integer(row.get("estimated_bytes"),1,Footprint.MAX_BYTES):return fail("product_manifest")
	for key:Variant in data.models:
		var row:Variant=data.models[key]
		if not key is String or not _key(key) or not row is Dictionary or not Compiled._sha(row.get("source_sha")) or not Compiled._sha(row.get("payload_sha")) or not data.products.has(row.payload_sha) or not _integer(row.get("source_bytes"),1,Compiled.MAX_JSON_INTEGER):return fail("model_manifest")
	var snapshot:=Snapshot.new();snapshot.root=root;snapshot.manifest=data;snapshot.budget=budget
	return {"ok":true,"snapshot":snapshot}
