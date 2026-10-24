extends "res://tools/test_white_native_gpu_reuse.gd"
## Per-product native reopen/material audit, sharing the same verified writer.
func run()->void:
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	var rows:=_check_town()
	for row:Dictionary in rows:
		row.source_sha=FileAccess.get_sha256(row.source)
		row.native_path=Native.directory("D:/code/rmmo_runtime").path_join(row.payload_sha+".scn")
		check(FileAccess.get_sha256(row.native_path)==row.payload_sha,"reopened product keeps exact saved SHA")
		row.resource_audit="passed" if row.serialized_materials==0 else "failed"
		row.visual_review="not repeated; white geometry pipeline only"
	var report:={"models":rows,"failures":failures,"scope":"White native cache rebuild. Per-product reopen, saved/source identity and no serialized materials. No new texture, art-direction or formal map acceptance."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WHITE_NATIVE_PRODUCTS ",rows.size()," failures=",failures);quit(1 if failures else 0)
