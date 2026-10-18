extends SceneTree
## Exact real header comparison, including every memory reservation/bounds field.
const MANIFEST=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const MEMORY=preload("res://scripts/world3d/asset_memory_estimate.gd")
const EMBEDDED=preload("res://scripts/world3d/embedded_glb.gd")
const SOURCE="D:/code/rmmo_runtime/packs/default/assets/7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd.glb"
var report:Dictionary={"samples":[],"failures":[],"header_work":{}}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:report.failures.append(label)
func run()->void:
	var output:="";var control:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--control="):control=arg.trim_prefix("--control=")
	if output.is_empty() or control.is_empty() or DisplayServer.get_name()!="headless":quit(2);return
	var old_manifest:Script=load(control.path_join("asset_bounds_manifest.gd"))
	var old_memory:Script=load(control.path_join("asset_memory_estimate.gd"))
	var old_embedded:Script=load(control.path_join("embedded_glb.gd"))
	var file:=FileAccess.open(SOURCE,FileAccess.READ);file.seek(12);var length:=file.get_32();file.seek(20)
	var data:Dictionary=JSON.parse_string(file.get_buffer(length).get_string_from_utf8());var bin_size:=file.get_32();file.close()
	var pending:Array=[data];var containers:=0;var scalars:=0
	while not pending.is_empty():
		var item:Variant=pending.pop_back()
		if item is Dictionary:containers+=1;pending.append_array(item.values())
		elif item is Array:containers+=1;pending.append_array(item)
		else:scalars+=1
	report.header_work={"containers":containers,"scalar_leaves":scalars,"json_bytes":length}
	for candidate:bool in [false,true,true,false,true,false,false,true]:
		var row:Dictionary={"candidate":candidate}
		var manifest:Script=MANIFEST if candidate else old_manifest
		var memory:Script=MEMORY if candidate else old_memory
		var embedded:Script=EMBEDDED if candidate else old_embedded
		var started:=Time.get_ticks_usec();var bounds:Dictionary=manifest.from_json(data,bin_size);row.manifest_us=Time.get_ticks_usec()-started
		started=Time.get_ticks_usec();var plain:bool=embedded._plain(data);row.embedded_us=Time.get_ticks_usec()-started
		started=Time.get_ticks_usec();var safe:bool=memory._bounded_plain(data);row.memory_scan_us=Time.get_ticks_usec()-started
		started=Time.get_ticks_usec();var estimate:Dictionary=memory.estimate(SOURCE);row.memory_total_us=Time.get_ticks_usec()-started
		check(bounds==old_manifest.from_json(data,bin_size) and plain==old_embedded._plain(data) and safe==old_memory._bounded_plain(data) and estimate==old_memory.estimate(SOURCE),"exact header bounds, admission bytes and eligibility unchanged")
		report.samples.append(row)
	var out:=FileAccess.open(output,FileAccess.WRITE);out.store_string(JSON.stringify(report,"\t"));out.close()
	print("METADATA_PROFILE ",JSON.stringify(report));quit(0 if report.failures.is_empty() else 1)
