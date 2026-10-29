extends RefCounted
## Reads only the immutable native product that supplied the reservation.
## A pre-allocation miss may be re-admitted as GLTF; after resource creation,
## errors retain the private PackedScene for the caller's main-thread disposal.
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
# Probe-only baseline. Immutable native geometry is bound to candidate.source_sha;
# checking the source once after all private preparation accepts that geometry.
static var source_precheck_enabled:=false

static func read(path:String,candidate:Dictionary,content_root:String,prepare_private:Callable=Callable(),trusted_package:bool=false,mutable_source:bool=false,expected_product_generator:String="",published_product:bool=false)->Dictionary:
	var started:=Time.get_ticks_usec()
	if not Compiled.enabled or candidate.is_empty():return {"error":OK,"fallback_required":true,"cache_reason":"candidate_disabled"}
	for key in ["source_path","product","generator"]:
		if not candidate.get(key) is String:return {"error":OK,"fallback_required":true,"cache_reason":"candidate_schema"}
	if not Compiled._sha(candidate.get("source_sha")) or not Compiled._sha(candidate.get("payload_sha")) or not candidate.get("bytes") is int or not Compiled.valid_payload_size(candidate.bytes):
		return {"error":OK,"fallback_required":true,"cache_reason":"candidate_schema"}
	var product:String=candidate.get("product","")
	var product_path:=product.replace("\\","/").simplify_path()
	var expected_product:=Compiled.directory(content_root).path_join(candidate.payload_sha+".scn").replace("\\","/").simplify_path()
	if content_root.is_empty() or product_path!=expected_product:
		return {"error":OK,"fallback_required":true,"cache_reason":"candidate_product"}
	# Published native assets have their own immutable identity. Auditing that
	# product must not bring the optional GLB import source back into consumption.
	var published_source:bool=published_product or (trusted_package and not mutable_source)
	# The editor binds a product to its load-operation conversion snapshot.
	# Direct mutable callers without a snapshot use the current generator.
	if mutable_source and not published_product and expected_product_generator.is_empty():expected_product_generator=Compiled.generator()
	var key_allowed:bool=Paths.asset_key_allowed(path,content_root) if published_source else Paths.allowed(path,content_root)
	if candidate.source_path.replace("\\","/").simplify_path()!=path.replace("\\","/").simplify_path() or (not published_source and not trusted_package and candidate.get("generator")!=Compiled.generator()) or (not expected_product_generator.is_empty() and candidate.get("generator")!=expected_product_generator) or not key_allowed or not Paths.allowed(product,Compiled.directory(content_root)):
		return {"error":OK,"fallback_required":true,"cache_reason":"candidate_identity"}
	var file:=FileAccess.open(product,FileAccess.READ)
	if file==null or file.get_length()!=int(candidate.bytes):return {"error":OK,"fallback_required":true,"cache_reason":"candidate_size"}
	file.close()
	var phase:=Time.get_ticks_usec()
	if not trusted_package:
		if FileAccess.get_sha256(product)!=candidate.payload_sha:return {"error":OK,"fallback_required":true,"cache_reason":"candidate_checksum"}
		Trace.elapsed("compiled.payload_sha",phase,{"path":path,"bytes":candidate.bytes})
		if not ResourceLoader.get_dependencies(product).is_empty():return {"error":OK,"fallback_required":true,"cache_reason":"candidate_dependencies"}
	if mutable_source and not published_product and not FileAccess.file_exists(path):return {"error":OK,"fallback_required":true,"cache_reason":"source_missing"}
	if source_precheck_enabled and not trusted_package and not published_source:
		phase=Time.get_ticks_usec()
		var before_sha:=FileAccess.get_sha256(path)
		Trace.elapsed("compiled.source_precheck",phase,{"path":path})
		if before_sha!=candidate.source_sha:return {"error":OK,"fallback_required":true,"cache_reason":"candidate_source_changed"}
	# Production native products are content addressed and never overwritten.
	# Never call Compiled.read here: a newer manifest could name a larger product
	# than the one whose exact resource footprint was admitted.
	phase=Time.get_ticks_usec()
	var loaded:Resource=ResourceLoader.load(product,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var packed:=loaded as PackedScene
	Trace.elapsed("compiled.native_read",phase,{"path":path,"bytes":candidate.bytes})
	var result:Dictionary={"error":ERR_INVALID_DATA,"packed":packed,"compiled":true,"source_digest":candidate.source_sha,"compiled_payload_bytes":int(candidate.bytes)}
	if loaded!=null and packed==null:result.retained_resources=[loaded]
	if packed==null or (not trusted_package and not Compiled._valid_packed(packed)):return result
	if packed.has_meta(&"_rmmo_model_textures_bound_v1"):packed.remove_meta(&"_rmmo_model_textures_bound_v1")
	if not prepare_private.is_null():
		# Private instantiation accepts the authored package, or the explicit audit.
		# It still belongs to the caller's charged reservation and disposal path.
		packed.set_meta("compiled_asset_validated",true)
		if not prepare_private.is_valid():return result
		phase=Time.get_ticks_usec()
		# Do not merge this packet: a callback cannot replace source/payload identity,
		# the fixed PackedScene, or retry flags. Retain even malformed return values
		# so all returned Nodes/resources can be disposed by the main-thread owner.
		var prepared:Variant=prepare_private.call(packed)
		result.private_preparation=prepared
		Trace.elapsed("compiled.private_preparation",phase,{"path":path})
		if not prepared is Dictionary or not prepared.get("error") is int:return result
		if prepared.error!=OK:
			result.error=prepared.error
			return result
		if not prepared.get("scene") is Node or not is_instance_valid(prepared.scene):return result
	phase=Time.get_ticks_usec()
	# Only explicit import/audit transactions can bind to a mutable GLB source.
	# Editor and gameplay consumers bind to the admitted native product instead.
	var source_sha:String=candidate.source_sha if published_source else (preload("res://scripts/world3d/runtime_package_policy.gd").source_identity(path) if trusted_package else FileAccess.get_sha256(path))
	Trace.elapsed("compiled.source_identity" if trusted_package else "compiled.source_sha",phase,{"path":path})
	if not published_source and not Paths.allowed(path,content_root):result.error=ERR_BUSY;return result
	if source_sha!=candidate.source_sha:
		# Never destroy the allocated native scene on this worker. Its coordinator
		# retains its charged reservation until main-thread disposal, including
		# any separately admitted retry owned by the initial loading coordinator.
		result.error=ERR_BUSY;result.native_source_retry=true
		result.cache_reason="candidate_source_changed_after_read"
		return result
	packed.set_meta("compiled_asset_validated",true)
	packed.set_meta("_rmmo_source_digest",candidate.source_sha)
	packed.set_meta("_rmmo_native_payload_sha",candidate.payload_sha)
	packed.set_meta("_rmmo_native_generator",candidate.generator)
	# A trusted package read has not checked the payload. Never inherit an
	# authored metadata value that could falsely mark this owner as audited.
	packed.set_meta("_rmmo_native_audited",not trusted_package)
	result.error=OK;result.cache_us=Time.get_ticks_usec()-started
	Trace.elapsed("compiled.read",started,{"path":path,"bytes":candidate.bytes,"footprint":true})
	return result
