extends SceneTree
## UI integration test on an in-memory fixture; never saves the user's map.
var ed
func _init():call_deferred("run")
func point(cell: Vector2i) -> Vector2:
	var p: Vector2=ed._vp.get_canvas_transform()*(Vector2(cell)*48+Vector2(24,24))
	return p*ed._vpc.size/Vector2(ed._vp.size)
func button(cell: Vector2i,pressed: bool):
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=pressed;event.position=point(cell);ed._on_canvas_input(event)
func motion(cell: Vector2i):
	var event:=InputEventMouseMotion.new();event.position=point(cell)
	event.button_mask=MOUSE_BUTTON_MASK_LEFT;ed._on_canvas_input(event)
func capture(label: String):
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/code/rmmo_runtime/style_work/town_m/selection_"+label+".png")
func run():
	root.size=Vector2i(1600,1000)
	ed=load("res://scripts/editor/content_editor.gd").new();root.add_child(ed)
	await process_frame
	var d=load("res://scripts/editor/domain/map_document.gd").new()
	d.setup_blank("Axel256","多图层移动验收",32,24);d.tileset_id="axel_town"
	for y in range(24):
		for x in range(32):d.set_tile(x,y,0,2816,false)
	var kit: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/style_work/town_m/house_kit.json"))
	var built=load("res://scripts/editor/domain/building_generator.gd").place(d,kit,{"x":6,"y":6,"bays":1,"floors":2,"instance_id":"move_test"})
	assert(built.ok)
	ed.doc=d;ed.pack.maps["Axel256"]=d;ed.current_map_id="Axel256"
	ed._reload_field();ed._set_zoom(.85);ed._cam.position=Vector2(16,12)*48
	ed._set_tool(ed.PaintTools.Tool.SELECT)
	await create_timer(2).timeout
	button(Vector2i(6,6),true);motion(Vector2i(10,13));button(Vector2i(10,13),false)
	var selection: Rect2i=ed._selection_move.rect()
	motion(Vector2i(14,16));assert(ed._selection_move.rect()==selection)
	await capture("selected")
	button(Vector2i(8,10),true);motion(Vector2i(14,10))
	assert(ed._selection_move.dragging and d.building_instances.move_test.x==6)
	await capture("dragging")
	button(Vector2i(14,10),false)
	assert(d.building_instances.move_test.x==12 and d.ext_tile("meta",6,6)==0)
	await create_timer(.5).timeout
	await capture("moved")
	ed._undo_edit();assert(d.building_instances.move_test.x==6)
	ed._redo_edit();assert(d.building_instances.move_test.x==12)
	# MCP runs the same transaction and supports automation acceptance.
	var mcp=load("res://scripts/editor/adapters/editor_mcp.gd").new();mcp.editor=ed;root.add_child(mcp)
	var r=mcp.call_tool("move_selection",{"x":12,"y":6,"w":5,"h":8,"dx":1,"dy":0,"layers":["1","2","3","meta"]})
	assert(r.ok and d.building_instances.move_test.x==13)
	print("PASS real canvas press/motion/release, fixed selection, ghost, commit, UI undo/redo and MCP move")
	mcp.queue_free();ed.queue_free();await process_frame
	quit()
