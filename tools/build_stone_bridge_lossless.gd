extends SceneTree
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const OUT="D:/code/rmmo_runtime/art_sources/stone_bridge_optimization_20261009"
func _initialize()->void:run.call_deferred()
func run()->void:
	var audit:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/source_audit.json"))
	var source:=Store._read(OUT+"/source_master.rmres",audit.source_sha256)
	assert(source.ok)
	var definition:Dictionary=source.definition.duplicate(true)
	var original:=Frozen.decode(definition.house_prefab)
	var data:=original.duplicate(true)
	var render_id:int=data.entries[0][1][0];var collision_id:int=data.entries[0][1][1]
	assert(render_id!=collision_id)
	var removed:=0
	for si in data.meshes[render_id].surfaces.size():
		var arrays:Array=data.meshes[render_id].surfaces[si]
		var first:=FileAccess.get_file_as_bytes(OUT+"/remap_surface_%d_first.bin"%si).to_int32_array()
		var indices:=FileAccess.get_file_as_bytes(OUT+"/remap_surface_%d_indices.bin"%si).to_int32_array()
		removed+=arrays[Mesh.ARRAY_VERTEX].size()-first.size()
		for slot in arrays.size():
			if arrays[slot]==null or slot==Mesh.ARRAY_INDEX:continue
			var old:Variant=arrays[slot];var compact:Variant=old.slice(0,0)
			var stride:=4 if slot==Mesh.ARRAY_TANGENT else 1
			compact.resize(first.size()*stride)
			for i in first.size():
				for component in stride:compact[i*stride+component]=old[first[i]*stride+component]
			arrays[slot]=compact
		arrays[Mesh.ARRAY_INDEX]=indices
	assert(var_to_bytes(data.meshes[collision_id])==var_to_bytes(original.meshes[collision_id]))
	assert(data.materials==original.materials and data.entries==original.entries)
	assert(Frozen.Cook.valid_data(data))
	var raw:=var_to_bytes(data)
	definition.house_prefab={"version":1,"length":raw.size(),"sha256":Store._sha(raw),"data":Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_ZSTD))}
	var encoded:=Store._encode(definition)
	assert(encoded.ok and not encoded.bytes.is_empty())
	var candidate_path:String=OUT+"/"+encoded.sha256+".rmres"
	var f:=FileAccess.open(candidate_path,FileAccess.WRITE);f.store_buffer(encoded.bytes);f.close()
	var reread:=Store._read(candidate_path,encoded.sha256,encoded.length)
	assert(reread.ok and reread.definition==definition)
	var record:Dictionary=definition.duplicate(true)
	for key in Store.FIELDS:record[key]=audit.compact[key]
	for key in audit.compact.rmmo_state:record[key]=audit.compact.rmmo_state[key]
	f=FileAccess.open(OUT+"/candidate_record.json",FileAccess.WRITE);f.store_string(JSON.stringify(record));f.close()
	f=FileAccess.open(OUT+"/candidate_cooked.bin",FileAccess.WRITE);f.store_buffer(raw);f.close()
	var report:={"candidate":candidate_path,"sha256":encoded.sha256,"bytes":encoded.length,"raw_bytes":raw.size(),"removed_exact_duplicate_render_vertices":removed,"original_collision_data_byte_exact":true,"material_definitions_exact":true,"triangle_order_and_all_expanded_vertex_channels_exact":"array_analysis.json","rmres_reopen_exact":true,"published":false}
	f=FileAccess.open(OUT+"/candidate_audit.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	print(JSON.stringify(report));quit()
