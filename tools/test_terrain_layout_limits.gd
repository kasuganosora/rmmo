extends "res://tools/test_world3d_mcp.gd"
## Final-state no-op and aggregate-budget regression, with real HTTP dispatch.
const City=preload("res://scripts/world3d/city_layout.gd")
const T=preload("res://scripts/world3d/terrain_surface.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
func run()->void:
	create_timer(180).timeout.connect(func():quit(2));rpc_timeout_ms=90000
	var directory:=Paths.cache_directory("terrain_layout_limits_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	check(Doc.new().save(path)==OK,"temporary native map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false
	editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=32700
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real 3D HTTP limits fixture starts")
	var created:=await call_tool("create_terrain",{"center":[0,0,0],"width":16.,"depth":16.,"cell_size":.25})
	check(not editor._doc.map_meta.has("editor_layout") and City.valid({}),"terrain-only map needs no road metadata")
	var stroke:={"id":created.id,"mode":"flatten","shape":"rectangle","points":[[0.,0.]],"plot_width":32.,"plot_depth":32.,"target_height":0.,"strength":1.,"blend_margin":1.}
	var before:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	var noop:=await call_tool("apply_terrain_layout",{"strokes":[stroke,stroke]})
	check(not noop.changed and equivalent(before,editor._doc.recovery_snapshot()) and editor._doc._undo.size()==history,"duplicate unchanged stamps preserve metadata, records and history")
	var raised:Dictionary=stroke.duplicate(true);raised.target_height=.2
	var cancelled:=await call_tool("apply_terrain_layout",{"strokes":[raised,stroke]})
	check(not cancelled.changed and equivalent(before,editor._doc.recovery_snapshot()) and editor._doc._undo.size()==history,"stamps cancelling in final state create no transaction")
	# Thirty-two valid connected 64x64 tiles keep each individual stroke legal.
	# Sixteen stamps exceed the combined work budget; no live edit may leak out.
	var base:Dictionary=editor._doc._find(created.id).duplicate(true)
	editor._doc.records=[]
	for z in 4:
		for x in 8:
			var tile:Dictionary=base.duplicate(true);tile.uuid="budget_%d_%d"%[x,z];tile.position=[x*16.,0.,z*16.]
			check(T.valid(tile),"budget fixture tile remains native-valid")
			editor._doc.records.append(tile)
	stroke.id="budget_0_0";stroke.points=[[999.,999.]]
	var strokes:Array=[]
	for i in 16:strokes.append(stroke.duplicate(true))
	before=editor._doc.recovery_snapshot();history=editor._doc._undo.size()
	var rejected:=await call_tool("apply_terrain_layout",{"strokes":strokes},false)
	check(str(rejected.get("error","")).contains("200 万"),"aggregate work budget is enforced across individually valid stamps")
	check(equivalent(before,editor._doc.recovery_snapshot()) and editor._doc._undo.size()==history,"budget rejection is atomic")
	FileAccess.open(OUT+"/terrain_layout_limits_review.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failed,"noop":noop,"cancelled":cancelled,"budget":rejected,"temporary_map":path},"\t"))
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_path="";session.world3d_editor_doc=null
	print("TERRAIN_LAYOUT_LIMITS failures=",failed);quit(1 if failed else 0)
