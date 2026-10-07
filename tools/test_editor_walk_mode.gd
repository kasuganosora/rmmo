extends "res://tools/test_world3d_city_layout.gd"
const Walk = preload("res://scripts/world_editor/walk_mode.gd")

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func motion(direction: Array, duration: float, extra: Dictionary={}) -> void:
	await call_tool("move_editor_walk",{"direction":direction,"duration":duration}.merged(extra))
	for i in 240:
		await physics_frame
		if editor._walk_mode._seconds<=0: break
	await frames(12)

func enter(position: Array) -> void:
	await call_tool("set_editor_walk_mode",{"enabled":true,"position":position})
	await call_tool("set_editor_walk_view",{"yaw":0,"pitch":-20,"distance":4.5})
	await frames(10)

func key(code: Key, pressed: bool=true) -> InputEventKey:
	var event:=InputEventKey.new(); event.keycode=code; event.physical_keycode=code; event.pressed=pressed
	return event

func run() -> void:
	Engine.max_fps=60; root.size=Vector2i(1600,1000); root.content_scale_size=root.size
	directory=Paths.cache_directory("editor_walk_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new()
	doc.add_box_silent("ground",Vector3(0,-.1,0),Vector3(40,.2,40))
	var wall:=doc.add_box_silent("block",Vector3(0,2,-3),Vector3(6,4,.4))
	doc._find(wall).editor_locked=true
	var decor:=doc.add_box_silent("block",Vector3(8,1,-2),Vector3(2,2,.2)); doc._find(decor).collision="none"
	var hidden:=doc.add_box_silent("block",Vector3(-8,1,-2),Vector3(2,2,.2)); doc._find(hidden).editor_hidden=true
	var box:=doc.add_box_silent("block",Vector3(2,.5,1),Vector3.ONE)
	for i in 4:doc.add_box_silent("block",Vector3(-4,(i+1)*.1,2-i),Vector3(2,(i+1)*.2,1))
	check(doc.save(path)==OK,"temporary walk fixture saved")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_doc=doc; session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false
	editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); editor._safety.enabled=false
	await settle(); await frames(4)
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"walk HTTP server starts")
	var definitions: Array=(await rpc("tools/list")).result.tools
	var names:=definitions.map(func(t):return t.name)
	check(["set_editor_walk_mode","move_editor_walk","set_editor_walk_view"].all(func(n):return names.has(n)) and not names.has("paint_tile"),"walk operations discovered only on current 3D MCP")
	await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":20,"distance":30})
	var original_camera: Transform3D=editor._camera.transform; var original_size: float=editor._camera.size
	var original_hint: String=editor._canvas.tooltip_text
	var original: Dictionary=doc.recovery_snapshot(); var history: int=doc._undo.size()
	await atomic_reject("set_editor_walk_mode",{"enabled":true,"position":[0,0,-3]})
	await atomic_reject("set_editor_walk_mode",{"enabled":true,"position":[50,0,0]})
	await atomic_reject("set_editor_walk_mode",{"enabled":"yes"})
	await atomic_reject("move_editor_walk",{"direction":[0,1],"duration":.2})
	check(not editor._walk_mode.active and editor._camera.transform==original_camera,"failed entry preserves original camera and creates no actor")
	editor._walk_button.pressed.emit(); await frames(12)
	var walk=editor._walk_mode
	check(walk.active and editor._walk_button.button_pressed and walk.visual.is_visible_in_tree() and walk.visual.mesh is CapsuleMesh,"UI button enters visible third-person capsule mode")
	check(editor._transform_buttons[0].text=="移动" and editor._canvas.tooltip_text==Walk.HINT,"toolbar and canvas describe the walking controls")
	check(editor._camera.projection==Camera3D.PROJECTION_PERSPECTIVE and walk.body.is_on_floor(),"capsule stands on the live editor ground")
	await atomic_reject("set_editor_walk_mode",{"enabled":false,"position":[0,0,0]})
	await atomic_reject("move_editor_walk",{"direction":[0,1],"duration":3})
	await atomic_reject("set_editor_walk_view",{"pitch":100})
	await enter([0,0,0]); await motion([0,1],1.)
	print("WALK_WALL ",walk.state())
	check(walk.body.position.z>-2.55 and walk.body.position.z<-2.3,"locked solid wall blocks capsule without tunnelling")
	await enter([0,0,0]); await call_tool("set_editor_walk_view",{"yaw":180,"pitch":0,"distance":8})
	check(editor._camera.position.z>-2.7 and editor._camera.position.z<-2.,"third-person camera retracts before solid wall")
	await enter([8,0,1])
	var pixel: Vector2=editor._camera.unproject_position(Vector3(8,1,-2))
	check(editor._pick_object(pixel)==decor,"non-colliding decoration remains selectable")
	await motion([0,1],1.5)
	check(walk.body.position.z<-3.,"none-collision decoration does not block walking")
	await enter([-8,0,1]); await motion([0,1],1.5)
	check(walk.body.position.z<-3.,"hidden object does not leave a ghost walking collider")
	await enter([-4,0,3.5]); await motion([0,1],1.3)
	print("WALK_STEPS ",walk.state())
	check(walk.body.position.y>.75 and walk.body.position.z<-.5,"capsule walks up four normal steps")
	await enter([0,0,1])
	await call_tool("move_editor_walk",{"direction":[0,0],"duration":.1,"jump":true}); await frames(8)
	check(walk.body.position.y>.25,"space/MCP jump lifts a grounded capsule")
	await frames(70); check(walk.body.is_on_floor(),"gravity returns capsule to the floor")
	var before: Vector3=walk.body.position
	editor._input(key(KEY_W)); await frames(10); editor._input(key(KEY_W,false))
	check(walk.body.position.z<before.z-.2,"WASD drives physical movement through editor input")
	editor._input(key(KEY_D)); editor._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT); before=walk.body.position; await frames(10)
	check(walk.keys.is_empty() and abs(walk.body.position.x-before.x)<.01,"focus loss releases held movement keys")
	var text:=LineEdit.new(); root.add_child(text); text.grab_focus(); before=walk.body.position
	check(not walk.input(key(KEY_W)),"typing is not consumed as walking")
	await frames(10); check(walk.body.position.distance_to(before)<.01,"editing a text field pauses the actor")
	text.queue_free(); await settle()
	var shortcut:=key(KEY_S); shortcut.ctrl_pressed=true
	check(not walk.input(shortcut),"Ctrl+S remains an editor shortcut")
	var middle:=InputEventMouseButton.new(); middle.button_index=MOUSE_BUTTON_MIDDLE; middle.pressed=true; middle.position=editor._canvas.get_global_rect().get_center()
	editor._input(middle); check(not editor._camera_navigation.held,"middle mouse cannot start free flight while walking")
	middle.pressed=false; editor._input(middle)
	var right:=InputEventMouseButton.new(); right.button_index=MOUSE_BUTTON_RIGHT; right.pressed=true; right.position=middle.position
	editor._input(right)
	var mouse_move:=InputEventMouseMotion.new(); mouse_move.relative=Vector2(40,-15); mouse_move.position=right.position; mouse_move.button_mask=MOUSE_BUTTON_MASK_RIGHT
	var previous_yaw: float=walk.yaw; editor._input(mouse_move)
	check(walk.looking and walk.yaw<previous_yaw,"right drag changes the third-person view")
	right.pressed=false; editor._input(right); check(not walk.looking,"right release restores editing pointer")
	editor._material_panel._set_drawer(true); right.pressed=true; right.position=editor._material_panel._drawer.get_global_rect().get_center()
	editor._input(right); check(not walk.looking,"material drawer overlay keeps its own mouse input")
	editor._material_panel._set_drawer(false)
	var state:=await call_tool("editor_state"); check(state.walk.active and state.walk.perspective=="third_person","HTTP state exposes the live walk session")
	check(equivalent(original,doc.recovery_snapshot()) and history==doc._undo.size(),"walking and camera controls do not alter map or undo history")
	# UI selection and the real transform transaction must remain usable from this camera.
	await enter([0,0,3]); editor._set_mode(1)
	pixel=editor._camera.unproject_position(Vector3(2,.5,1)); editor._place(pixel,true)
	check(editor._inspector.selection==box,"left-click selection works in third person")
	editor._set_transform_mode(0)
	check(editor._transform_drag.begin(editor,pixel,0),"UI move gizmo starts while walking")
	before=walk.body.position; editor._input(key(KEY_W)); await frames(5)
	check(walk.body.position.distance_to(before)<.01,"actor pauses during an object drag")
	editor._transform_drag.update(pixel+Vector2(60,0),true); editor._transform_drag.finish()
	check(doc._undo.size()==history+1 and not equivalent(original.records,doc.records),"UI movement commits one existing undo transaction")
	await call_tool("undo"); check(equivalent(original.records,doc.records) and walk.active,"undo restores the object without leaving walking mode")
	await call_tool("redo"); check(not equivalent(original.records,doc.records) and walk.active,"redo reapplies the object movement while walking")
	await call_tool("undo")
	await atomic_reject("set_object_transform",{"id":wall,"position":[0,2,-6]})
	await call_tool("set_object_transform",{"id":box,"position":[0,.5,1]})
	await enter([0,0,3]); await motion([0,1],.8)
	check(walk.body.position.z>1.75,"walking collision follows an object moved via MCP")
	await call_tool("set_object_properties",{"ids":[box],"hidden":true})
	await motion([0,1],.6); check(walk.body.position.z<1.4,"hiding a moved object removes its walking collider")
	await call_tool("undo"); await call_tool("undo")
	# Place a built-in module using the normal palette and left-click operation.
	await enter([0,0,3]); editor._query=""; editor._asset_category=""; editor._refresh_palette()
	var module_index: int=editor._palette_items.find_custom(func(entry):return entry.has("surface_id") and not entry.get("paint",false) and not entry.has("auto_family") and not entry.has("asset_path"))
	check(module_index>=0,"built-in placement fixture available")
	if module_index>=0:
		editor._pick=module_index; editor._set_mode(0)
		var count: int=doc.records.size()
		editor._place(editor._camera.unproject_position(Vector3(-2,0,0)),true); await frames(5)
		check(doc.records.size()==count+1 and walk.active,"left click places a module while capsule remains in the editor")
		await call_tool("undo"); check(equivalent(original.records,doc.records),"undo removes the newly placed module")
	await enter([0,0,3]); await call_tool("select_objects",{"ids":[box]})
	await call_tool("set_editor_walk_view",{"yaw":-15,"pitch":-15,"distance":5})
	await frames(10); await RenderingServer.frame_post_draw
	var image_path:=directory.path_join("editor_walk_preview.png")
	check(root.get_texture().get_image().save_png(image_path)==OK,"third-person capsule and editing controls screenshot saved")
	print("WALK_PREVIEW ",image_path)
	await call_tool("save_world")
	check(walk.active and not editor._dirty,"saving does not exit walking or dirty the map")
	var saved=Doc.open_file(path); check(saved!=null,"saved map reopens independently")
	check(saved.records.size()==doc.records.size() and not FileAccess.get_file_as_string(path).contains("EditorWalkCapsule"),"temporary capsule is absent from exported map")
	await call_tool("set_editor_walk_mode",{"enabled":false})
	check(editor._camera.transform.is_equal_approx(original_camera) and editor._camera.projection==Camera3D.PROJECTION_ORTHOGONAL and editor._camera.size==original_size,"exit restores exact original camera projection, size and transform")
	check(editor._canvas.tooltip_text==original_hint and editor._transform_buttons[0].text=="移动 W","exit restores free-camera input hints")
	editor._unhandled_input(key(KEY_F6)); await frames(10)
	check(walk.active,"F6 enters the same walking mode")
	editor._input(key(KEY_ESCAPE)); check(not walk.active,"Esc exits walking before editor close handling")
	await enter([0,0,0]); await call_tool("set_editor_camera",{"projection":"top"})
	check(not walk.active and editor._camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"switching editor view cleanly exits walking")
	await enter([0,0,0]); await call_tool("open_world",{"path":path}); await frames(5)
	check(not walk.active and walk.body==null,"opening a map removes the old transient capsule")
	editor.queue_free(); await settle(); print("EDITOR_WALK_MODE failures=",failed); quit(0 if failed==0 else 1)
