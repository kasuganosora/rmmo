extends SceneTree
const Decoder=preload("res://scripts/world_editor/heightmap_png16.gd")
func _init()->void:run.call_deferred()
func run()->void:
	var directory:="";var checks:=0;var failures:=0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--inputs="):directory=arg.trim_prefix("--inputs=")
	var cases:Array=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("cases.json")))
	var results:Array=[]
	for row:Dictionary in cases:
		var decoded:=Decoder.decode(FileAccess.get_file_as_bytes(directory.path_join(row.path)))
		var ok:bool=decoded.ok==row.ok
		if ok and row.ok:
			ok=decoded.values.size()==row.values.size()
			for i in row.values.size():ok=ok and absf(decoded.values[i]*65535.-row.values[i])<.0000001
		checks+=1
		if not ok:failures+=1
		results.append({"case":row.path,"ok":ok,"source_sha256":FileAccess.get_sha256(directory.path_join(row.path))})
		print("PASS " if ok else "FAIL ",row.path)
	FileAccess.open(directory.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":results},"\t"))
	quit(1 if failures else 0)
