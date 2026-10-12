extends SceneTree
## Production UI + background-rendered captures, using an isolated document.
const Paths = preload("res://scripts/world3d/map_paths.gd")
var editor: Node3D
var directory: String
var failed := 0
var shots: Array = []

func _initialize() -> void: run.call_deferred()
func frames(count: int = 8) -> void:
	for i in count: await process_frame
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failed += 1
func click(control: Control) -> void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down; event.position=root.get_final_transform()*control.get_global_rect().get_center()
		Input.parse_input_event(event); await frames(3)
func capture(label: String) -> void:
	await frames()
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))
	shots.append(label)
func run() -> void:
	create_timer(150).timeout.connect(func(): print("FAIL timeout"); quit(2))
	directory = Paths.cache_directory("editor_layout_fixed_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var document = preload("res://scripts/world3d/world_document.gd").new()
	document.add_box("ground",Vector3(0,-0.1,0),Vector3(20,0.2,20))
	var id: String = document.add_box("block",Vector3(0,1.5,0),Vector3(4,3,0.4))
	document._find(id).editor_name="住宅院墙 · 布局验收"
	document._find(id).rotation=[0.,133.113,0.]
	document.map_meta.name="布局验证地图"
	var before: Array = document.records.duplicate(true)
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=document; session.world3d_editor_path=directory.path_join("map.gltf")
	root.size=Vector2i(1920,1080)
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	editor.set_meta("layout_preferences_path",directory.path_join("layout.cfg"))
	root.add_child(editor); await frames(20)
	editor._selection_tools.set_ids([id]); editor._dock_tabs.current_tab=10
	for transform in 3:
		editor._set_transform_mode(transform)
		check(editor._dock_tabs.current_tab==10 and editor._transform_mode==transform,"transform %d preserves terrain context"%transform)
	var navigation:Control=editor.find_child("WorkspaceTaskNavigation",true,false)
	check(navigation.get_child_count()==7,"six common tasks plus More share one navigation surface")
	navigation.get_child(5).pressed.emit()
	check(editor._dock_tabs.current_tab==11 and editor._city.panel.fortification_panel.is_visible_in_tree(),"visible fortification entry opens independent task")
	editor._add_mode_menu.get_popup().id_pressed.emit(2)
	check(editor._mode==4 and editor._add_mode_menu.text.contains("传送"),"Add menu retains teleport authoring mode")
	editor._set_transform_mode(0)
	var title:Label=editor.find_child("WorkspaceDocumentTitle",true,false)
	editor._dirty=true
	check(title.text.contains("布局验证地图") and title.text.contains("未保存"),"document identity and dirty state update immediately")
	editor._report_error("参数无效：这一条较长的错误需要持续可见，直到修正或关闭。","城防")
	editor._thumbnails.import_finished.emit("layout","fixture",OK)
	editor._on_search("")
	check(editor._workspace_feedback.notice.visible and editor._workspace_feedback.context=="城防","background success and tool hints preserve important error")
	editor._report_result({"ok":true},"地图环境已应用","地图环境")
	check(editor._workspace_feedback.notice.visible,"unrelated success cannot clear the error")
	await capture("1920_persistent_error")
	editor._report_result({"ok":true},"城防已更新","城防")
	check(not editor._workspace_feedback.notice.visible,"successful retry clears its own error")
	var split:HSplitContainer=editor.find_child("WorkspaceSplit",true,false)
	split.split_offset=840; split.dragged.emit(840); await frames()
	check(split.split_offset<=520,"oversized sidebars are constrained to preserve the scene")
	var bound:=true
	for control:Control in editor._snap_controls.values():
		var label:Control=control.get_parent().get_child(0)
		bound=bound and absf(control.get_global_rect().get_center().y-label.get_global_rect().get_center().y)<8
	check(bound,"snap labels and values remain bound in narrow canvas")
	await capture("1920_wide_sidebar_limit")
	split.split_offset=330; editor._dock_tabs.current_tab=1
	await capture("1920_inspector")
	for task in editor._terrain_panel.tasks.get_tab_count():
		editor._dock_tabs.current_tab=10; editor._terrain_panel.tasks.current_tab=task
		await capture("1920_terrain_%d"%task)
	editor._dock_tabs.current_tab=11
	for task in editor._city.panel.fortification_panel.tasks.get_tab_count():
		editor._city.panel.fortification_panel.tasks.current_tab=task
		await capture("1920_fortification_%d"%task)
		var panel=editor._city.panel.fortification_panel
		check(panel.apply_button.get_global_rect().end.y<=editor._status.global_position.y,"fortification action visible on task %d"%task)
	var overlay=editor._city.overlay
	var undo_count:int=document._undo.size()
	editor._dock_tabs.current_tab=9; await frames()
	await click(overlay.mini_toggle)
	check(not overlay.mini.visible and overlay.mini_toggle.visible,"overview collapses with an accessible restore control")
	editor._city.begin_draw(6.,0.,"ground"); await frames()
	await click(overlay.mini_toggle)
	check(overlay.mini.visible and editor._city.pending.is_empty(),"real overlay click during drawing cannot append a path point")
	editor._city.finish_draw(true)
	await click(overlay.mini_toggle)
	var stored:=ConfigFile.new(); stored.load(directory.path_join("layout.cfg"))
	check(stored.get_value("layout","minimap_collapsed",false),"overview preference persists outside map")
	check(document._undo.size()==undo_count and document.records==before,"navigation and layout preferences never mutate map or undo")
	for dimensions in [Vector2i(1366,768),Vector2i(1024,768)]:
		root.size=dimensions; editor._dock_tabs.current_tab=0; await capture("%d_library"%dimensions.x)
		var viewport:=root.get_visible_rect()
		check(editor._canvas.size.x>=240 and editor._status.get_global_rect().end.y<=viewport.end.y,"layout fits physical window %s"%dimensions)
	var workspace:Control=editor.find_child("ContentWorkspace",true,false)
	var view_menu:MenuButton=workspace.find_children("*","MenuButton",true,false).filter(func(menu):return menu.text=="视图")[0]
	view_menu.get_popup().id_pressed.emit(22); await frames()
	check(workspace.theme.default_font_size==18,"View menu enables larger text")
	editor._dock_tabs.current_tab=1; await capture("1024_inspector_large_text")
	stored.load(directory.path_join("layout.cfg"))
	check(stored.get_value("layout","font_size",0)==18,"text size preference persists")
	# Verify a genuine shared save updates the identity without document UI coupling.
	var saved:bool=await editor._save_async()
	await frames(20)
	check(saved and title.text.contains("已保存") and not title.text.contains("未保存"),"successful isolated save updates persistent document state")
	var reopened=preload("res://scripts/world3d/world_document.gd").open_file(session.world3d_editor_path)
	check(reopened!=null and reopened.records.size()==document.records.size(),"layout-only work preserves shared save/reopen")
	editor._report_error("先前打开失败","打开地图")
	check(editor.open_document(session.world3d_editor_path) and not editor._workspace_feedback.notice.visible,"successful synchronous reopen clears earlier open failure")
	var file:=FileAccess.open(directory.path_join("summary.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"failed":failed,"screenshots":shots,"directory":directory},"\t")); file.close()
	editor.queue_free(); await frames()
	print("EDITOR_LAYOUT_FIXED_ARTIFACTS ",directory)
	print("EDITOR_LAYOUT_FIXED ","PASS" if failed==0 else "FAIL")
	quit(0 if failed==0 else 1)
