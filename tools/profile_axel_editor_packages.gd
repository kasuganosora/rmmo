extends SceneTree
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Snapshot=preload("res://scripts/world3d/document_source_snapshot.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var path:="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf";var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--verify-resource-packages":Policy.verify_packages=true
		elif arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	Trace.start();var started:=Time.get_ticks_usec();var source:=Snapshot.read_file(path)
	var editor:=Cursor.new();editor.begin_snapshot(source,true)
	while not editor.done:editor.advance()
	var elapsed:=(Time.get_ticks_usec()-started)/1000.;var trace:=Trace.stop()
	var report:={"scope":"read-only editor/MCP document CPU preparation; no GPU scene or UI construction","trusted":Policy.trusted(),"elapsed_ms":elapsed,"error":editor.error,"metrics":editor.metrics,"map_sha":source._signature,"map_unchanged":source.matches_disk(),"trace":trace}
	if editor.document!=null:
		report.records=editor.document.records.size()
		report.records_sha=preload("res://scripts/world3d/map_resource_store.gd")._sha(var_to_bytes(editor.document.records))
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("EDITOR_PACKAGES trusted=",report.trusted," ms=",elapsed," records=",report.get("records",0)," error=",editor.error)
	quit(0 if editor.error.is_empty() and editor.document!=null and report.map_unchanged else 1)
