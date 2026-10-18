extends RefCounted
## Sparse deletion uses the existing insertion-ordered identity catalogue.
## Validate every selected position before mutation; malformed/reordered public
## inputs and large removals fall back to the caller's ordinary stable scan.
static func erase_small(values:Array,members:Dictionary,selected:Dictionary)->bool:
	if selected.size()>16 or values.size()!=members.size():return false
	var keys:Array=members.keys();var positions:Array[int]=[]
	for id:String in selected:
		var at:=keys.find(id)
		if at<0 or not values[at] is Dictionary or values[at].get("uuid")!=id:return false
		positions.append(at)
	positions.sort()
	for i:int in range(positions.size()-1,-1,-1):values.remove_at(positions[i])
	return true
