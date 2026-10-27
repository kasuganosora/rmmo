extends SceneTree
## Preflight only. It does not construct the map or install/copy sidecars.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Compressed=preload("res://scripts/world3d/compressed_texture_source.gd")
const Builder=preload("res://tools/isolated_texture_map_builder.gd")
const REVIEW="D:/code/rmmo_runtime/review_artifacts"
func _initialize()->void:run.call_deferred()
func run()->void:
	var audit_path:="";var stage:="";var output:="";var root_:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--audit="):audit_path=arg.trim_prefix("--audit=")
		if arg.begins_with("--stage="):stage=arg.trim_prefix("--stage=")
		if arg.begins_with("--root="):root_=arg.trim_prefix("--root=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if audit_path.is_empty() or stage.is_empty() or output.is_empty() or root_.is_empty() or not Paths.allowed(audit_path,REVIEW) or not Paths.allowed(stage,REVIEW) or not Paths.allowed(output,REVIEW) or FileAccess.file_exists(output):printerr("invalid inputs or output");quit(2);return
	var audit:Variant=JSON.parse_string(FileAccess.get_file_as_string(audit_path));var staged:Variant=JSON.parse_string(FileAccess.get_file_as_string(stage.path_join("manifest.json")))
	if not audit is Dictionary or not staged is Dictionary or not FileAccess.file_exists(stage.path_join("COMPLETE")):printerr("invalid inventory or stage");quit(2);return
	var errors:Array=[];var rows:Array=[];var candidates:Array=[];var declarations:Dictionary={};var blobs:Dictionary={};var pack:=Builder._normalize(str(staged.get("pack_root","")))
	var map:=Builder._normalize(str(audit.get("map","")))
	if not Paths.allowed(map,root_) or not Paths.allowed(pack,root_) or not audit.get("errors") is Array or not audit.errors.is_empty() or not audit.get("map_unchanged",false) or FileAccess.get_sha256(map)!=audit.get("map_sha256","") or Builder._normalize(str(staged.get("map","")))!=map or staged.get("map_sha256","")!=audit.map_sha256 or staged.get("audit_sha256","")!=FileAccess.get_sha256(audit_path):errors.append("map or audit identity mismatch")
	for row:Dictionary in audit.get("texture_variants",[]):
		var source:=Builder._normalize(str(row.get("source","")));var normal:bool=row.get("normal_role",false);var flip:bool=row.get("flip_normal_green",false)
		var selected:=Builder._normalize(str(row.get("selected_sidecar","")));var actual:=Compressed.sidecar_path(source,flip,normal)
		var plan:=Compressed.plan(source,flip,normal,root_)
		if not Paths.allowed(source,pack) or not FileAccess.file_exists(source) or Builder._normalize(actual)!=selected or (not selected.is_empty() and (plan.is_empty() or plan.sidecar!=selected or int(plan.width)!=int(row.get("width",0)) or int(plan.height)!=int(row.get("height",0)))):errors.append({"source":source,"error":"source or selected sidecar missing/changed"});continue
		declarations[[source,normal,flip]]=true
		rows.append({"source":source,"selected":selected,"normal":normal,"flip":flip})
	for blob:Dictionary in staged.get("blobs",[]):blobs[str(blob.get("path",""))]=blob
	for row:Dictionary in staged.get("targets",[]):
		var src:=Builder._normalize(pack.path_join(str(row.get("source",""))));var dst:=Builder._normalize(pack.path_join(str(row.get("target",""))));var blob_path:=Builder._normalize(stage.path_join(str(row.get("blob",""))))
		var normal:bool=row.get("role","")=="normal";var flip:bool=row.get("flip",false);var blob:Dictionary=blobs.get(str(row.get("blob","")),{})
		if not Paths.allowed(src,pack) or not Paths.allowed(dst,pack) or not Paths.allowed(blob_path,stage) or not declarations.has([src,normal,flip]) or not Builder._sidecar_suffix_valid(src,dst,normal,flip) or FileAccess.file_exists(dst):errors.append({"source":src,"error":"candidate path or role"});continue
		var digest:=FileAccess.get_sha256(src);var blob_digest:=FileAccess.get_sha256(blob_path);var size:=Builder._png_size(src)
		var file:=FileAccess.open(blob_path,FileAccess.READ)
		var header:Dictionary={}
		if file!=null:
			var length:=file.get_length();header=Compressed._header(file.get_buffer(mini(length,148)),length,normal);file.close()
		if digest.is_empty() or digest!=row.get("source_sha256","") or digest!=blob.get("source_sha256","") or blob_digest.is_empty() or blob_digest!=row.get("blob_sha256","") or blob_digest!=blob.get("sha256","") or blob.get("role","")!=row.get("role","") or blob.get("flip",null)!=flip or header.is_empty() or size.x<=0 or size.y<=0 or int(header.get("width",0))!=size.x or int(header.get("height",0))!=size.y or int(blob.get("width",0))!=size.x or int(blob.get("height",0))!=size.y:errors.append({"source":src,"error":"candidate identity or dimensions"});continue
		candidates.append({"source":src,"source_sha256":digest,"target":dst,"blob":blob_path,"blob_sha256":blob_digest,"role":row.role,"flip":flip,"width":size.x,"height":size.y})
	var report:Dictionary={"map":map,"audit":audit_path,"audit_sha256":FileAccess.get_sha256(audit_path),"stage":stage,"variants":rows,"candidates":candidates,"errors":errors,"contract":"Read-only preflight; no texture or candidate sidecar is installed."}
	var f:=FileAccess.open(output,FileAccess.WRITE)
	if f==null:printerr("cannot write output");quit(2);return
	f.store_string(JSON.stringify(report,"\t"));f.close()
	print("TEXTURE_INPUTS variants=",rows.size()," candidates=",candidates.size()," errors=",errors.size()," output=",output)
	for error:Variant in errors:printerr(error)
	quit(0 if errors.is_empty() else 1)
