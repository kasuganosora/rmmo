extends RefCounted
## One brush transaction, indexed cells, cardinally connected interpolation.
const Rules = preload("res://scripts/world3d/auto_tile_rules.gd")
const Doc = preload("res://scripts/world3d/world_document.gd")
var active := false
var changed := false
var doc
var family := ""
var cell_size := 4.0
var elevation := 0.0
var erase := false
var before: Array = []
var index := {}
var last: Variant = null
var touched := {}
var error := ""
var options := {}
var editable: Callable
var staged:=false
var source_document:RefCounted
var source_revision:=0
var source_next:=0
var generation:=0
var preview_ids:Dictionary={}
var _copied:Dictionary={}
var _positions:Dictionary={}
var _positions_dirty:=false


func begin(document, selected_family: String, spacing: float, height: float, erasing: bool, settings: Dictionary = {}, private:bool=false) -> void:
	staged=private;source_document=document;source_revision=document.authoring_revision;source_next=document._next;generation+=1
	doc=Doc.new() if staged else document
	if staged:doc.records=document.records.duplicate();doc.map_meta=document.map_meta;doc._next=document._next
	family = selected_family
	cell_size = spacing
	elevation = snappedf(height, 0.001)
	erase = erasing
	before = [] if staged else doc.records.duplicate(true)
	preview_ids.clear();_copied.clear();_positions.clear();_positions_dirty=true
	index = Rules.index_records(doc.records)
	last = null
	touched.clear()
	changed = false
	error = Rules.options_error(family, elevation, settings)
	options = Rules.normalized_options(family, settings)
	active = error.is_empty() and family in Rules.FAMILIES and cell_size > 0 and is_finite(cell_size) and is_finite(elevation)


func paint(point: Vector3) -> Array[String]:
	var changed_ids: Array[String] = []
	if not active or not point.is_finite(): return changed_ids
	var cell := Rules.cell_at(point, cell_size)
	var from: Vector2i = cell if last == null else last
	if absi(cell.x - from.x) + absi(cell.y - from.y) > 1024:
		error = "一次拖动画笔跨度超过 1024 格，请缩小范围"
		last = null
		return changed_ids
	var cells := _line(from, cell)
	last = cell
	var affected := {}
	for at in cells:
		var layer := float(options.get("base_height", 0)) if family == "cliff" else elevation
		var key := Rules.key(at, family, cell_size, layer)
		if touched.has(key): continue
		touched[key] = true
		var record: Dictionary = index.get(key, {})
		if not record.is_empty() and editable.is_valid() and not editable.call(record): continue
		if bool(record.get("editor_locked", false)) or bool(record.get("editor_hidden", false)): continue
		if erase:
			if record.is_empty() or record.tile3d.family != family: continue
			changed_ids.append(str(record.uuid))
			doc.remove(str(record.uuid))
			_positions_dirty=true
			index.erase(key)
		else:
			if not record.is_empty() and record.tile3d.family == family and float(record.tile3d.elevation) == elevation and record.tile3d.get("options", {}) == options: continue
			if record.is_empty():
				var uuid: String = doc.add_box_silent("ground", Vector3.ZERO, Vector3.ONE)
				record = doc._find(uuid)
				_copied[uuid]=true;_positions_dirty=true
			else:record=_private_record(record,key)
			Rules.configure(record, at, family, cell_size, elevation, options)
			index[key] = record
			changed_ids.append(str(record.uuid))
		changed = true
		affected[key] = true
		for offset in Rules.OFFSETS: affected[at + offset] = true
		affected[at] = true
	# A height change also affects bridge landings on other logical layers.
	var surfaces := Rules.landing_index(index)
	for key:String in index:
		var record:Dictionary=index[key]
		var tile: Dictionary = record.tile3d
		if not affected.has(Vector2i(tile.cell[0], tile.cell[1])) or float(tile.cell_size) != cell_size: continue
		record=_private_record(record,key)
		if Rules.refresh(index, record, surfaces) and not changed_ids.has(str(record.uuid)):
			changed_ids.append(str(record.uuid))
	if not changed_ids.is_empty():generation+=1
	for id:String in changed_ids:preview_ids[id]=true
	return changed_ids

func current()->bool:
	return source_document!=null and source_document.authoring_revision==source_revision and source_document._next==source_next

func _private_record(record:Dictionary,key:String)->Dictionary:
	var id:=str(record.uuid)
	if not staged or _copied.has(id):return record
	if _positions_dirty:
		_positions.clear()
		for i:int in doc.records.size():_positions[str(doc.records[i].uuid)]=i
		_positions_dirty=false
	var next:=record.duplicate(true)
	doc.records[_positions[id]]=next;index[key]=next;_copied[id]=true
	return next

## Recompute only records around detached/replaced cells. The caller owns the
## document array; untouched record dictionaries remain immutable and shared.
static func refresh_around(document:RefCounted,ids:Array)->Array[String]:
	var affected:Dictionary={};var result:Array[String]=[]
	for id:String in ids:
		var record:Dictionary=document._find(id)
		if not record.has("tile3d"):continue
		var tile:Dictionary=record.tile3d;var cell:=Vector2i(tile.cell[0],tile.cell[1]);var spacing:=float(tile.cell_size)
		affected[Vector3(cell.x,cell.y,spacing)]=true
		for offset:Vector2i in Rules.OFFSETS:affected[Vector3(cell.x+offset.x,cell.y+offset.y,spacing)]=true
	if affected.is_empty():return result
	var neighbors:=Rules.index_records(document.records);var surfaces:=Rules.landing_index(neighbors)
	for i:int in document.records.size():
		var record:Dictionary=document.records[i]
		if not Rules.attached(record):continue
		var tile:Dictionary=record.tile3d
		if not affected.has(Vector3(tile.cell[0],tile.cell[1],float(tile.cell_size))):continue
		var next:=record.duplicate(true)
		if Rules.refresh(neighbors,next,surfaces):
			document.records[i]=next;neighbors[Rules.record_key(next)]=next;result.append(str(next.uuid))
	return result


func finish(cancel: bool = false) -> bool:
	if not active: return false
	active = false
	var applied := changed and not cancel
	if changed and not staged:
		if cancel: doc.records = before.duplicate(true)
		else: doc.commit_change(before)
	before.clear()
	index.clear()
	touched.clear()
	last = null
	return applied


static func _line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [from]
	var at := from
	var dx := absi(to.x - from.x)
	var dz := absi(to.y - from.y)
	var sx := 1 if to.x > from.x else -1
	var sz := 1 if to.y > from.y else -1
	var error := dx - dz
	while at != to:
		var twice := error * 2
		if twice > -dz:
			error -= dz
			at.x += sx
			result.append(at)
		if twice < dx:
			error += dx
			at.y += sz
			result.append(at)
	return result
