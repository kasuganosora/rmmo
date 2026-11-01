extends RefCounted
## Bounded spatial-bucket selection, including exact entering/leaving strips.
## Sparse worlds visit occupied keys; dense worlds visit only queried cells.
var bins:Array=[]
var visited_cells:=0
var _index:Dictionary
var _keys:Array=[]
var _sparse:=false
var _rects:Array[Rect2i]=[]
var _cursor:=0
var _cell:=Vector2i.ZERO
var _old:Rect2i
var _next:Rect2i
var _changed:=false

func _init(index:Dictionary,from:Vector2i,to:Vector2i,radius:int,changed_only:bool=true)->void:
	_index=index;_changed=changed_only
	var extent:=Vector2i(radius,radius);var size_:=Vector2i(2*radius+1,2*radius+1)
	_old=Rect2i(from-extent,size_);_next=Rect2i(to-extent,size_)
	if changed_only:
		_difference(_old,_next);_difference(_next,_old)
	else:_rects.append(_next)
	var cells:=0
	for rect:Rect2i in _rects:cells+=rect.get_area()
	_sparse=index.size()<cells
	if _sparse:_keys=index.keys()
	elif not _rects.is_empty():_cell=_rects[0].position

func _difference(a:Rect2i,b:Rect2i)->void:
	var overlap:=a.intersection(b)
	if not overlap.has_area():_rects.append(a);return
	_add_rect(a.position,Vector2i(overlap.position.x,a.end.y))
	_add_rect(Vector2i(overlap.end.x,a.position.y),a.end)
	_add_rect(Vector2i(overlap.position.x,a.position.y),Vector2i(overlap.end.x,overlap.position.y))
	_add_rect(Vector2i(overlap.position.x,overlap.end.y),Vector2i(overlap.end.x,a.end.y))

func _add_rect(low:Vector2i,end:Vector2i)->void:
	if end.x>low.x and end.y>low.y:_rects.append(Rect2i(low,end-low))

func advance(budget_usec:int)->bool:
	if budget_usec<=0:return false
	var deadline:=Time.get_ticks_usec()+budget_usec
	var advanced:=false
	while not advanced or Time.get_ticks_usec()<deadline:
		advanced=true
		var key:Vector2i
		if _sparse:
			if _cursor>=_keys.size():return true
			key=_keys[_cursor];_cursor+=1;visited_cells+=1
			var inside_next:=_next.has_point(key)
			if (_old.has_point(key)==inside_next) if _changed else not inside_next:continue
		else:
			if _cursor>=_rects.size():return true
			key=_cell;visited_cells+=1
			_cell.x+=1
			if _cell.x>=_rects[_cursor].end.x:_cell.x=_rects[_cursor].position.x;_cell.y+=1
			if _cell.y>=_rects[_cursor].end.y:
				_cursor+=1
				if _cursor<_rects.size():_cell=_rects[_cursor].position
		if _index.has(key):bins.append(_index[key])
	return false

func finish()->void:
	while not advance(2000):pass
