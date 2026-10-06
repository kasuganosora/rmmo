extends RefCounted
## Spatial candidate selection; narrow phase retains the existing polygon tests.
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
var cells: Dictionary={}
var entries: Array=[]
static func keys(box: AABB) -> Array:
	var result: Array=[]
	for z in range(floori(box.position.z/32),floori(box.end.z/32)+1):
		for x in range(floori(box.position.x/32),floori(box.end.x/32)+1): result.append(Vector2i(x,z))
	return result
func add(shape: Dictionary,id: String,support: bool,road:=false) -> void:
	var index:=entries.size(); entries.append({"shape":shape,"id":id,"support":support,"road":road})
	for key in keys(shape.bounds):
		if not cells.has(key): cells[key]=[]
		cells[key].append(index)
func query(box: AABB) -> Array:
	var indices: Dictionary={}
	for key in keys(box):
		for index in cells.get(key,[]): indices[index]=true
	return indices.keys().map(func(i):return entries[i])
