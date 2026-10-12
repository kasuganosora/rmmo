extends SceneTree
## UI-only fixture: no model generation, map writes or foreground window.
const FortificationPanel=preload("res://scripts/world_editor/fortification_panel.gd")
const F=preload("res://scripts/world3d/fortification_data.gd")
var failures:=0
var assertions:=0

class Catalog extends VBoxContainer:
	signal catalog_changed
	var _entries:Array=[]
class Library extends RefCounted:
	func find(_id:String)->Dictionary:return {}
class MaterialTool extends RefCounted:
	var library=Library.new()
class Fortifications extends RefCounted:
	var entries:Array=[]
	var overlay_plan:Dictionary={}
	var calls:Array=[]
	var reject:=false
	func regions()->Array:return entries
	func summary(args:Dictionary)->Dictionary:
		calls.append(["summary",args.duplicate(true)])
		return {"ok":false,"error":"预览路径与现有物件冲突"} if reject else {"ok":true,"length":60.0,"tower_count":2,"count":20,"gates":[],"plan_token":"test-plan"}
	func generate(args:Dictionary)->Dictionary:
		calls.append(["generate",args.duplicate(true)]); return {"ok":true}
	func set_gate(id:String,gate:String,amount:float)->Dictionary:
		calls.append(["gate",id,gate,amount]); return {"ok":false,"error":"城门活动范围被占用"} if reject else {"ok":true}
	func set_terrain_follow(id:String,enabled:bool)->Dictionary:
		calls.append(["follow",id,enabled]); return {"ok":true}
	func bake(id:String)->Dictionary:calls.append(["bake",id]); return {"ok":true}
	func remove(id:String,keep:bool)->Dictionary:calls.append(["remove",id,keep]); return {"ok":true}
class City extends RefCounted:
	func begin_fortification(_height:float)->Dictionary:return {"ok":true}
class Editor extends Node3D:
	var _doc=RefCounted.new()
	var _material_tool=MaterialTool.new()
	var _material_panel=Catalog.new()
	var _fortifications=Fortifications.new()
	var _city=City.new()
	var reports:Array=[]
	func _report_result(result:Dictionary,success:String,context:String)->void:reports.append([result,success,context])
class Host extends VBoxContainer:
	var editor:Node3D
	func note(parent:Node,text_:String)->Label:
		var result:=Label.new(); result.text=text_; result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; parent.add_child(result); return result
	func button(parent:Node,text_:String,action:Callable)->Button:
		var result:=Button.new(); result.text=text_; result.pressed.connect(action); parent.add_child(result); return result

func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	assertions+=1
	if not ok:failures+=1; push_error("FAIL "+label)
	else:print("PASS "+label)
func frames()->void:
	for i in 5:await process_frame
func choose(control:OptionButton,value:String)->void:
	for i in control.item_count:
		if control.get_item_metadata(i)==value:control.select(i);control.item_selected.emit(i);return

func run()->void:
	root.size=Vector2i(1280,720); root.content_scale_size=root.size
	var editor:=Editor.new(); root.add_child(editor); editor.add_child(editor._material_panel)
	var host:=Host.new(); host.editor=editor; root.add_child(host); host.hide()
	var panel=FortificationPanel.new(); panel.setup(host)
	check(panel.fields.values().shape=="path" and panel.gate_fields.values().kind=="land","task can initialize and read forms before entering the scene tree")
	root.add_child(panel); panel.size=Vector2(330,630); await frames()
	check(panel.fields.values().style=="medieval_stone" and panel.fields.values().height==7.5 and panel.fields.values().tower_layout=="automatic","new wall UI uses the shared service modern defaults")
	check(panel.tasks.get_tab_count()==6 and panel.fields.is_ancestor_of(panel.fields.fields.radius_x),"six task pages keep fields in shared SettingsForm")
	check(panel.fields.fields.name.get_parent() is HBoxContainer and panel.fields.fields.name.get_parent()==panel.fields._labels.name.get_parent(),"compact labels and values share one horizontal row")
	check(panel.fields.fields.closed.text=="闭合路径" and not panel.fields._labels.closed.visible,"boolean field uses its semantic label without a duplicate label row")
	check(panel.pages[0].get_combined_minimum_size().y<320 and panel.state.autowrap_mode==TextServer.AUTOWRAP_OFF,"common path layout fits one compact page with single-line status")
	check(not panel.fields.fields.radius_x.visible and not panel.fields.fields.curve_tension.visible and panel.fields.fields.closed.visible,"path hides unrelated ring and spline fields")
	var fields_before:Dictionary=panel.fields.values()
	panel.tasks.current_tab=3; await frames(); panel.tasks.current_tab=0
	check(panel.fields.values()==fields_before,"tab changes preserve complete recipe")
	panel.fields.fields.name.text="南城墙"
	choose(panel.fields.fields.shape,"ellipse")
	check(panel.fields.fields.radius_x.visible and not panel.fields.fields.closed.visible and panel.fields.fields.name.text=="南城墙","ring shows only relevant layout controls without losing name")
	panel.tower_nodes.text="0,2"
	FortificationPanel.MaterialChoice.choose(panel.materials.stone,"pending:stone")
	panel.gate_fields.fields.width.value=7.25
	var pending_material:OptionButton=panel.materials.stone
	var pending_gate:SpinBox=panel.gate_fields.fields.width
	check(not panel.request().has("tower_indices"),"ring request ignores hidden path-only tower indices")
	check(panel.set_points([[-40,-30],[40,30]]).ok and panel.fields.values().radius_x==40 and panel.fields.values().radius_z==30,"ring selection updates shared form and bounds")
	check(panel.request().stone_material_id=="pending:stone" and panel.materials.stone==pending_material,"ring drawing preserves the independent material draft and menu")
	check(panel.tower_nodes.text=="0,2" and panel.gate_fields.fields.width==pending_gate and is_equal_approx(panel.gate_fields.values().width,7.25),"ring drawing preserves hidden tower text and uncommitted gate fields")
	choose(panel.fields.fields.shape,"spline")
	check(panel.fields.fields.curve_tension.visible and not panel.fields.fields.radius_x.visible,"spline exposes tension and hides ring controls")
	choose(panel.fields.fields.tower_layout,"manual")
	check(not panel.fields.fields.tower_spacing.visible,"manual tower layout hides automatic spacing")
	panel.fields.fields.corner_towers.button_pressed=false
	check(panel.fields.fields.wall_access.visible and panel.fields.fields.arrow_slits.visible,"enabled dependent options stay reachable when towers are disabled")
	panel.fields.fields.corner_towers.button_pressed=true
	panel.tasks.current_tab=1; await frames()
	var height:SpinBox=panel.fields.fields.height
	height.get_line_edit().grab_focus(); height.get_line_edit().text="8.125"
	check(is_equal_approx(panel.request().height,8.125),"request commits focused numeric text in nested task page")
	height.get_line_edit().release_focus()
	panel.tasks.current_tab=0; await frames()
	var footer_position:Vector2=panel._footer.global_position
	panel.tasks.get_child(0).scroll_vertical=10000; await frames()
	check(panel._footer.global_position.is_equal_approx(footer_position) and panel._footer.get_global_rect().end.y<=panel.get_global_rect().end.y+.1,"primary actions stay visible while task content scrolls")
	check(panel.apply_button.disabled,"apply is disabled before preview")
	panel.show_preview()
	check(not panel.apply_button.disabled and editor._fortifications.calls.back()[0]=="summary","preview uses shared service and enables apply")
	panel.fields.fields.height.value=8.25
	check(panel.apply_button.disabled and panel.preview.is_empty(),"editing invalidates preview and prevents stale apply")
	editor._fortifications.reject=true; panel.show_preview()
	check(panel.info.text.contains("冲突") and editor.reports.back()[2]=="城防","preview failure persists locally and uses shared status reporting")
	panel.tasks.current_tab=4; await frames()
	check(panel.info.text.contains("冲突"),"switching task tabs does not erase failure")
	panel.refresh()
	check(panel.info.text.contains("冲突"),"unrelated catalog refresh does not erase failure")
	editor._fortifications.reject=false
	check(not panel.gate_fields.fields.water_depth.visible,"land gate hides water-only parameters")
	choose(panel.gate_fields.fields.kind,"water")
	check(panel.gate_fields.fields.water_depth.visible and panel.gate_fields.fields.grille.visible,"water gate exposes water-specific parameters")
	panel._add_gate(); var first_gate:String=panel.current.gates[0].id
	panel._add_gate()
	check(panel.gate_choice.get_item_metadata(panel.gate_choice.selected)!=first_gate and panel.current.gates.size()==2,"adding a gate selects the newly added gate")
	var editable:Dictionary=panel.request().duplicate(true); editable.id="editable_wall"; editable.name="可修改城墙"
	editor._fortifications.entries=[{"settings":editable.duplicate(true),"baked":false,"parts":[{"id":"legacy_part"}]}]
	panel.refresh(); panel.choice.select(1); panel.load_region()
	var stored_before:PackedByteArray=var_to_bytes(editor._fortifications.entries[0].settings)
	panel.gate_fields.fields.width.value=9.75; panel._update_gate(); panel._add_gate(); panel._remove_gate()
	check(var_to_bytes(editor._fortifications.entries[0].settings)==stored_before,"gate draft edits never alias and mutate the stored recipe before apply")
	panel.fields.fields.name.text="未提交名称"; panel.fields.fields.height.value=9.25; panel.tower_nodes.text="1,3"
	panel.gate_choice.select(1); panel.gate_choice.item_selected.emit(1); panel.gate_fields.fields.width.value=8.5
	FortificationPanel.MaterialChoice.choose(panel.materials.stone,"pending:second-stone")
	panel.tasks.current_tab=4; await frames(); panel.tasks.get_child(4).scroll_vertical=70; await frames()
	var draft_height:SpinBox=panel.fields.fields.height; var draft_scroll:int=panel.tasks.get_child(4).scroll_vertical
	var draft_gate_id:String=panel.gate_choice.get_item_metadata(panel.gate_choice.selected)
	panel.refresh(); await frames()
	check(panel.fields.fields.height==draft_height and panel.fields.values().name=="未提交名称" and is_equal_approx(panel.fields.values().height,9.25),"unrelated city refresh preserves existing-wall form and pending values")
	check(panel.request().stone_material_id=="pending:second-stone" and panel.tower_nodes.text=="1,3" and panel.gate_choice.get_item_metadata(panel.gate_choice.selected)==draft_gate_id and is_equal_approx(panel.gate_fields.values().width,8.5),"unrelated refresh preserves material, tower and selected gate drafts")
	check(panel.tasks.current_tab==4 and panel.tasks.get_child(4).scroll_vertical==draft_scroll,"unrelated refresh preserves task and scroll context")
	editor._fortifications.entries[0].settings.height=10.0; panel.refresh()
	check(panel.fields.fields.height!=draft_height and is_equal_approx(panel.fields.values().height,10.0) and panel.fields.values().name==editable.name,"stored recipe changes rebuild the form from current document state")
	panel.fields.fields.name.text="旧文档草稿"; editor._doc=RefCounted.new(); panel.refresh()
	check(panel.fields.values().name==editable.name,"new document identity reloads even an identical wall recipe")
	panel.fields.fields.name.text="显式切换前草稿"; panel.load_region()
	check(panel.fields.values().name==editable.name,"explicit region selection reloads authoritative settings")
	panel.new_region(); panel.fields.fields.name.text="新建草稿"; editor._doc=RefCounted.new(); panel.refresh()
	check(panel.fields.values().name=="城墙","changing documents also discards an unbound new-wall draft")
	var saved:Dictionary=panel.current.duplicate(true)
	saved.id="existing_wall"; saved.name="北城墙"; saved.gates=editable.gates.duplicate(true); saved.gates[0].height=3.5
	editor._fortifications.entries=[{"settings":saved,"baked":true,"parts":[{"id":"wall_mesh"}],"source_part_count":60}]
	panel.refresh(); panel.choice.select(1); panel.load_region(); await frames()
	check(panel.state.text.contains("只读") and not panel.preview_button.visible and not panel.apply_button.visible,"baked wall clearly enters management state")
	check(not panel.fields.fields.height.editable and panel.fields.fields.shape.disabled and panel.materials.stone.disabled and not panel.gate_fields.fields.width.editable,"baked structural geometry and materials are read-only")
	check(not panel.fields.fields.follow_terrain.disabled and not panel.follow_button.disabled and not panel.gate_open_button.disabled,"baked wall retains terrain-follow and gate controls")
	check(panel.detach_button.disabled and panel.bake_button.disabled and not panel.delete_button.disabled,"management only enables operations supported for baked walls")
	panel.gate_choice.select(0); panel.gate_choice.item_selected.emit(0)
	check(is_equal_approx(panel.gate_fields.values().height,3.5),"read-only legacy gate height is preserved without clamp")
	var saved_before:Dictionary=panel.current.duplicate(true); var calls:int=editor._fortifications.calls.size()
	panel._add_gate(); panel._update_gate(); panel._remove_gate(); panel.show_preview()
	check(panel.current==saved_before and calls==editor._fortifications.calls.size(),"frozen UI rejects structural actions without business calls or local edits")
	check(not panel.set_points([[0,0],[50,0]]).ok and panel.current==saved_before,"in-flight drawing cannot mutate a frozen wall recipe")
	panel.fields.fields.follow_terrain.button_pressed=true; panel._apply_follow()
	check(editor._fortifications.calls.back()==["follow","existing_wall",true],"terrain-follow routes through existing shared operation")
	editor._fortifications.reject=true; panel.set_gate(1)
	check(editor._fortifications.calls.back()[0]=="gate" and panel.info.text.contains("占用"),"gate errors remain visible beside the current task")
	panel.new_region()
	check(panel.preview_button.visible and panel.fields.fields.height.editable and panel.tasks.current_tab==0,"new wall restores editable creation state")
	for size_ in [Vector2(300,560),Vector2(420,720)]:
		panel.size=size_; await frames()
		check(panel.tasks.size.y>120 and panel._footer.get_global_rect().end.y<=panel.get_global_rect().end.y+.1,"compact panel retains scrollable work area and footer at %s"%size_)
	panel.add_theme_font_size_override("font_size",20); panel.size=Vector2(300,560); await frames()
	check(panel.get_combined_minimum_size().x<=300 and panel.fields.fields.name.size.x>=120,"large text preserves usable compact field width without forcing a wider sidebar")
	panel.queue_free(); host.queue_free(); editor.queue_free(); await frames()
	print("FORTIFICATION_PANEL_LAYOUT_FINISHED checks=%d failures=%d"%[assertions,failures]); quit(0 if failures==0 else 1)
