extends "res://tools/test_model_components_http.gd"
const SOURCE="D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2/axel_guild_repaired.glb"
func review_timeout()->float:return 600.0
func expected_components()->int:return 37
func make_source(source_path:String)->void:
	rpc_timeout_ms=60000
	check(DirAccess.copy_absolute(SOURCE,source_path)==OK,"isolated full guild source copied")
	check(FileAccess.get_sha256(SOURCE)==FileAccess.get_sha256(source_path),"exact final guild SHA in temporary map")
	var built:=preload("res://scripts/world3d/compiled_asset_cache.gd").build(source_path)
	print("GUILD_PRODUCTION_COMPILE=",built)
	check(built.get("ok",false),"temporary guild native prepared through production compiler")
func verify_loaded()->void:
	check(editor._ground_batches!=null and editor._ground_batches.groups.size()>0,"actual editor automatically batches guild parts")
	print("GUILD_EDITOR_BATCH_GROUPS=",editor._ground_batches.groups.size())
