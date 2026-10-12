extends RefCounted
## Synchronous operation-owned broad phase. Never retained through edits/undo.
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const Footprint=preload("res://scripts/world_editor/building_footprint.gd")
const CELL:=32.0
const MAX_CELLS:=256
var entries:Array=[]
var cells:Dictionary={}
var global_entries:Array=[]
var shape_builds:=0

func capture(records:Array,excluded:Dictionary)->void:
	entries.clear();cells.clear();global_entries.clear();shape_builds=0
	for record:Dictionary in records:
		if excluded.has(record.uuid):continue
		var entry:Dictionary={"record":record}
		# These footprints include vertical clearance or an opening sweep beyond
		# plain render bounds. Cache their exact shapes once, never shrink them.
		if record.has("rock_bank") or record.has("road_mesh") or record.has("channel_mesh") or (record.has("fixture") and record.has("fortification")):
			entry.shapes=Footprint.record_shapes(record);shape_builds+=1
			if entry.shapes.is_empty():continue
			entry.bounds=entry.shapes[0].bounds
			for shape:Dictionary in entry.shapes:entry.bounds=entry.bounds.merge(shape.bounds)
		else:entry.bounds=Geometry.bounds([record])
		var at:=entries.size();entries.append(entry)
		var low:=Vector2i(floori(entry.bounds.position.x/CELL),floori(entry.bounds.position.z/CELL))
		var high:=Vector2i(floori(entry.bounds.end.x/CELL),floori(entry.bounds.end.z/CELL))
		if (high.x-low.x+1)*(high.y-low.y+1)>MAX_CELLS:global_entries.append(at);continue
		for x in range(low.x,high.x+1):
			for z in range(low.y,high.y+1):
				var key:=Vector2i(x,z)
				if not cells.has(key):cells[key]=[]
				cells[key].append(at)

func obstacles(bounds:AABB)->Array:
	var query:=bounds.grow(.02);var selected:Dictionary={}
	var low:=Vector2i(floori(query.position.x/CELL),floori(query.position.z/CELL))
	var high:=Vector2i(floori(query.end.x/CELL),floori(query.end.z/CELL))
	if (high.x-low.x+1)*(high.y-low.y+1)>MAX_CELLS:
		for at in entries.size():selected[at]=true
	else:
		for at in global_entries:selected[at]=true
		for x in range(low.x,high.x+1):
			for z in range(low.y,high.y+1):
				for at in cells.get(Vector2i(x,z),[]):selected[at]=true
	# Preserve original conflict ordering, independent of spatial bucket order.
	var indices:Array=selected.keys();indices.sort()
	var result:Array=[]
	for at:int in indices:
		var entry:Dictionary=entries[at]
		if not entry.bounds.grow(.01).intersects(query):continue
		if not entry.has("shapes"):entry.shapes=Footprint.record_shapes(entry.record);shape_builds+=1
		for shape:Dictionary in entry.shapes:
			result.append({"id":entry.record.uuid,"record":entry.record,"shape":shape})
	return result
