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
var _copy_queue:Node
var _copy:Dictionary={}

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
	if result.get("pending",false):
		editor._asset_operations.tag_ui(result.request_id)
		editor._status.text="正在后台准备旗帜，完成后可撤销"
	else:editor._status.text="旗帜已更换，可撤销；保存地图后生效" if result.ok else str(result.error)

func import_image(path:String)->void:
	var root_:=preload("res://scripts/world3d/map_paths.gd").external_root()
	if preload("res://scripts/world3d/map_paths.gd").allowed(path,root_):
		commit(form.values().merged({"design":image_mode,"texture_path":path},true));return
	if not _copy.is_empty():_copy.token.cancel();_copy_queue.cancel();_copy_queue.queue_free();_copy.clear()
	_copy_queue=preload("res://scripts/world_editor/load_preparation_queue.gd").new()
	_copy_queue.ledger=editor._shared_preparation_ledger;_copy_queue.shared_ledger_enabled=true;add_child(_copy_queue)
	var token:=preload("res://scripts/world3d/asset_worker_drainer.gd").CancelToken.new()
	_copy={"token":token,"document":editor._doc,"revision":editor._doc.authoring_revision,"ids":ids.duplicate(),"settings":form.values().merged({"design":image_mode},true)}
	if not _copy_queue.enqueue("copy",preload("res://scripts/world_editor/banner_image_copy.gd").run.bind(path,root_,token),{"estimated_bytes":5*1024*1024,"exclusive":false,"cpu_only":true},"texture"):
		_copy.clear();_copy_queue.queue_free();set_process(false)
		editor._status.text="图片导入任务无法启动";return
	editor._status.text="正在后台导入旗帜图片"
	set_process(true)

func _process(_delta:float)->void:
	if _copy.is_empty() or not _copy_queue.is_ready("copy"):return
	var result:Dictionary=_copy_queue.acquire("copy").duplicate();_copy_queue.release("copy");_copy_queue.queue_free()
	var pending:=_copy;_copy={};set_process(false)
	if not result.get("ok",false):editor._status.text=result.get("error","图片导入失败");return
	if editor._doc!=pending.document or editor._doc.authoring_revision!=pending.revision or ids!=pending.ids:
		editor._status.text="图片已导入，选择或地图已变化，本次未修改旗帜";return
	commit(pending.settings.merged({"texture_path":result.path},true))

func _exit_tree()->void:
	if not _copy.is_empty():_copy.token.cancel()
