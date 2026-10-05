extends VBoxContainer
const Banner=preload("res://scripts/world3d/streetlamp_banner.gd")
const Ops=preload("res://scripts/world_editor/banner_tools.gd")
var editor:Node
var ids:Array=[]
var form:VBoxContainer
var note:Label
var key:=""
var picker:FileDialog
var image_mode:="flag"

func setup(host:Node)->void:
	editor=host
	var title:=Label.new();title.text="路灯旗帜（可批量更换）";add_child(title)
	note=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.custom_minimum_size.x=260;add_child(note)
	form=preload("res://scripts/world_editor/settings_form.gd").new();add_child(form)
	button("应用旗形、配色和受风",func():commit(form.values()))
	button("整面换旗…",func():choose("flag"))
	button("只换图案…",func():choose("emblem"))
	button("去掉图案",func():commit(form.values().merged({"design":"plain"},true)))
	button("恢复原版红金旗帜",func():commit(Banner.defaults()))
	picker=FileDialog.new();picker.title="选择旗帜图片（自动导入资源库）";picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE;picker.access=FileDialog.ACCESS_FILESYSTEM
	picker.filters=PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 旗帜图片"]);add_child(picker);picker.file_selected.connect(import_image)

func button(text_:String,action:Callable)->void:
	var value:=Button.new();value.text=text_;value.pressed.connect(action);add_child(value)

func choose(mode:String)->void:
	image_mode=mode;picker.popup_centered_ratio(.65)

func refresh()->void:
	ids=editor._selection_tools.ids.duplicate();visible=false
	if ids.is_empty() or editor._selection_tools.whole or editor._view==null:return
	for id in ids:
		var view:Node=editor._view.get_node_or_null(NodePath(str(id)))
		if view==null or Banner.slot(view)==null:return
	visible=true
	var value:=Banner.settings(editor._doc._find(str(ids[0])))
	var next_key:=JSON.stringify([ids,value])
	if key==next_key:return
	key=next_key
	note.text="顶部固定，布面随游戏风向和风速摆动。\n整面换旗：完整设计图；只换图案：透明 PNG，保留底色。\n已选 %d 盏 · %s"%[ids.size(),{"original":"原版刺绣","plain":"纯色","flag":"整面图片","emblem":"独立图案"}[value.design]]
	var values:Dictionary={}
	for field in ["shape","color","trim_color","wind_enabled"]:values[field]=value[field]
	form.build(Banner.schema(),values,{"shape":"旗形","color":"布料底色","trim_color":"原版刺绣色","wind_enabled":"随风飘动"},{"shape":[{"id":"pointed","name":"尖尾旗"},{"id":"rectangle","name":"长方旗"},{"id":"swallowtail","name":"燕尾旗"}]})

func commit(changes:Dictionary)->void:
	var result:=Ops.apply(editor,ids,changes)
	editor._status.text="旗帜已更换，可撤销；保存地图后生效" if result.ok else str(result.error)

func import_image(path:String)->void:
	var input:=Image.load_from_file(path)
	if input==null or input.get_width()>8192 or input.get_height()>8192:
		editor._status.text="请选择不超过 8192×8192 的有效图片";return
	var directory:=preload("res://scripts/asset/art_paths.gd").path("banner_streetlamp/designs")
	var destination:=directory.path_join(FileAccess.get_sha256(path)+"."+path.get_extension().to_lower())
	if DirAccess.make_dir_recursive_absolute(directory)!=OK or (not FileAccess.file_exists(destination) and DirAccess.copy_absolute(path,destination)!=OK):
		editor._status.text="旗帜图片导入失败";return
	commit(form.values().merged({"design":image_mode,"texture_path":destination},true))
