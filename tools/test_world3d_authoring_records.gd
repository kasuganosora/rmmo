extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failures:=0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1; push_error(message)
func _init() -> void: call_deferred("run")
func write(path: String, data: Dictionary) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--probe":
		var started:=Time.get_ticks_msec();var fast:=Doc.authoritative_extras(args[1])
		print("Record path=",fast.has("extras")," check_ms=",Time.get_ticks_msec()-started)
		var loaded=Doc.open_file(args[1]);print("Loaded=",loaded!=null," total_ms=",Time.get_ticks_msec()-started);quit(0);return
	var dir:=Paths.cache_directory("record_open_test_%d"%OS.get_process_id());var path:=dir.path_join("map.gltf")
	var doc=Doc.sample_yard();check(doc.save(path)==OK,"save authoritative fixture")
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(Doc.authoritative_extras(path).has("extras"),"native root qualifies for record loader")
	var reopened=Doc.open_file(path);check(reopened!=null and reopened.records.size()==doc.records.size(),"records load without duplicate scene import")
	var root_index: int=raw.scenes[int(raw.get("scene",0))].nodes[0]
	var bad:=raw.duplicate(true);bad.nodes[root_index].extras.rmmo_records[0].fixture={"id":"bad","kind":"door","pivot":[0,0,0],"angle":90,"open":2}
	write(path,bad);check(Doc.open_file(path)==null,"invalid hinge cannot enter the document through the fast loader")
	bad=raw.duplicate(true);bad.buffers[0].uri="missing.bin";write(path,bad);check(Doc.open_file(path)==null,"missing baked buffer rejected")
	bad=raw.duplicate(true);bad.buffers[0].uri="..%2f..%2f..%2f..%2foutside.bin";write(path,bad);check(Doc.open_file(path)==null,"escaped dependency rejected")
	bad=raw.duplicate(true);bad.buffers[0].byteLength=1000000000;write(path,bad);check(Doc.open_file(path)==null,"truncated baked buffer rejected")
	bad=raw.duplicate(true);bad.nodes[root_index].translation=[1,0,0];write(path,bad);check(Doc.authoritative_extras(path).is_empty(),"transformed roots retain the GLTF import path")
	write(path,raw)
	print("test_world3d_authoring_records: ","PASS" if failures==0 else "FAIL")
	quit(0 if failures==0 else 1)
