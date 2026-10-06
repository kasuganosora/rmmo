extends RefCounted
## Snapshot first, clear second, place last: overlap never eats source cells.
static func move(doc, rect: Rect2i, delta: Vector2i, layers: Array) -> Dictionary:
	if delta==Vector2i.ZERO:return {"ok":true,"dirty":[]}
	var bounds:=Rect2i(0,0,doc.width,doc.height)
	if not bounds.encloses(rect) or not bounds.encloses(Rect2i(rect.position+delta,rect.size)):
		return {"ok":false,"error":"目标超出地图，请向地图内移动"}
	if layers.is_empty():return {"ok":false,"error":"请先勾选参与移动的图层"}
	var selected={}
	for layer in layers:
		var name:=str(layer)
		if name not in ["0","1","2","3","4","5"] and name not in doc.MapExt.LAYER_IDS:
			return {"ok":false,"error":"未知图层："+name}
		selected[name]=true
	if rect.size.x<=0 or rect.size.y<=0 or rect.size.x*rect.size.y*selected.size()>1048576:
		return {"ok":false,"error":"选区为空或过大，请分批移动"}
	var cells=[];var source={};var restore={}
	var before: Dictionary=doc.building_instances.duplicate(true)
	var after: Dictionary=before.duplicate(true)
	for id in before:
		var instance: Dictionary=before[id]
		var touched:=false;var complete:=true
		for c in instance.get("cells",[]):
			var included: bool=rect.has_point(Vector2i(c.x,c.y)) and selected.has(str(int(c.z)))
			touched=touched or included;complete=complete and included
		for c in instance.get("meta",[]):
			var included: bool=rect.has_point(Vector2i(c.x,c.y)) and selected.has("meta")
			touched=touched or included;complete=complete and included
		if not touched:continue
		if not complete:return {"ok":false,"error":"生成住宅需完整框选，并勾选所有建筑图层及通行标记层"}
		var moved: Dictionary=after[id]
		moved.x=int(instance.x)+delta.x;moved.y=int(instance.y)+delta.y
		for field in ["cells","meta"]:
			for c in moved.get(field,[]):
				var layer: String=str(int(c.z)) if field=="cells" else "meta"
				var old:=Vector2i(c.x,c.y)
				var value: int=int(c.tile_id) if field=="cells" else int(c.value)
				if read(doc,layer,old)!=value:return {"ok":false,"error":"生成住宅包含手工修改，请先更新住宅实例再移动"}
				restore[key(layer,old)]=int(c.get("under",0))
				c.x=int(c.x)+delta.x;c.y=int(c.y)+delta.y
	for layer in selected:
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				var pos:=Vector2i(x,y);var value:=read(doc,layer,pos)
				if value==0:continue
				cells.append({"layer":layer,"pos":pos,"value":value})
				source[key(layer,pos)]=true
	for c in cells:
		var target: Vector2i=c.pos+delta
		if not source.has(key(c.layer,target)) and read(doc,c.layer,target)!=0:
			return {"ok":false,"error":"目标图层已有内容（%d,%d），未移动"%[target.x,target.y]}
	if cells.is_empty():return {"ok":true,"dirty":[]}
	var dirty: Array[Vector2i]=[];var seen={}
	doc.begin_undo_batch()
	for c in cells:write(doc,c.layer,c.pos,int(restore.get(key(c.layer,c.pos),0)))
	# Capture new underlay after source restoration, before painting destinations.
	for id in after:
		if after[id]==before[id]:continue
		for field in ["cells","meta"]:
			for c in after[id].get(field,[]):
				c.under=read(doc,str(int(c.z)) if field=="cells" else "meta",Vector2i(c.x,c.y))
	for c in cells:
		write(doc,c.layer,c.pos+delta,c.value)
		for p in [c.pos,c.pos+delta]:
			if not seen.has(p):seen[p]=true;dirty.append(p)
	if after!=before:
		doc.building_instances=after
		doc._push_undo({"t":"building_instances","old":before,"new":after.duplicate(true)})
	doc.end_undo_batch()
	doc._undo[-1]["selection_move"]=true
	return {"ok":true,"dirty":dirty}

static func key(layer: String,p: Vector2i) -> String:return "%s:%d:%d"%[layer,p.x,p.y]
static func read(doc,layer: String,p: Vector2i) -> int:
	return doc.tile(p.x,p.y,int(layer)) if layer.is_valid_int() else doc.ext_tile(layer,p.x,p.y)
static func write(doc,layer: String,p: Vector2i,value: int) -> void:
	if layer.is_valid_int():doc.set_tile(p.x,p.y,int(layer),value)
	else:doc.set_ext_tile(layer,p.x,p.y,value)
