extends SceneTree
## Read-only layout capture against an existing temporary map. No map writes.
const Paths=preload("res://scripts/world3d/map_paths.gd")
var editor:Node3D
var directory:String
var shots:Array=[]
func _initialize()->void:run.call_deferred()
func settle()->void:
	for i in 8:await process_frame
func box(c:Control)->Dictionary:
	var r:=c.get_global_rect()
	return {"x":r.position.x,"y":r.position.y,"width":r.size.x,"height":r.size.y,"minimum":str(c.get_combined_minimum_size())}
func controls(node:Node,result:Array)->void:
	if node is Control and node.is_visible_in_tree():
		var item:Dictionary=box(node);item.path=str(node.get_path());item.type=node.get_class()
		if node is BaseButton or node is Label or node is LineEdit:item.text=node.text
		if node is ScrollContainer:item.scroll_y=node.scroll_vertical;item.scroll_max=node.get_v_scroll_bar().max_value
		result.append(item)
	for child:Node in node.get_children():controls(child,result)
func capture(label:String)->void:
	await settle();await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.save_png(directory.path_join(label+".png"))
	var elements:Array=[];controls(editor,elements)
	var tabs:Array=[]
	for i in editor._dock_tabs.get_tab_count():tabs.append(editor._dock_tabs.get_tab_title(i))
	shots.append({"name":label,"window":str(root.size),"logical_viewport":str(root.get_visible_rect()),"content_scale":str(root.content_scale_size),"canvas":box(editor._canvas),"dock":box(editor._dock_tabs),"panels":tabs,"controls":elements})
	print("LAYOUT_CAPTURE ",label," canvas=",editor._canvas.get_global_rect()," dock=",editor._dock_tabs.get_global_rect())
func tab_named(label:String)->void:
	for i in editor._dock_tabs.get_tab_count():
		if editor._dock_tabs.get_tab_title(i)==label:editor._dock_tabs.current_tab=i;return
func finish()->void:
	var file:=FileAccess.open(directory.path_join("layout.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"purpose":"read-only editor layout review","shots":shots},"\t"));file.close()
	print("EDITOR_LAYOUT_ARTIFACTS ",directory)
	editor.queue_free();await settle();print("EDITOR_LAYOUT_AUDIT_FINISHED");quit()
func run()->void:
	create_timer(180).timeout.connect(func():quit(2))
	directory=Paths.cache_directory("editor_layout_review_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path="D:/code/rmmo_runtime/cache/world3d/crop_extensions_10777411/map.gltf";session.world3d_editor_doc=null
	root.size=Vector2i(1920,1080)
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor)
	await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	if editor._load_failed:print("ERROR: layout fixture failed to open");quit(1);return
	editor._grid.hide();editor._city.set_camera({"projection":"perspective","center":[0,0,0],"distance":15.,"pitch":-35.,"yaw":20.})
	if "--supplement" in OS.get_cmdline_user_args():
		tab_named("素材");editor._on_search("麦");await capture("1920_library_wheat")
		var split:HSplitContainer=editor.find_child("WorkspaceSplit",true,false)
		var detected:=false
		for width in range(400,981,10):
			split.split_offset=width;await settle()
			for control:Control in editor._snap_controls.values():
				var label:Control=control.get_parent().get_child(control.get_index()-1)
				if absf(control.global_position.y-label.global_position.y)>10:
					print("SNAP_GROUP_WRAP ",width," ",label.text," label_y=",label.global_position.y," field_y=",control.global_position.y)
					await capture("snap_group_wrap");detected=true;break
			if detected:break
		split.split_offset=330;tab_named("地形");editor._set_mode(1);tab_named("地形")
		print("MODE_PANEL_BEFORE ",editor._dock_tabs.get_tab_title(editor._dock_tabs.current_tab))
		editor._set_transform_mode(1)
		print("MODE_PANEL_AFTER ",editor._dock_tabs.get_tab_title(editor._dock_tabs.current_tab));await capture("transform_forces_inspector")
		await finish();return
	tab_named("素材");await capture("1920_library")
	var assets:Array=editor._doc.records.filter(func(r):return r.get("kind")=="asset")
	if not assets.is_empty():editor._inspector.select(assets[0].uuid)
	tab_named("属性");await capture("1920_inspector")
	tab_named("地形");editor._terrain_panel.tasks.current_tab=0;await capture("1920_terrain")
	editor._terrain_panel.tasks.current_tab=5;await capture("1920_terrain_create")
	editor._terrain_panel.tasks.current_tab=2;await capture("1920_river_top")
	var scroll:ScrollContainer=editor._terrain_panel.river_panel._body.get_parent();scroll.scroll_vertical=100000;await capture("1920_river_bottom")
	tab_named("城镇布局");await capture("1920_city_top")
	var city_scroll:ScrollContainer=editor._dock_tabs.get_current_tab_control();city_scroll.scroll_vertical=100000;await capture("1920_city_bottom")
	tab_named("城防");editor._city.panel.fortification_panel.tasks.current_tab=0;await capture("1920_fortification")
	editor._city.panel.fortification_panel.tasks.current_tab=5;await capture("1920_fortification_management")
	root.size=Vector2i(1366,768);tab_named("素材");await capture("1366_library_default_scale")
	root.size=Vector2i(1024,768);await capture("1024_library_default_scale")
	# Diagnostic text enlargement only in this disposable instance, no settings save.
	root.size=Vector2i(1920,1080)
	var workspace:Control=editor.find_child("ContentWorkspace",true,false)
	preload("res://scripts/world_editor/workspace_typography.gd").apply(workspace,18);tab_named("属性");await capture("1920_inspector_font18_probe")
	await finish()
