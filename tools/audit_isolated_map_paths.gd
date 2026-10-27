extends SceneTree
## Read-only inventory of explicit path-like values in hydrated records and map
## metadata; the inventory is not a proof of dynamic loading dependencies.
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const REVIEW="D:/code/rmmo_runtime/review_artifacts"
var entries:Dictionary={}
func _initialize()->void:run.call_deferred()
func visit(value:Variant,key:String)->void:
	if value is Dictionary:
		for field:Variant in value:visit(value[field],key+"."+str(field))
	elif value is Array:
		for child:Variant in value:visit(child,key+"[]")
	elif value is String:
		var s:String=value.replace("\\","/")
		if not (s.begins_with("D:/") or s.begins_with("C:/") or s.begins_with("user://") or s.begins_with("res://")):return
		if not entries.has(key):entries[key]={"count":0,"unique":{}}
		entries[key].count+=1;entries[key].unique[s]=true
func run()->void:
	var map:="";var root_:="";var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map=arg.trim_prefix("--map=")
		if arg.begins_with("--root="):root_=arg.trim_prefix("--root=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if map.is_empty() or root_.is_empty() or output.is_empty() or not Paths.allowed(map,root_) or not Paths.allowed(output,REVIEW) or FileAccess.file_exists(output):printerr("invalid input or output");quit(2);return
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(map));var extras:Dictionary={}
	if not data is Dictionary or not data.get("nodes") is Array:printerr("invalid map");quit(1);return
	for node:Variant in data.nodes:
		if node is Dictionary and node.get("extras") is Dictionary and node.extras.get("rmmo_records") is Array:
			if not extras.is_empty():printerr("multiple record roots");quit(1);return
			extras=node.extras
	if extras.is_empty():printerr("no map records");quit(1);return
	var restored:=Store.read_records(extras.rmmo_records,map,root_,extras.rmmo_resource_dependencies,1,false)
	if not restored.ok:printerr("read failed ",restored);quit(1);return
	for key:String in extras:
		if key not in ["rmmo_records","rmmo_resource_dependencies"]:visit(extras[key],"extras."+key)
	for record:Dictionary in restored.records:visit(record,"record")
	var model_classes:Dictionary={}
	for record:Dictionary in restored.records:
		if record.has("asset_path"):
			var class_key:=str(record.get("kind",""))+"|prefab="+str(record.has("house_prefab"))+"|model_building="+str(record.has("model_building"))
			if not model_classes.has(class_key):model_classes[class_key]={"count":0,"paths":{}}
			model_classes[class_key].count+=1;model_classes[class_key].paths[str(record.asset_path)]=true
	for key:String in model_classes:
		var model_paths:Array=model_classes[key].paths.keys();model_paths.sort();model_classes[key].paths=model_paths
	var grouped:Dictionary={}
	for key:String in entries:
		var values:Array=entries[key].unique.keys();values.sort()
		grouped[key]={"count":entries[key].count,"unique_count":values.size(),"values":values}
	var result:Dictionary={"map":map,"map_sha256":FileAccess.get_sha256(map),"records":restored.records.size(),"path_fields":grouped,"model_classes":model_classes,"note":"Explicit serialized path values only; runtime-generated and encoded paths require separate code review."}
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:printerr("output cannot be written");quit(1);return
	file.store_string(JSON.stringify(result,"\t"));file.close()
	print("MAP_PATH_INVENTORY records=",restored.records.size()," fields=",grouped.size()," output=",output)
	for key:String in grouped:print(key," count=",grouped[key].count," unique=",grouped[key].unique_count)
	for key:String in model_classes:print("MODEL_CLASS ",key," count=",model_classes[key].count," unique=",model_classes[key].paths.size())
	quit(0)
