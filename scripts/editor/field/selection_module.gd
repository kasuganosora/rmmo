extends RefCounted
const Move=preload("res://scripts/editor/domain/selection_move.gd")
const Blit=preload("res://scripts/map/tile_blit.gd")
var owner: WeakRef
var ctrl:
	get:return owner.get_ref()
var drawing:=false
var dragging:=false
var anchor:=Vector2i.ZERO
var original:=Rect2i()
var layers: Array=[]
var ghost: Sprite2D
func _init(c):owner=weakref(c)
func selected_layers() -> Array:
	var out=[]
	var root=ctrl._layer_tree.get_root()
	if root==null:return out
	var group=root.get_first_child()
	while group!=null:
		var item=group.get_first_child()
		while item!=null:
			if item.is_checked(2):
				var m: Dictionary=item.get_metadata(0)
				out.append(str(int(m.z)) if int(m.z)>=0 else str(m.ext))
			item=item.get_next()
		group=group.get_next()
	return out
func rect() -> Rect2i:
	var b: Array[Vector2i]=ctrl._selection_bounds()
	return Rect2i(Vector2i(mini(b[0].x,b[1].x),mini(b[0].y,b[1].y)),Vector2i(absi(b[1].x-b[0].x)+1,absi(b[1].y-b[0].y)+1))
func show_rect(r: Rect2i) -> void:
	ctrl.paint.rect_start=r.position
	ctrl.map_field.edit_rect_a=r.position;ctrl.map_field.edit_rect_b=r.end-Vector2i.ONE
func clamp_cell(p: Vector2i) -> Vector2i:
	return p.clamp(Vector2i.ZERO,Vector2i(ctrl.doc.width-1,ctrl.doc.height-1))
func press(cell: Vector2i, fresh: bool=false) -> void:
	if dragging or drawing:return
	cell=clamp_cell(cell)
	ctrl._cursor=cell
	if ctrl.paint.rect_start.x>=0 and rect().has_point(cell) and not fresh:
		layers=selected_layers()
		if layers.is_empty():ctrl._status.text="请勾选图层列表中的「移动」列";return
		dragging=true;original=rect();anchor=cell
		make_ghost()
	else:
		drawing=true;anchor=cell;show_rect(Rect2i(cell,Vector2i.ONE))
func motion(cell: Vector2i) -> void:
	if drawing:
		ctrl.map_field.edit_rect_b=clamp_cell(cell)
	elif dragging:
		var delta:=cell-anchor
		show_rect(Rect2i(original.position+delta,original.size))
		if is_instance_valid(ghost):ghost.position=Vector2(original.position+delta)*ctrl.doc.tile_size
		ctrl._status.text="移动 %d,%d · 松手提交 · Esc取消"%[delta.x,delta.y]
func release(cell: Vector2i) -> void:
	if drawing:
		motion(cell);drawing=false
		ctrl._status.text="选框内拖动移动 · Shift拖动重新框选 · 勾选「移动」选择图层"
	elif dragging:
		var delta:=cell-anchor
		var result:=Move.move(ctrl.doc,original,delta,layers)
		dragging=false;clear_ghost()
		show_rect(Rect2i(original.position+delta,original.size) if result.ok else original)
		if result.ok:
			var dirty: Array[Vector2i]=[];dirty.assign(result.dirty)
			ctrl._refresh_dirty(dirty);ctrl._status.text="已移动 %d 个图层，可 Ctrl+Z 撤销"%layers.size()
		else:ctrl._status.text=result.error
func cancel(clear: bool=false) -> void:
	if dragging and ctrl.map_field:show_rect(original)
	dragging=false;drawing=false;clear_ghost()
	if clear and ctrl.paint:
		ctrl.paint.rect_start=Vector2i(-1,-1)
		if ctrl.map_field:
			ctrl.map_field.edit_rect_a=Vector2i(-1,-1);ctrl.map_field.edit_rect_b=Vector2i(-1,-1)
func clear_ghost() -> void:
	if is_instance_valid(ghost):ghost.queue_free()
	ghost=null
func make_ghost() -> void:
	clear_ghost()
	# Bound temporary preview memory; large selections still preview their bounds.
	if original.size.x*original.size.y>4096:return
	var ts: int=ctrl.doc.tile_size
	var image:=Image.create(original.size.x*ts,original.size.y*ts,false,Image.FORMAT_RGBA8)
	image.fill(Color(0,0,0,0))
	for layer in layers:
		if layer not in ["0","1","2","3"] and layer not in ctrl.MapExt.VISUAL_EXT:continue
		for y in range(original.size.y):
			for x in range(original.size.x):
				Blit.blit_tile(image,Move.read(ctrl.doc,layer,original.position+Vector2i(x,y)),x*ts,y*ts,ctrl.map_field.pack.sheets,ts,ts,ctrl.map_field.pack.flags,0)
	ghost=Sprite2D.new();ghost.centered=false;ghost.texture=ImageTexture.create_from_image(image)
	ghost.position=Vector2(original.position)*ts;ghost.modulate.a=.65;ghost.z_index=100
	ctrl.map_field.add_child(ghost)
