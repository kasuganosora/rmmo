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

static func read(path:String,candidate:Dictionary,content_root:String,prepare_private:Callable=Callable())->Dictionary:
	var started:=Time.get_ticks_usec()
	if not Compiled.enabled or candidate.is_empty():return {"error":OK,"fallback_required":true,"cache_reason":"candidate_disabled"}
	for key in ["source_path","product","generator"]:
		if not candidate.get(key) is String:return {"error":OK,"fallback_required":true,"cache_reason":"candidate_schema"}
	if not Compiled._sha(candidate.get("source_sha")) or not Compiled._sha(candidate.get("payload_sha")) or not candidate.get("bytes") is int or candidate.bytes<=0 or candidate.bytes>Compiled.MAX_FILE_BYTES:
		return {"error":OK,"fallback_required":true,"cache_reason":"candidate_schema"}
	var product:String=candidate.get("product","")
	if content_root.is_empty() or product!=Compiled.directory(content_root).path_join(candidate.payload_sha+".scn"):
		return {"error":OK,"fallback_required":true,"cache_reason":"candidate_product"}
	if candidate.get("source_path")!=path or candidate.get("generator")!=Compiled.generator() or not Paths.allowed(path,content_root) or not Paths.allowed(product,Compiled.directory(content_root)):
		return {"error":OK,"fallback_required":true,"cache_reason":"candidate_identity"}
	var file:=FileAccess.open(product,FileAccess.READ)
	if file==null or file.get_length()!=int(candidate.bytes):return {"error":OK,"fallback_required":true,"cache_reason":"candidate_size"}
	file.close()
	var phase:=Time.get_ticks_usec()
	if FileAccess.get_sha256(product)!=candidate.payload_sha:return {"error":OK,"fallback_required":true,"cache_reason":"candidate_checksum"}
	Trace.elapsed("compiled.payload_sha",phase,{"path":path,"bytes":candidate.bytes})
	if not ResourceLoader.get_dependencies(product).is_empty():return {"error":OK,"fallback_required":true,"cache_reason":"candidate_dependencies"}
	if source_precheck_enabled:
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
	if packed==null or not Compiled._valid_packed(packed):return result
	if not prepare_private.is_null():
		# This marker authorizes only private instantiation of the validated schema.
		# Source identity and publication still depend on the final gate below.
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
	var source_sha:=FileAccess.get_sha256(path)
	Trace.elapsed("compiled.source_sha",phase,{"path":path})
	if not Paths.allowed(path,content_root):result.error=ERR_BUSY;return result
	if source_sha!=candidate.source_sha:
		# Never destroy the allocated native scene on this worker. Its coordinator
		# retains its charged reservation until main-thread disposal, including
		# any separately admitted retry owned by the initial loading coordinator.
		result.error=ERR_BUSY;result.native_source_retry=true
		result.cache_reason="candidate_source_changed_after_read"
		return result
	packed.set_meta("compiled_asset_validated",true)
	result.error=OK;result.cache_us=Time.get_ticks_usec()-started
	Trace.elapsed("compiled.read",started,{"path":path,"bytes":candidate.bytes,"footprint":true})
	return result
