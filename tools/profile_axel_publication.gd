extends "res://tools/profile_axel_region_loading.gd"
## Optional bounded trace and explicit experimental flags. Same map, requests,
## camera and budgets as the region probe; no forced publication or bypass.
const Trace=preload("res://scripts/world3d/load_trace.gd")
var trace_enabled:=false
var publication_sources:Dictionary={}
func run()->void:
	trace_enabled="--trace" in OS.get_cmdline_user_args()
	if "--fair-publication" in OS.get_cmdline_user_args():
		preload("res://scripts/world3d/deferred_asset_loader.gd").fair_publication_enabled=true
	if "--legacy-publication" in OS.get_cmdline_user_args():
		preload("res://scripts/world3d/deferred_asset_loader.gd").fair_publication_enabled=false
	if "--shared-prefab-pixels" in OS.get_cmdline_user_args():
		preload("res://scripts/world3d/deferred_asset_loader.gd").prefab_texture_preparation_enabled=true
		preload("res://scripts/world3d/deferred_asset_loader.gd").shared_prefab_texture_preparation_enabled=true
	for path:String in ["res://scripts/world3d/house_prefab.gd","res://scripts/world3d/runtime_mesh_cache.gd","res://scripts/world3d/surface_materials.gd","res://scripts/world3d/deferred_asset_loader.gd","res://scripts/world3d/publication_order.gd","res://tools/profile_axel_publication.gd"]:
		publication_sources[path]=FileAccess.get_sha256(path)
	if trace_enabled:Trace.start()
	await super.run()
func finish(code:int=-1)->void:
	if finished:return
	if trace_enabled:
		var trace:=Trace.stop()
		var path:=output.path_join("publication_trace.json")
		var file:=FileAccess.open(path,FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify(trace));file.close()
		report.trace={"path":path,"sha256":FileAccess.get_sha256(path),"dropped":trace.dropped,"events":trace.events.size()}
	report.publication_sources=publication_sources
	report.shared_prefab_pixels=preload("res://scripts/world3d/deferred_asset_loader.gd").shared_prefab_texture_preparation_enabled
	report.fair_publication=preload("res://scripts/world3d/deferred_asset_loader.gd").fair_publication_enabled
	for path:String in publication_sources:check(FileAccess.get_sha256(path)==publication_sources[path],"publication source unchanged "+path)
	super.finish(code)
