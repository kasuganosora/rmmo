extends SceneTree
## Explicit offline fixture builder; all generated files live in a new review
## root and private user directories. It never launches a renderer or a game.
const Builder=preload("res://tools/isolated_texture_map_builder.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var args:Dictionary={}
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		for key:String in ["source-map","source-root","audit","stage","native-manifest","output"]:
			if arg.begins_with("--"+key+"="):args[key]=arg.trim_prefix("--"+key+"=")
	for key:String in ["source-map","source-root","audit","stage","native-manifest","output"]:
		if not args.has(key) or str(args[key]).is_empty():printerr("missing --",key);quit(2);return
	if "--without-mock-server" not in OS.get_cmdline_user_args():printerr("offline builder requires --without-mock-server");quit(2);return
	var user:=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path()
	if not Paths.allowed(user,Builder.REVIEW_ROOT) or not Paths.allowed(OS.get_data_dir(),Builder.REVIEW_ROOT) or not Paths.allowed(OS.get_cache_dir(),Builder.REVIEW_ROOT):printerr("builder requires private APPDATA/LOCALAPPDATA before launch");quit(2);return
	var manager:=root.get_node_or_null("AssetManager")
	if manager==null or manager.is_node_ready():printerr("cannot isolate AssetManager before ready");quit(2);return
	manager.content_root_override=ProjectSettings.globalize_path("user://fixture_builder")
	run.call_deferred()
func run()->void:
	var result:=Builder.build(args["source-map"],args["source-root"],args.audit,args.stage,args.output,args["native-manifest"])
	if not result.get("ok",false):printerr("ISOLATED_BUILD_FAILED ",result.get("error",""));quit(1);return
	print("ISOLATED_BUILD_OK map=",result.target_map," records=",result.record_count," native=",result.native.size()," candidates=",result.candidate_targets.size()," full_map_closure_verified=",result.full_map_closure_verified)
	quit(0)
