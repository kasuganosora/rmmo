extends "res://tools/test_deferred_asset_scene.gd"
## Run with an isolated --store-root and a sparse unrelated 9 GiB .scn fixture.
## The fixture represents persistent products; it is never parsed or allocated.
func run()->void:
	var folder:="";var producer_path:="res://scripts/world3d/compiled_asset_cache.gd"
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--store-root="):folder=argument.trim_prefix("--store-root=")
		if argument.begins_with("--producer="):producer_path=argument.trim_prefix("--producer=")
	if folder.is_empty() or not Paths.allowed(folder) or not folder.contains("/review_artifacts/"):
		check(false,"test requires isolated external evidence directory");quit(1);return
	var manager:=root.get_node("AssetManager");var old_root:String=manager.content_root_override
	manager.content_root_override=folder
	var producer:Script=load(producer_path)
	var historical:=folder.path_join("cache/world3d/compiled_assets_v1/unrelated_history.scn")
	var witness:=FileAccess.open(historical,FileAccess.READ)
	check(witness!=null and witness.get_length()>8*1024*1024*1024,"pre-existing native storage exceeds the former 8 GiB quota")
	if witness==null:manager.content_root_override=old_root;quit(1);return
	var historical_size:=witness.get_length();witness.close()
	var source:=folder.path_join("tiny.glb")
	static_fixture(source,Color(.2,.6,.3,1))
	var result:Dictionary=producer.build(source)
	print("NATIVE_STORE_RESULT ",JSON.stringify(result))
	check(result.get("ok",false),"a bounded new native import succeeds regardless of unrelated historical bytes")
	if result.get("ok",false):
		var readback:Dictionary=producer.read(source)
		check(readback.get("hit",false),"new native product remains readable and valid")
		Drainer.dispose_result(readback)
		var reused:Dictionary=producer.build(source)
		check(reused.get("ok",false) and reused.get("reused",false),"repeated import reuses the existing published product")
		var index:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(producer.index_path(source)))
		check(index.get("source_path")==source,"new publication records asset ownership for future maintenance")
	else:check(false,"new native product remains readable and valid")
	witness=FileAccess.open(historical,FileAccess.READ)
	check(witness!=null and witness.get_length()==historical_size,"unrelated historical products remain untouched")
	if witness!=null:witness.close()
	manager.content_root_override=old_root
	print("NATIVE_STORE_CAPACITY failures=",failures)
	quit(0 if failures==0 else 1)
