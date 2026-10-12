extends SceneTree
func _initialize()->void:
	var path:="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	var doc:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var records:Array=doc.nodes[0].extras.rmmo_records
	var definitions:Dictionary={}
	var definition_rows:Array=[]
	var model_records:Array=[]
	for record in records:
		var uri:String=record.rmmo_ref.uri
		if not definitions.has(uri):
			var bytes:PackedByteArray=FileAccess.get_file_as_bytes(path.get_base_dir().path_join(uri))
			var raw:=bytes.slice(16).decompress(bytes.decode_u64(8),FileAccess.COMPRESSION_ZSTD)
			var definition:Dictionary=bytes_to_var(raw)
			var row:={"uri":uri,"file_bytes":bytes.size(),"raw_bytes":raw.size(),"keys":definition.keys(),"paths":[],"array_sizes":{}}
			collect(definition,"",row)
			definitions[uri]=row
			definition_rows.append(row)
		model_records.append({"uuid":record.uuid,"uri":uri,"state":record.rmmo_state,"paths":definitions[uri].paths})
	var output:={"map":path,"definitions":definition_rows,"records":model_records}
	var file:=FileAccess.open("D:/code/rmmo/review_artifacts/town_asset_size_audit_20261011/inventory_map_definitions.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"  "));file.close()
	print("INVENTORY_DECODE ",records.size()," records / ",definitions.size()," definitions")
	quit()
func collect(value:Variant,key:String,row:Dictionary)->void:
	if value is Dictionary:
		for k in value:collect(value[k],key+"/"+str(k),row)
	elif value is Array:
		row.array_sizes[key]=value.size()
		for i in value.size():collect(value[i],key+"/"+str(i),row)
	elif value is PackedByteArray or value is PackedVector3Array or value is PackedVector2Array or value is PackedInt32Array or value is PackedFloat32Array or value is PackedColorArray:
		row.array_sizes[key]=value.size()
	elif value is String:
		if value.contains("D:/") or value.begins_with("res://") or value.ends_with(".glb") or value.ends_with(".png") or value.ends_with(".jpg"):row.paths.append({"key":key,"path":value})
