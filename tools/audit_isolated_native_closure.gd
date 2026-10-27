extends SceneTree
## Inspect native products listed by the read-only map path inventory; this
## never opens/copies authoring GLBs and writes only a new review report.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Metadata=preload("res://scripts/world3d/white_native_asset_metadata.gd")
const Writer=preload("res://scripts/world3d/white_native_asset_writer.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const REVIEW="D:/code/rmmo_runtime/review_artifacts"
func _initialize()->void:run.call_deferred()
func run()->void:
	var inventory:="";var output:="";var source_root:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--inventory="):inventory=arg.trim_prefix("--inventory=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--root="):source_root=arg.trim_prefix("--root=")
	if inventory.is_empty() or output.is_empty() or source_root.is_empty() or not Paths.allowed(inventory,REVIEW) or not Paths.allowed(output,REVIEW) or FileAccess.file_exists(output):printerr("invalid input or output");quit(2);return
	var input:Variant=JSON.parse_string(FileAccess.get_file_as_string(inventory))
	if not input is Dictionary or not input.get("model_classes") is Dictionary:printerr("invalid path inventory");quit(2);return
	var unique:Dictionary={}
	for category:String in input.model_classes:
		if category.begins_with("asset|prefab=false|"):
			for path:String in input.model_classes[category].paths:unique[path]=true
	var keys:Array=unique.keys();keys.sort();Controls.enable_native_geometry_only()
	var rows:Array=[];var errors:Array=[];var bytes:=0
	for path:String in keys:
		if not Paths.asset_key_allowed(path,source_root):errors.append({"path":path,"error":"model outside root"});continue
		var meta:Dictionary=Metadata.read(path,source_root)
		if meta.is_empty():errors.append({"path":path,"error":"native metadata missing or stale"});continue
		var product:String=meta.native_product_path;var index:String=meta.native_index_path;var descriptor:String=meta.native_descriptor_path
		if not Paths.allowed(product,source_root) or not Paths.allowed(index,source_root) or not Paths.allowed(descriptor,source_root):errors.append({"path":path,"error":"native path outside root"});continue
		var file:=FileAccess.open(product,FileAccess.READ)
		if file==null:errors.append({"path":path,"error":"native product missing"});continue
		var length:=file.get_length();file.close();var digest:=FileAccess.get_sha256(product)
		if length!=meta.native_product_bytes or digest!=meta.native_payload_sha:errors.append({"path":path,"error":"native product size or hash mismatch"});continue
		var deps:=ResourceLoader.get_dependencies(product)
		if not deps.is_empty():errors.append({"path":path,"error":"native product has external dependencies","dependencies":deps});continue
		var index_sha:=FileAccess.get_sha256(index);var descriptor_sha:=FileAccess.get_sha256(descriptor)
		if index_sha.is_empty() or descriptor_sha.is_empty():errors.append({"path":path,"error":"native index or descriptor unavailable"});continue
		rows.append({"model":path,"source_sha256":meta.native_source_sha,"index":index,"index_sha256":index_sha,"descriptor":descriptor,"descriptor_sha256":descriptor_sha,"product":product,"product_sha256":digest,"bytes":length,"external_dependencies":deps});bytes+=length
	var report:Dictionary={"map":input.map,"map_sha256":input.map_sha256,"inventory":inventory,"inventory_sha256":FileAccess.get_sha256(inventory),"source_root":source_root,"models":rows,"errors":errors,"requested":keys.size(),"passed":rows.size(),"referenced_product_bytes":bytes,"contract":"Read-only explicit model keys; authoring GLBs not opened. Does not cover generated IO or the complete game process."}
	var out:=FileAccess.open(output,FileAccess.WRITE)
	if out==null:printerr("cannot write output");quit(2);return
	out.store_string(JSON.stringify(report,"\t"));out.close()
	print("NATIVE_CLOSURE requested=",keys.size()," passed=",rows.size()," errors=",errors.size()," bytes=",bytes," output=",output)
	for error:Dictionary in errors:printerr(error)
	quit(0 if errors.is_empty() else 1)
