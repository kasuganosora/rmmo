extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Store=preload("res://scripts/world_editor/draft_store.gd")
const SOURCE="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
class DraftHost extends Node3D:
	var _status: Label
	var _recovery_button: Button

func _initialize() -> void: call_deferred("run")

func run() -> void:
	Engine.max_fps=60
	var output:=OS.get_cmdline_user_args()[0]
	var before:=FileAccess.get_sha256(SOURCE); var doc=Doc.open_file(SOURCE)
	var directory:=preload("res://scripts/world3d/map_paths.gd").cache_directory("draft_profile_%d"%Time.get_ticks_usec())
	var store:=Store.new(directory.path_join("drafts")); var path:=directory.path_join("map.gltf")
	var start:=Time.get_ticks_usec(); var prepared:=store.snapshot(path,doc)
	var prepare_ms:=(Time.get_ticks_usec()-start)/1000.
	if not prepared.ok: print(prepared); quit(1); return
	var host:=DraftHost.new(); host._status=Label.new(); host.add_child(host._status); root.add_child(host)
	var safety=preload("res://scripts/world_editor/document_safety.gd").new(); safety.editor=host; safety.store=store; host.add_child(safety)
	safety._draft_prepared=prepared.duplicate(); safety._preparing=true
	start=Time.get_ticks_usec(); safety._validate_and_encode.call_deferred()
	var frames:=0; var last:=Time.get_ticks_usec(); var worst:=0.
	while safety.state().active:
		frames+=1; await process_frame
		worst=maxf(worst,(Time.get_ticks_usec()-last)/1000.); last=Time.get_ticks_usec()
	var encode_ms:=(Time.get_ticks_usec()-start)/1000.
	var id:=store.own_id(path); var restored: Dictionary=store.read(id)
	var same: bool=restored.ok and equivalent(restored.state.records,prepared.state.records) and equivalent(restored.state.map_meta,prepared.state.map_meta)
	var result:={"ok":same,"error":restored.get("error",""),"source_unchanged":before==FileAccess.get_sha256(SOURCE),"snapshot_ms":prepare_ms,"validate_encode_publish_ms":encode_ms,"max_frame_ms":worst,"frames_during_job":frames,"raw_bytes":restored.get("header",{}).get("uncompressed_bytes",0),"stored_bytes":FileAccess.get_file_as_bytes(store.file_for(id)).size(),"version":restored.get("header",{}).get("version"),"draft_id":id,"directory":directory}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t")); print("EDITOR_DRAFT_PROFILE ",JSON.stringify(result)); host.free(); quit(0 if same and result.source_unchanged else 1)

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int): return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not equivalent(a[i],b[i]): return false
		return true
	return a==b
