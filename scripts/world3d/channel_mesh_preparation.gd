extends RefCounted
## CPU-only preparation. A context cache hit does not prove every channel mesh
## was cookable; only an exact restored geometry key may skip preparation.
const Channel=preload("res://scripts/world3d/channel_surface.gd")
static func supports(record:Dictionary)->bool:
	# Fortification art uses channel polygons as a clipping mask, not as its
	# rendered slab. Gates and explicit building shapes also have later builders.
	return record.has("channel_mesh") and not record.has("fortification_art") and not record.has("water_gate") and str(record.get("building_shape","")).is_empty()
static func cached_keys(cooked:Dictionary)->Dictionary:
	var result:Dictionary={}
	for entry:Array in cooked.get("entries",[]):
		var key:Variant=entry[0]
		if key is Array and key.size()==3 and key[0]=="channel_mesh":result[key]=true
	return result
static func cached(record:Dictionary,context:RefCounted,keys:Dictionary)->bool:
	return keys.has(["channel_mesh",record,context.data.get(str(record.uuid),{}).get("normals",{})])
static func prepare(records:Array,context:RefCounted,keys:Dictionary)->Dictionary:
	var result:Dictionary={}
	for record:Dictionary in records:
		if supports(record) and not cached(record,context,keys):result[str(record.uuid)]=Channel.arrays(record)
	return result
