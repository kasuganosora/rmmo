extends SceneTree
const Directory=preload("res://scripts/world3d/map_dependency_index.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const MAP="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
func _initialize()->void:run.call_deferred()
func run()->void:
	var current:=Directory.read_for_loading(MAP,"D:/code/rmmo_runtime")
	if not current.ok:print(current);quit(1);return
	var records:Array=[]
	for row:Dictionary in current.index.rows:
		if row.reason=="unknown_geometry":records.append(current.index.extras.rmmo_records[row.order])
	var decoded:=Store.read_records(records,MAP,"D:/code/rmmo_runtime")
	if not decoded.ok:print(decoded);quit(1);return
	var groups:Dictionary={}
	for record:Dictionary in decoded.records:
		var keys:Array=record.keys();keys.sort()
		var extra:Array=[]
		for key:String in keys:
			if key not in Directory.COMMON_FIELDS+Directory.ASSET_FIELDS:extra.append(key)
		var group:String=str(record.kind)+":"+str(record.get("building_shape",""))+":"+str(extra)
		if not groups.has(group):groups[group]={"count":0,"samples":[],"keys":keys}
		groups[group].count+=1
		if groups[group].samples.size()<3:groups[group].samples.append(record.uuid)
	print(JSON.stringify(groups,"\t"))
	quit()
