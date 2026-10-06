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

func rebuild_shape_index()->void:
	shape_revision+=1
	_shape_cells.clear();_large_shapes.clear()
	_indexed_shape_count=shapes.size()
	for i in shapes.size():
		var rect:Rect2=shapes[i].bounds
		var low:=Vector2i((rect.position/SHAPE_CELL_SIZE).floor())
		var high:=Vector2i((rect.end/SHAPE_CELL_SIZE).floor())
		# Large terrain pieces remain a short shared list rather than creating
		# thousands of cells. The index never clips or changes their footprints.
		if (high.x-low.x+1)*(high.y-low.y+1)>MAX_SHAPE_CELLS:
			_large_shapes.append(i);continue
		for y in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var cell:=Vector2i(x,y)
				if not _shape_cells.has(cell):_shape_cells[cell]=[]
				_shape_cells[cell].append(i)

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
		return shapes.filter(func(shape):return rect.intersects(shape.bounds))
	last_query_indexed=true
	var candidates:Dictionary={}
	for i in _large_shapes:candidates[i]=true
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			for i in _shape_cells.get(Vector2i(x,y),[]):candidates[i]=true
	last_query_candidates=candidates.size()
	var ordered:Array=candidates.keys();ordered.sort()
	var result:Array=[]
	# Shape IDs are their original painter order, including equal-height ties.
	for i:int in ordered:
		if rect.intersects(shapes[i].bounds):result.append(shapes[i])
	return result

func build(root:Node)->void:
	shapes.clear();markers.clear()
	title=str(preload("res://scripts/world3d/gltf_map_io.gd").extras_of(root).get("map_name","三维地图"))
	var first:=true
	for spec in root.get_meta("stream_library",[]):
		if not spec.get("mesh") is Mesh:continue
		var extra:Dictionary=spec.get("extras",{})
		var building:Dictionary=extra.get("building",{})
		# A map shows occupied ground-floor footprints, not every hinge, tread,
		# roof tile and upper-storey surface. Separate slabs preserve courtyard holes.
		if not building.is_empty() and (building.get("role")!="floor" or int(building.get("floor",0))!=0):continue
		var box:AABB=spec.mesh.get_aabb()
		var transform:Transform3D=spec.transform
		var projected:=PackedVector2Array()
		for i in 8:
			var p:Vector3=transform*box.get_endpoint(i)
			projected.append(Vector2(p.x,p.z))
		var polygon:=Geometry2D.convex_hull(projected)
		var rect:=Rect2(projected[0],Vector2.ZERO)
		for p in projected:rect=rect.expand(p)
		bounds=rect if first else bounds.merge(rect);first=false
		var kind:=str(extra.get("kind",""))
		var center:=rect.get_center()
		if kind in ["npc","warp","gather"] or extra.get("hostile",false) or extra.get("ally",false):
			markers.append({"position":center,"id":str(spec.uuid),"kind":kind,"hostile":bool(extra.get("hostile",false)),"name":str(extra.get("name",kind))})
			continue
		if polygon.size()<4:continue
		var world_box:AABB=transform*box
		var color:=Color("68765b") if world_box.size.y<.6 else Color("8c8374")
		if not building.is_empty():color=Color("8c8374")
		if kind=="water":color=Color("4b7888")
		shapes.append({"polygon":polygon,"bounds":rect,"color":color,"height":world_box.end.y})
	shapes.sort_custom(func(a,b):return a.height<b.height)
	rebuild_shape_index()
	if first:bounds=Rect2(-10,-10,20,20)
	bounds=bounds.grow(2)

func toggle_pin(point:Vector2)->void:
	for i in pins.size():
		if pins[i].distance_to(point)<1.5:pins.remove_at(i);return
	if pins.size()>=3:pins.pop_front()
	pins.append(point)
