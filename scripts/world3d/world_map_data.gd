extends RefCounted
## Shared cartographic projection of the full document, independent of residency.
var bounds:=Rect2()
var shapes:Array=[]
var markers:Array=[]
var title:="三维地图"
var pins:Array[Vector2]=[]
const SHAPE_CELL_SIZE:=64.0
const MAX_SHAPE_CELLS:=64
var _shape_cells:Dictionary={}
var _large_shapes:Array[int]=[]
var _indexed_shape_count:=-1
var last_query_candidates:=0
var last_query_indexed:=false
var shape_revision:=0

var order_revision:=0
var _paint_order:Array[int]=[]
var _raw_bounds:=Rect2()
var _has_raw_bounds:=false
var _spec_count:=0
var _seen_specs:Dictionary={}

static func _paint_less(a:Dictionary,b:Dictionary)->bool:
	var ah:float=a.get("height",0.);var bh:float=b.get("height",0.)
	if ah!=bh:return ah<bh
	var ao:int=a.get("map_draw_order",a.get("source_order",a.get("draw_id",0)))
	var bo:int=b.get("map_draw_order",b.get("source_order",b.get("draw_id",0)))
	if ao!=bo:return ao<bo
	return int(a.get("source_order",a.get("draw_id",0)))<int(b.get("source_order",b.get("draw_id",0)))

func _index_shape(i:int)->void:
	var rect:Rect2=shapes[i].bounds
	var low:=Vector2i((rect.position/SHAPE_CELL_SIZE).floor())
	var high:=Vector2i((rect.end/SHAPE_CELL_SIZE).floor())
	if (high.x-low.x+1)*(high.y-low.y+1)>MAX_SHAPE_CELLS:
		_large_shapes.append(i);return
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var cell:=Vector2i(x,y)
			if not _shape_cells.has(cell):_shape_cells[cell]=[]
			_shape_cells[cell].append(i)

func rebuild_shape_index()->void:
	shape_revision+=1;order_revision+=1
	_shape_cells.clear();_large_shapes.clear();_paint_order.clear()
	_indexed_shape_count=shapes.size()
	for i in shapes.size():
		shapes[i].draw_id=i;_paint_order.append(i);_index_shape(i)
	_paint_order.sort_custom(func(a,b):return _paint_less(shapes[a],shapes[b]))
	for rank in _paint_order.size():shapes[_paint_order[rank]].draw_order=rank

func visible_shapes(rect:Rect2)->Array:
	last_query_candidates=0;last_query_indexed=false
	if not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x<=0 or rect.size.y<=0:return []
	var low:=Vector2i((rect.position/SHAPE_CELL_SIZE).floor())
	var high:=Vector2i((rect.end/SHAPE_CELL_SIZE).floor())
	var cell_count:=(high.x-low.x+1)*(high.y-low.y+1)
	# Full-map overview and unindexed test data are cheaper to scan once than
	# probing a very large rectangle of cells. Exact intersection is identical.
	if _indexed_shape_count!=shapes.size() or cell_count>mini(4096,_shape_cells.size()):
		last_query_candidates=shapes.size()
		var selected:Array=shapes.filter(func(shape):return rect.intersects(shape.bounds))
		selected.sort_custom(_paint_less)
		return selected
	last_query_indexed=true
	var candidates:Dictionary={}
	for i in _large_shapes:candidates[i]=true
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			for i in _shape_cells.get(Vector2i(x,y),[]):candidates[i]=true
	last_query_candidates=candidates.size()
	var ordered:Array=candidates.keys();ordered.sort_custom(func(a,b):return int(shapes[a].get("draw_order",a))<int(shapes[b].get("draw_order",b)))
	var result:Array=[]
	# Stable storage IDs are separate from painter order after lazy additions.
	for i:int in ordered:
		if rect.intersects(shapes[i].bounds):result.append(shapes[i])
	return result

func _project_specs(specs:Array)->Dictionary:
	var first:=true;var projected_bounds:=Rect2();var projected_shapes:Array=[];var projected_markers:Array=[];var seen:Dictionary={}
	var ordinal:=_spec_count
	for spec:Dictionary in specs:
		var source_order:=ordinal;ordinal+=1
		var uuid:=str(spec.get("uuid",""))
		if not uuid.is_empty():
			if seen.has(uuid) or _seen_specs.has(uuid):return {"ok":false,"error":"duplicate map footprint UUID: "+uuid}
			seen[uuid]=true
		if not spec.get("mesh") is Mesh:continue
		var extra:Dictionary=spec.get("extras",{})
		var building:Dictionary=extra.get("building",{})
		# A map shows occupied ground-floor footprints, not every hinge, tread,
		# roof tile and upper-storey surface. Separate slabs preserve courtyard holes.
		if not building.is_empty() and (building.get("role")!="floor" or int(building.get("floor",0))!=0):continue
		var box:AABB=spec.mesh.get_aabb()
		if not spec.get("transform") is Transform3D:return {"ok":false,"error":"invalid footprint transform"}
		var transform:Transform3D=spec.transform
		var projected:=PackedVector2Array()
		for i in 8:
			var p:Vector3=transform*box.get_endpoint(i)
			projected.append(Vector2(p.x,p.z))
		var polygon:=Geometry2D.convex_hull(projected)
		var rect:=Rect2(projected[0],Vector2.ZERO)
		for p in projected:rect=rect.expand(p)
		projected_bounds=rect if first else projected_bounds.merge(rect);first=false
		var kind:=str(extra.get("kind",""))
		var center:=rect.get_center()
		if kind in ["npc","warp","gather"] or extra.get("hostile",false) or extra.get("ally",false):
			projected_markers.append({"position":center,"id":str(spec.uuid),"kind":kind,"hostile":bool(extra.get("hostile",false)),"name":str(extra.get("name",kind))})
			continue
		if polygon.size()<4:continue
		var world_box:AABB=transform*box
		var color:=Color("68765b") if world_box.size.y<.6 else Color("8c8374")
		if not building.is_empty():color=Color("8c8374")
		if kind=="water":color=Color("4b7888")
		projected_shapes.append({"source_order":source_order,"map_draw_order":int(spec.get("map_draw_order",source_order)),"polygon":polygon,"bounds":rect,"color":color,"height":world_box.end.y})
	return {"ok":true,"shapes":projected_shapes,"markers":projected_markers,"bounds":projected_bounds,"has_bounds":not first,"seen":seen,"next_ordinal":ordinal}

func _commit_projection(projected:Dictionary)->void:
	markers.append_array(projected.markers);_seen_specs.merge(projected.seen,true);_spec_count=projected.next_ordinal
	if projected.has_bounds:
		_raw_bounds=_raw_bounds.merge(projected.bounds) if _has_raw_bounds else projected.bounds
		_has_raw_bounds=true
	bounds=(_raw_bounds if _has_raw_bounds else Rect2(-10,-10,20,20)).grow(2)

func build(root:Node)->void:
	shapes.clear();markers.clear();_seen_specs.clear();_spec_count=0;_has_raw_bounds=false;_raw_bounds=Rect2()
	title=str(preload("res://scripts/world3d/gltf_map_io.gd").extras_of(root).get("map_name","三维地图"))
	var projected:=_project_specs(root.get_meta("stream_library",[]))
	if not projected.ok:push_error(projected.error);rebuild_shape_index();return
	shapes.append_array(projected.shapes);shapes.sort_custom(_paint_less)
	_commit_projection(projected);rebuild_shape_index()

## Append stable storage slots and spatial buckets; existing footprints/RIDs do
## not change identity. Only draw-order ranks may move for overlapping heights.
func append_specs(additions:Array)->Dictionary:
	if additions.is_empty():return {"ok":true,"added_shapes":0,"added_markers":0}
	var projected:=_project_specs(additions)
	if not projected.ok:return projected
	if _indexed_shape_count!=shapes.size():rebuild_shape_index()
	var first_changed:=_paint_order.size()
	for shape:Dictionary in projected.shapes:
		var id:=shapes.size();shape.draw_id=id;shapes.append(shape);_index_shape(id)
		var low:=0;var high:=_paint_order.size()
		while low<high:
			var middle: int=(low+high)/2
			if _paint_less(shape,shapes[_paint_order[middle]]):high=middle
			else:low=middle+1
		_paint_order.insert(low,id);first_changed=mini(first_changed,low)
	for rank in range(first_changed,_paint_order.size()):shapes[_paint_order[rank]].draw_order=rank
	_indexed_shape_count=shapes.size()
	if not projected.shapes.is_empty():order_revision+=1
	_commit_projection(projected)
	return {"ok":true,"added_shapes":projected.shapes.size(),"added_markers":projected.markers.size()}

func toggle_pin(point:Vector2)->void:
	for i in pins.size():
		if pins[i].distance_to(point)<1.5:pins.remove_at(i);return
	if pins.size()>=3:pins.pop_front()
	pins.append(point)
