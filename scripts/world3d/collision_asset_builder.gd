extends RefCounted
## Explicit OFFLINE producer. Never called by gameplay/Stream. Import may own
## native rendering resources: every returned packet, even error/cancel, must
## be joined and consumed by AssetWorkerDrainer on main before its lease ends.
const Descriptor=preload("res://scripts/world3d/collision_asset_descriptor.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Memory=preload("res://scripts/world3d/asset_memory_estimate.gd")
const Manifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")

static func estimate(path:String,root:String)->Dictionary:
	if root.is_empty() or not Paths.allowed(path,root) or path.get_extension().to_lower()!="glb":return {}
	var memory:=Memory.estimate(path)
	# Unknown sources retain the ordinary loader, not an optimistic cache build.
	if not memory.known:return {}
	var bytes:int=memory.estimated_bytes+Descriptor.WORKSPACE_BYTES
	return {"estimated_bytes":bytes,"exclusive":memory.exclusive or bytes>Memory.EXCLUSIVE_BYTES,"known":true,"source_bytes":memory.source_bytes,"source_estimated_bytes":memory.estimated_bytes,"workspace_bytes":Descriptor.WORKSPACE_BYTES,"stage":"offline_collision_asset"}

static func build(path:String,root:String,admitted_bytes:int,token:RefCounted=null)->Dictionary:
	if not Descriptor.Products._worker():return Descriptor._miss("worker_required")
	if Descriptor._cancelled(token):return Descriptor._miss("cancelled",true)
	if root.is_empty() or not Paths.allowed(path,root):return Descriptor._miss("unsupported_or_root")
	if admitted_bytes<Descriptor.WORKSPACE_BYTES:return Descriptor._miss("budget_not_admitted")
	# Establish the import identity BEFORE re-reading its admission headers. If
	# the source changes after estimation, Deferred's pre-import SHA must reject
	# it before it can allocate the replacement's potentially larger textures.
	var source:=Descriptor._hash_source(path,root,token)
	if not source.ok:return source
	# Recompute the bounded headers; supplied budgets are never source proof.
	var current:=estimate(path,root)
	if current.is_empty():return Descriptor._miss("unsupported_or_root")
	if admitted_bytes<int(current.estimated_bytes):return Descriptor._miss("budget_not_admitted")
	var manifest:=Manifest.read(path)
	if not manifest.get("known",false):return Descriptor._miss("unsupported:"+str(manifest.get("reason","")))
	var began:=Time.get_ticks_usec()
	# Force the actual source importer for this offline proof. The result uses
	# the production CPU capture and original collision source precedence; no
	# additional geometry parser, texture readback, or reduced approximation.
	var prepared:=Deferred.prepare_scene(path,source.sha,token,manifest,true,root,true)
	var result:Dictionary
	if not str(prepared.get("error","invalid_preparation")).is_empty():
		result=Descriptor._miss("prepare:"+str(prepared.get("error","invalid_preparation")),prepared.get("cancelled",false))
	else:
		result=Descriptor._build_verified_preparation(path,root,prepared,Descriptor.WORKSPACE_BYTES,token)
	Trace.elapsed("collision_asset.build",began,{"path":path,"ok":result.ok,"admitted_bytes":admitted_bytes})
	# Do not free or drop the last GPU/resource owner on this worker. Recognized
	# ownership field also clears aliases of this exact dictionary on main.
	result.private_preparation=prepared
	result.admitted_bytes=admitted_bytes
	return result
