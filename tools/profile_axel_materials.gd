extends "res://tools/profile_axel_publication.gd"
## Same route and bounded trace, with detailed existing pixel/material timers.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
func run()->void:
	for path:String in ["res://scripts/world3d/material_publication.gd","res://tools/profile_axel_materials.gd"]:
		publication_sources[path]=FileAccess.get_sha256(path)
	if "--legacy-materials" in OS.get_cmdline_user_args():preload("res://scripts/world3d/deferred_asset_loader.gd").material_publication_slices_enabled=false
	Paint.texture_profile_enabled=true;Pixels.profile_enabled=true;Pixels.reset_profile()
	await super.run()
func finish(code:int=-1)->void:
	if finished:return
	report.material_profile=Paint.profile_snapshot()
	report.pixel_profile=Pixels.profile_snapshot()
	report.material_slices=preload("res://scripts/world3d/deferred_asset_loader.gd").material_publication_slices_enabled
	report.material_slice_sha256=FileAccess.get_sha256("res://scripts/world3d/material_publication.gd")
	super.finish(code)
