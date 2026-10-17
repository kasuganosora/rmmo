extends "res://tools/test_world3d_mcp.gd"
## Regenerate derived road kerbs through native HTTP; authoring layout is fixed.
const City=preload("res://scripts/world3d/city_layout.gd")
const Roads=preload("res://scripts/world_editor/road_tools.gd")
var report:Dictionary={"checks":[],"saved":false}
var output:=""
func check(ok:bool,label:String)->void:
	super.check(ok,label);report.checks.append({"name":label,"passed":ok})
func persist()->void:
	if output.is_empty():return
	report.failures=failed
	FileAccess.open(output.path_join("authoring.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
func run()->void:
	var source:="";var target:="";var expected:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):source=arg.trim_prefix("--map=")
		elif arg.begins_with("--save="):target=arg.trim_prefix("--save=")
		elif arg.begins_with("--expected-sha="):expected=arg.trim_prefix("--expected-sha=")
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	if not Paths.allowed(output) or not Paths.allowed(target) or not target.contains("/cache/world3d/") or FileAccess.file_exists(target):quit(1);return
	DirAccess.make_dir_recursive_absolute(output);DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	check(expected.length()==64 and FileAccess.get_sha256(source)==expected,"exact formal source")
	if failed:persist();quit(1);return
	report.merge({"source":source,"source_sha256":expected,"target":target,"scope":"Derived kerb conformity only; road graph, terrain, houses, bridges and scene placements unchanged"})
	create_timer(900).timeout.connect(func():check(false,"authoring timeout");persist();quit(2));rpc_timeout_ms=600000
	var fixture:=output.path_join("empty_editor/map.gltf");DirAccess.make_dir_recursive_absolute(fixture.get_base_dir())
	var empty:=Doc.new();check(empty.save(fixture)==OK,"isolated empty editor fixture")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=fixture;session.world3d_editor_doc=empty
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=output.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var original=Doc.open_file(source);check(original!=null,"native formal source opens")
	if failed:persist();quit(1);return
	var before:Dictionary=original.recovery_snapshot();var staged:=Doc.new();staged.apply_recovery(before);editor._doc=staged;editor._city.refresh();editor._authoring.refresh()
	var socket:=TCPServer.new();port=32840
	while socket.listen(port,"127.0.0.1")!=OK:port+=1
	socket.stop();check(editor.start_mcp(port).ok,"current 3D HTTP started")
	var discovery:=await rpc("tools/list");check(discovery.get("result",{}).get("tools",[]).any(func(t):return t.name=="generate_road_surface"),"native road tool discovered")
	persist()
	var result:=await call_tool("generate_road_surface",{})
	report.operation=result;persist()
	if not result.get("ok",false):editor._mcp.stop();quit(1);return
	check(staged.records.size()==original.records.size(),"all original instance IDs retained")
	var changed:Array=[];var unexpected:Array=[];var before_parts:=0;var after_parts:=0
	for row:Dictionary in original.records:
		var current:Dictionary=staged._find(row.uuid)
		if Roads._same(row,current):continue
		changed.append(row.uuid)
		if not row.has("road_mesh") or not current.has("road_mesh"):unexpected.append({"id":row.uuid,"reason":"non-road change"});continue
		before_parts+=row.road_mesh.get("kerbs",[]).size();after_parts+=current.road_mesh.get("kerbs",[]).size()
		var a:=row.duplicate(true);var b:=current.duplicate(true)
		a.road_mesh.erase("kerbs");b.road_mesh.erase("kerbs")
		if not Roads._same(a,b):unexpected.append({"id":row.uuid,"fields":a.keys().filter(func(k):return not Roads._same(a[k],b.get(k)))})
	report.changed_ids=changed;report.unexpected=unexpected;report.kerb_parts_before=before_parts;report.kerb_parts_after=after_parts
	check(not changed.is_empty() and unexpected.is_empty(),"only generated kerb geometry changes; road tops, UV, materials and scene source preserved")
	var old_meta:Dictionary=original.map_meta.duplicate(true);var new_meta:Dictionary=staged.map_meta.duplicate(true)
	old_meta.editor_layout.erase("road_surface");new_meta.editor_layout.erase("road_surface")
	check(Roads._same(old_meta,new_meta),"all authored metadata and road graph preserved")
	check(staged.validate_save()==OK,"native candidate validates")
	check(FileAccess.get_sha256(source)==expected,"formal source unchanged during candidate authoring")
	if failed==0:
		var after:Dictionary=staged.recovery_snapshot();original.apply_recovery(after);original.commit_recovery_change(before)
		check(original.undo() and Roads._same(original.records,before.records) and Roads._same(original.map_meta,before.map_meta),"native undo restores original roads")
		check(original.redo() and Roads._same(original.records,after.records) and Roads._same(original.map_meta,after.map_meta),"native redo restores refitted roads")
		if failed==0:
			check(original.save(target)==OK,"native candidate atomic save")
			var reopened=Doc.open_file(target)
			check(reopened!=null and reopened.validate_save()==OK and Roads._same(reopened.records,original.records) and Roads._same(reopened.map_meta,original.map_meta),"candidate saves and reopens exactly")
			report.saved=failed==0;report.target_sha256=FileAccess.get_sha256(target)
	persist();editor._mcp.stop();quit(0 if failed==0 else 1)
