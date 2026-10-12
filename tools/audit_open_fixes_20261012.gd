extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const House=preload("res://scripts/world3d/house_prefab.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/nonperformance_fixes_20261012"
func _initialize()->void:run.call_deferred()
func run()->void:
	var path:="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	var doc=Doc.open_file(path)
	if doc==null:quit(1);return
	var rows:Array=[];var houses:Dictionary={};var bridges:Array=[];var roads:Array=[]
	for r:Dictionary in doc.records:
		if r.has("road_mesh"):roads.append(r)
		if r.has("bridge_mesh"):
			var data:Dictionary=House.decode(r.house_prefab) if r.has("house_prefab") else {}
			bridges.append({"uuid":r.uuid,"asset_path":r.get("asset_path"),"frozen":r.has("house_prefab"),"materials":data.get("materials",[])})
		if r.get("kind")=="asset" and not r.has("house_prefab"):
			var p:=Vector2(r.position[0],r.position[2])
			if p.distance_to(Vector2(392,238))<35 or p.distance_to(Vector2(302,192))<35 or p.distance_to(Vector2(330,231))<25:
				rows.append(r)
	for id in doc.map_meta.get("building_instances",{}):
		var h:Dictionary=doc.map_meta.building_instances[id];var p:=Vector2(h.position[0],h.position[2])
		houses[id]=h
	DirAccess.make_dir_recursive_absolute(OUT)
	var f:=FileAccess.open(OUT+"/audit.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"sha256":FileAccess.get_sha256(path),"records":rows,"houses":houses,"bridges":bridges,"roads":roads,"layout":doc.map_meta.get("editor_layout",{})},"\t"));f.close()
	print("AUDIT rows=",rows.size()," houses=",houses.size()," bridges=",bridges.size());quit()
