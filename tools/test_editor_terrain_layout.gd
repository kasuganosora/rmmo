extends "res://tools/test_world3d_mcp.gd"

func ancestor_named(node:Node,title:String)->bool:
	var current:=node
	while current!=null:
		if current.name==title:return true
		current=current.get_parent()
	return false

func run()->void:
	create_timer(180).timeout.connect(func():quit(2)); rpc_timeout_ms=60000; Engine.max_fps=60
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	var directory:=Paths.cache_directory("editor_terrain_layout_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");var doc:=Doc.new();check(doc.save(path)==OK,"isolated layout fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=31842
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"layout fixture serves real HTTP MCP")
	var names:Array=(await rpc("tools/list")).result.tools.map(func(t):return t.name)
	check(["generate_terrain_river","preview_terrain_river","remove_terrain_river","list_terrain_rivers"].all(func(n):return n in names),"existing 3D river business tools remain discoverable")
	var panel=editor._terrain_panel
	editor._dock_tabs.current_tab=10;await settle()
	var titles:Array=[]
	for i in panel.tasks.get_tab_count():titles.append(panel.tasks.get_tab_title(i))
	check(titles==["雕刻","表面","河流","洞穴","岩岸","新建"],"terrain navigation names distinct editing tasks")
	check(ancestor_named(panel.create_fields,"新建") and ancestor_named(panel.materials,"表面") and ancestor_named(panel.slope_fields,"表面") and ancestor_named(panel.river_fields,"材质效果"),"creation, surface, and river appearance fields live in their own tasks")
	check(panel.brush_fields.fields.radius.get_parent()==panel.brush_fields._labels.radius.get_parent() and panel.brush_fields.fields.radius.get_parent().get_meta("terrain_compact_row",false),"scalar labels and inputs share a compact row")
	check(not panel.brush_fields._labels.cross_tiles.visible and panel.brush_fields.fields.cross_tiles.text.contains("同步边界"),"boolean fields use one semantic toggle instead of a duplicate label")
	check(panel.create_fields.fields.center.get_parent()==panel.create_fields and panel.river_panel.coordinates.fields.point.get_parent()==panel.river_panel.coordinates,"vector coordinates retain their full-width row")
	check(not panel.slope_fields.fields.rock_material_id.get_parent().get_meta("terrain_compact_row",false),"long material names retain the complete form width")
	var compact_values:Dictionary=panel.brush_fields.values();var compact_children:int=panel.brush_fields.get_child_count()
	panel.Compact.apply(panel.brush_fields,{})
	check(compact_values==panel.brush_fields.values() and compact_children==panel.brush_fields.get_child_count(),"compact layout is idempotent and preserves every field value")
	panel.brush_fields.fields.radius.get_line_edit().grab_focus();panel.brush_fields.fields.radius.get_line_edit().text="4.125"
	check(is_equal_approx(panel.brush_fields.values().radius,4.125),"nested compact rows still commit the number currently being typed")
	panel.brush_fields.fields.radius.get_line_edit().release_focus()

	check(not panel.brush_fields.fields.iterations.visible and not panel.brush_fields.fields.target_height.visible and not panel.brush_fields.fields.iterations.get_parent().visible and not panel.brush_fields.fields.target_height.get_parent().visible,"ordinary sculpt hides entire irrelevant parameter rows")
	panel.brush_fields.fields.mode.select(6);panel.brush_fields.fields.mode.item_selected.emit(6)
	check(panel.brush_fields.fields.iterations.visible and not panel.brush_fields.fields.target_height.visible,"erosion shows its own parameters")
	panel.brush_fields.fields.iterations.value=12
	panel.brush_fields.fields.mode.select(2);panel.brush_fields.fields.mode.item_selected.emit(2)
	check(panel.brush_fields.fields.target_height.visible and not panel.brush_fields.fields.iterations.visible and panel.brush_fields.values().iterations==12,"switching sculpt mode preserves hidden values")
	var initial:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	for i in panel.tasks.get_tab_count():panel.tasks.current_tab=i;await settle()
	check(equivalent(initial,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"browsing every terrain task changes no document or history")
	var create_page:Control=panel.tasks.get_tab_control(5);var create_footer:Control=create_page.get_node("Actions");var footer_y:=create_footer.global_position.y
	create_page.get_child(0).scroll_vertical=10000;await settle()
	check(is_equal_approx(footer_y,create_footer.global_position.y) and create_footer.get_global_rect().end.y<=root.size.y,"new terrain actions stay visible while creation fields scroll")
	var ground:=await call_tool("create_terrain",{"center":[0,0,0],"width":32.,"depth":32.,"cell_size":1.})
	var recipe:={"id":"layout_river","terrain_ids":[ground.id],"points":[[-12,0],[12,0]],"width":4.,"bank_width":2.,"water_level":-.5,"depth":1.5,"natural_materials":false}
	await call_tool("generate_terrain_river",recipe)
	var rivers=panel.river_panel;panel.refresh()
	check(rivers.river_picker.item_count==2,"HTTP-created river appears in the existing-river list")
	check(rivers.settings.fields.width.get_parent()==rivers.settings._labels.width.get_parent() and not rivers.settings._labels.natural_materials.visible and rivers.settings.fields.natural_materials.text=="自然河岸材质","river scalar fields and semantic switches use compact rows")
	initial=editor._doc.recovery_snapshot();history=editor._doc._undo.size()
	rivers.river_picker.select(1);rivers.river_picker.item_selected.emit(1)
	check(rivers.settings.values().id==recipe.id and equivalent(rivers.points,recipe.points) and rivers.apply_button.text=="更新河道" and not rivers.settings.fields.id.editable,"selecting a saved river loads editable parameters with stable identity")
	check(equivalent(initial,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"loading a river is read-only")
	rivers.settings.fields.width.value=5.25;panel.refresh()
	check(is_equal_approx(rivers.settings.values().width,5.25),"ordinary terrain refresh preserves unfinished river edits")
	var water_id:String=editor._doc.map_meta.terrain_rivers[0].water[0].id
	editor._selection_tools.set_ids([water_id]);rivers.new_river();rivers.load_selected()
	check(rivers.settings.values().id==recipe.id and rivers.points.size()==2,"scene water selection resolves its stored river ownership")
	var separate:=recipe.duplicate(true);separate.id="layout_other";separate.points=[[-12,10],[12,10]]
	await call_tool("generate_terrain_river",separate)
	editor._selection_tools.set_ids([ground.id]);rivers.load_selected()
	check(rivers.message.text.contains("多条河道") and rivers.settings.values().id==recipe.id,"ambiguous shared terrain never silently replaces the active river")
	panel.tasks.current_tab=2;await settle()
	var river_footer:Control=rivers.get_node("RiverActions");footer_y=river_footer.global_position.y
	for child in rivers.get_children():
		if child is ScrollContainer:child.scroll_vertical=10000
	await settle()
	check(is_equal_approx(footer_y,river_footer.global_position.y) and river_footer.get_global_rect().end.y<=root.size.y,"river generation and results remain visible while the form scrolls")
	initial=editor._doc.recovery_snapshot();history=editor._doc._undo.size()
	rivers.points=[[0,0]];rivers.apply_button.pressed.emit()
	check(equivalent(initial,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size() and rivers.message.text!="河道方案完成","invalid UI river edit reports failure without partial mutation")
	await call_tool("generate_terrain_river",recipe.merged({"points":[[0,0]]},true),false)
	rivers.load_river(recipe.id);rivers.points=[[-12,-7],[12,-7]];rivers.apply_button.pressed.emit();await settle()
	check(editor._doc._undo.size()==history+1 and equivalent(editor._doc.map_meta.terrain_rivers[1].request.points,rivers.points),"UI update uses the shared single undo transaction")
	await call_tool("undo");check(equivalent(initial,editor._doc.recovery_snapshot()),"HTTP undo restores the complete UI river update")
	await call_tool("redo");await call_tool("save_world");await call_tool("open_world",{"path":path})
	rivers=editor._terrain_panel.river_panel;rivers.load_river(recipe.id)
	check(equivalent(rivers.points,[[-12,-7],[12,-7]]) and rivers.river_picker.item_count==3,"saved river selection and updated route survive reopen")
	var loaded_args:Dictionary=rivers.args();var source:Dictionary=editor._doc.map_meta.terrain_rivers[0];var kept:Dictionary=source.request;source.request={}
	rivers.load_selected();check(rivers.message.text.contains("无效") and equivalent(loaded_args,rivers.args()),"invalid metadata cannot crash scene-linked lookup or replace pending fields")
	source.request=kept;rivers.refresh_catalog(true)
	rivers.new_river();check(rivers.settings.fields.id.editable and rivers.points.is_empty() and rivers.remove_button.disabled,"new river mode resets only the draft and cannot delete an existing river")
	editor._mcp.stop();editor.queue_free();await settle()
	print("EDITOR_TERRAIN_LAYOUT_ARTIFACTS ",directory)
	print("EDITOR_TERRAIN_LAYOUT_FINISHED failures=",failed);quit(0 if failed==0 else 1)
