extends SceneTree
## Read-only native snapshot; never overwrites the formal-source export.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
func _initialize()->void:
	var path:="";var output:="";var expected:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):path=arg.trim_prefix("--map=")
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=")
		elif arg.begins_with("--expected-sha="):expected=arg.trim_prefix("--expected-sha=")
	if not path.replace("\\","/").contains("/cache/world3d/") or output.is_empty() or expected.length()!=64 or FileAccess.get_sha256(path)!=expected:
		push_error("Exact temporary candidate, SHA and output required");quit(1);return
	var doc=Doc.open_file(path)
	if doc==null or doc.validate_save()!=OK:quit(1);return
	var pending:=output+".pending";var file:=FileAccess.open(pending,FileAccess.WRITE)
	if file==null:quit(1);return
	file.store_string(JSON.stringify({"map_path":path,"map_sha256":expected,"records":doc.records,"map_meta":doc.map_meta},"",true,true));file.close()
	if FileAccess.get_sha256(path)!=expected or Atomic.publish(pending,output)!=OK:quit(1);return
	print("READONLY_CANDIDATE records=",doc.records.size()," sha256=",expected);quit(0)
