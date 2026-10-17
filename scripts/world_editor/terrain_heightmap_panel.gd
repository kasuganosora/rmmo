extends VBoxContainer
const Importer=preload("res://scripts/world_editor/terrain_heightmap.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
var editor:Node3D
var fields:VBoxContainer
var path:LineEdit
var info:Label
var preview_button:Button
var apply_button:Button
var diagnostics:VBoxContainer
var token:=""
var base:=""
var ghost:Node3D
var last:Dictionary={}
func button(text:String,callback:Callable)->Button:
	var item:=Button.new();item.text=text;add_child(item);item.pressed.connect(callback);return item
func setup(value:Node3D)->void:
	editor=value
	var note:=Label.new();note.text="导入空白区域。支持 8 位单通道灰度 PNG、无头 16 位小端 R16；宽高为 17/33/65/129/257/513 个采样点。按原采样分为可雕刻地块，共享边界，不缩放重采样、不覆盖既有内容。";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(note)
	path=LineEdit.new();path.placeholder_text="资源根内的高度图绝对路径";add_child(path);path.text_changed.connect(func(_s):invalidate())
	button("选择高度图",func():
		var dialog:=FileDialog.new();dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;dialog.current_dir=Importer.Paths.external_root();dialog.filters=PackedStringArray(["*.png,*.r16,*.raw ; 高度图"]);add_child(dialog)
		dialog.file_selected.connect(func(p):path.text=p;invalidate();dialog.queue_free());dialog.canceled.connect(dialog.queue_free);dialog.popup_centered_ratio(.7))
	fields=Form.new();add_child(fields)
	fields.build(Importer.schema(),{"format":"png8","samples_x":65,"samples_z":65,"center":[0.,0.,0.],"width":64.,"depth":64.,"height_scale":10.,"bedrock_depth":16.,"name":"导入高度图","flip_z":false},{"format":"文件格式","samples_x":"RAW 横向采样点数","samples_z":"RAW 纵向采样点数","center":"中心 X / 垂直基准 Y / 中心 Z（米）","width":"世界宽度 X（米）","depth":"世界深度 Z（米）","height_scale":"黑到白的高差（米）","bedrock_depth":"基准以下底床深度（米）","name":"地形名称","flip_z":"上下翻转（默认首行在 -Z）"})
	for control:Control in fields.fields.values():
		if control is SpinBox:control.value_changed.connect(func(_v):invalidate())
		elif control is HBoxContainer:
			for spin:SpinBox in control.get_children():spin.value_changed.connect(func(_v):invalidate())
		elif control is OptionButton:control.item_selected.connect(func(_v):invalidate())
		elif control is CheckButton:control.toggled.connect(func(_v):invalidate())
		elif control is LineEdit:control.text_changed.connect(func(_v):invalidate())
	preview_button=button("预览并检查高度图",preview)
	apply_button=button("应用整组地形",apply_candidate);apply_button.disabled=true
	button("放弃高度图预览",invalidate)
	info=Label.new();info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(info)
	diagnostics=preload("res://scripts/world_editor/diagnostic_panel.gd").new();add_child(diagnostics);diagnostics.setup(editor)
func request()->Dictionary:
	var args:Dictionary=fields.values();args.path=path.text.strip_edges()
	if args.format=="png8":args.erase("samples_x");args.erase("samples_z")
	return args
func invalidate()->void:
	if not token.is_empty():editor._heightmap.discard(token)
	token="";base="";last={}
	if is_instance_valid(ghost):ghost.free()
	ghost=null
	if apply_button!=null:apply_button.disabled=true
	if info!=null:info.text="参数或地图变化后请重新预览。"
	if diagnostics!=null:diagnostics.display({})
func preview()->Dictionary:
	var args:=request();invalidate()
	var result:Dictionary=editor._heightmap.preview(args)
	if result.ok:
		token=result.plan_token;base=result.base_version;apply_button.disabled=false
		ghost=Node3D.new();ghost.name="HeightmapPreview";editor.add_child(ghost)
		for record:Dictionary in editor._heightmap.visual(token):
			var mesh:MeshInstance3D=editor._doc._mesh(record);mesh.transparency=.4;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;ghost.add_child(mesh)
		info.text="预览通过，尚未修改地图。\n%d 位 · %d × %d 采样\n%d 块 / %d 格 · 格距 %.3f × %.3f 米\n标高 %.3f–%.3f 米 · 量化步长 %.6f 米\n首行方向：%s"%[result.bit_depth,result.samples[0],result.samples[1],result.tile_count,result.cell_count,result.cell_size[0],result.cell_size[1],result.height_range[0],result.height_range[1],result.quantization_step,"+Z" if args.get("flip_z",false) else "-Z"]
	else:info.text=str(result.error)
	last=editor._diagnostics.explain(result,"preview_heightmap_import");diagnostics.display(last);return last
func apply_candidate()->Dictionary:
	request()
	if token.is_empty():return Importer.fail("请先预览当前高度图")
	var result:Dictionary=editor._heightmap.apply({"plan_token":token});invalidate()
	info.text="整组地形已应用，可一次撤销。请按原生流程保存。" if result.ok else str(result.error)
	last=editor._diagnostics.explain(result,"apply_heightmap_import");diagnostics.display(last);return last
func _process(_delta:float)->void:
	if not token.is_empty() and base!=editor._heightmap.version():invalidate()
func _exit_tree()->void:invalidate()
