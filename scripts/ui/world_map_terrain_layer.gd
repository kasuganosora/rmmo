extends Node2D
## Retain each footprint's fill/outline commands in original painter order.
## Panning only changes visibility and the parent transform, never tessellation.
var shapes:Array=[]
var redraws:=0
var timing:Dictionary={}
var commands_recorded:=0
var prepared_width:=-1.0
var _items:Array[RID]=[]
var _widths:Array[float]=[]
var _orders:Array[int]=[]
var _order_revision:=-1
var _priority:Array[int]=[]
var _priority_cursor:=0
var _queued:Dictionary={}
var _source:Array=[]
var _visible:Dictionary={}
var _data:RefCounted
var _revision:=-1
var _warm_cursor:=0
var warm_slices:=0
var max_warm_slice_ms:=0.0
const WARM_BUDGET_USEC:=1000
const LOADING_WARM_BUDGET_USEC:=4000

func prepare(data:RefCounted,width:float)->bool:
	var replaced:bool=_data!=data or _revision!=data.shape_revision or _items.size()>data.shapes.size()
	var changed:bool=replaced or _items.size()!=data.shapes.size()
	if replaced:
		clear()
		_data=data;_revision=data.shape_revision;_source=data.shapes
	if changed:
		var previous:=_items.size()
		_items.resize(_source.size());_widths.resize(_source.size());_orders.resize(_source.size())
		for i in range(previous,_source.size()):
			_widths[i]=-1.;_orders[i]=-1
			# Unindexed map data also needs stable per-footprint identifiers.
			_source[i].draw_id=i
	if changed or _order_revision!=data.order_revision:
		for i in _source.size():
			var order:int=_source[i].get("draw_order",i)
			if _orders[i]!=order and _items[i].is_valid():RenderingServer.canvas_item_set_draw_index(_items[i],order)
			_orders[i]=order
		_order_revision=data.order_revision
	if replaced or prepared_width!=width:
		prepared_width=width;_warm_cursor=0
		set_process(true)
	elif _warm_cursor<_source.size():set_process(true)
	return changed

func is_prepared()->bool:return _data!=null and _warm_cursor>=_source.size() and _priority_cursor>=_priority.size()

func _process(_delta:float)->void:
	# Layout, revision and visibility can change while a slice is pending.
	if not get_parent()._prepare_terrain():
		set_process(false);return
	var began:=Time.get_ticks_usec()
	var budget:int=get_parent()._terrain_warm_budget_usec()
	while _warm_cursor<_source.size() or _priority_cursor<_priority.size():
		var index:int
		if _priority_cursor<_priority.size():
			index=_priority[_priority_cursor];_priority_cursor+=1;_queued.erase(index)
		else:index=_warm_cursor;_warm_cursor+=1
		if _widths[index]!=prepared_width:_record(index,prepared_width)
		if Time.get_ticks_usec()-began>=budget:break
	if _priority_cursor>=_priority.size():_priority.clear();_priority_cursor=0
	if get_parent().has_meta("profile_frame"):
		warm_slices+=1;max_warm_slice_ms=maxf(max_warm_slice_ms,(Time.get_ticks_usec()-began)/1000.0)
	if is_prepared():
		set_process(false)
		get_parent()._terrain_preparation_finished()

func _record(i:int,width:float)->void:
	if not _items[i].is_valid():
		var item:=RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item,get_canvas_item())
		RenderingServer.canvas_item_set_draw_index(item,_orders[i])
		RenderingServer.canvas_item_set_visible(item,false)
		_items[i]=item
	var shape:Dictionary=_source[i]
	var polygon:PackedVector2Array=shape.polygon
	var count:=polygon.size()
	if count>1 and polygon[0]==polygon[count-1]:count-=1
	# WorldMapData footprints are convex hulls. A fan is exact and also avoids
	# the ear-clipping failure on extremely thin projected grass footprints.
	var indices:=PackedInt32Array()
	for corner in range(1,count-1):indices.append_array(PackedInt32Array([0,corner,corner+1]))
	RenderingServer.canvas_item_clear(_items[i])
	if not indices.is_empty():RenderingServer.canvas_item_add_triangle_array(_items[i],indices,polygon,PackedColorArray([shape.color]))
	RenderingServer.canvas_item_add_polyline(_items[i],polygon,PackedColorArray([shape.color.darkened(.25)]),width,true)
	RenderingServer.canvas_item_set_visible(_items[i],_visible.has(i))
	_widths[i]=width;commands_recorded+=1

func show_shapes(visible_shapes:Array,width:float)->void:
	var began:=Time.get_ticks_usec() if get_parent().has_meta("profile_frame") else 0
	var recorded_before:=commands_recorded
	var visible_added:=0
	var visible_removed:=0
	var next:Dictionary={}
	shapes=visible_shapes
	for shape:Dictionary in shapes:
		var i:int=shape.draw_id
		next[i]=true
		# New lazy footprints use the same bounded preparation queue. Existing
		# commands still resize immediately, preserving the established zoom path.
		if not _items[i].is_valid():
			if not _queued.has(i):_priority.append(i);_queued[i]=true;set_process(true)
		elif _widths[i]!=width:_record(i,width)
		if not _visible.has(i) and _items[i].is_valid():
			RenderingServer.canvas_item_set_visible(_items[i],true)
			if began>0:visible_added+=1
	for i:int in _visible:
		if not next.has(i) and _items[i].is_valid():
			RenderingServer.canvas_item_set_visible(_items[i],false)
			if began>0:visible_removed+=1
	_visible=next;redraws+=1
	if began>0:timing={"frame":Engine.get_process_frames(),"ms":(Time.get_ticks_usec()-began)/1000.0,"recorded_delta":commands_recorded-recorded_before,"visible_added":visible_added,"visible_removed":visible_removed,"width":width,"prepared_width":prepared_width,"commands_recorded":commands_recorded}

func clear()->void:
	set_process(false)
	for item in _items:
		if item.is_valid():RenderingServer.free_rid(item)
	_items.clear();_widths.clear();_orders.clear();_visible.clear();_source=[];shapes=[];_data=null;_revision=-1;prepared_width=-1.;_warm_cursor=0
	_order_revision=-1;_priority.clear();_priority_cursor=0;_queued.clear()

func _exit_tree()->void:clear()
