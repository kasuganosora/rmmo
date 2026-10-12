extends SceneTree
## Read-only source audit. Writes only independent artefacts, never map/cache data.
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const MAP="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const OUT="D:/code/rmmo_runtime/art_sources/stone_bridge_optimization_20261009"
const ID="stone_e_0be972769041dbc9"
func _initialize()->void:run.call_deferred()
func write_json(name:String,data:Variant)->void:
	var f:=FileAccess.open(OUT+"/"+name,FileAccess.WRITE);f.store_string(JSON.stringify(data,"  "));f.close()
func blob(name:String,data:PackedByteArray)->void:
	var f:=FileAccess.open(OUT+"/"+name,FileAccess.WRITE);f.store_buffer(data);f.close()
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var j:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MAP))
	var compact:Dictionary={}
	for n:Dictionary in j.nodes:
		for r:Dictionary in n.get("extras",{}).get("rmmo_records",[]):
			if r.uuid==ID:compact=r
	assert(not compact.is_empty())
	var ref:Dictionary=compact.rmmo_ref
	var path:=MAP.get_base_dir().path_join(ref.uri)
	var source:=Store._read(path,ref.sha256,int(ref.length))
	assert(source.ok)
	var record:Dictionary=source.definition.duplicate(true)
	for key in Store.FIELDS:record[key]=compact[key]
	for key in compact.rmmo_state:record[key]=compact.rmmo_state[key]
	var data:=Frozen.decode(record.house_prefab)
	assert(not data.is_empty())
	blob("source_master.rmres",FileAccess.get_file_as_bytes(path))
	write_json("original_record.json",record)
	blob("original_cooked.bin",var_to_bytes(data))
	var summary:Dictionary={"source":path,"source_sha256":ref.sha256,"source_bytes":ref.length,"compact":compact,"record_fields":record.keys(),"bridge_mesh":record.bridge_mesh,"materials":data.materials,"entries":data.entries,"meshes":[],"prefab_raw_bytes":record.house_prefab.length,"prefab_sha256":record.house_prefab.sha256,"source_preserved":FileAccess.get_sha256(path)==ref.sha256}
	for mi in data.meshes.size():
		var mesh:Dictionary=data.meshes[mi]
		var row:Dictionary={"index":mi,"bounds":var_to_str(mesh.bounds),"materials":mesh.materials,"surfaces":[],"box_size":var_to_str(mesh.box_size)}
		for si in mesh.surfaces.size():
			var arrays:Array=mesh.surfaces[si]
			var surface:Dictionary={"index":si,"slots":[]}
			for slot in arrays.size():
				if arrays[slot]==null:continue
				var name:="mesh_%d_surface_%d_slot_%d.bin"%[mi,si,slot]
				var bytes:PackedByteArray=arrays[slot].to_byte_array()
				blob(name,bytes)
				surface.slots.append({"slot":slot,"type":typeof(arrays[slot]),"count":arrays[slot].size(),"bytes":bytes.size(),"file":name,"sha256":Store._sha(bytes)})
			row.surfaces.append(surface)
		summary.meshes.append(row)
	write_json("source_audit.json",summary)
	print("BRIDGE_STATIC_AUDIT meshes=",data.meshes.size()," materials=",data.materials.size()," raw=",record.house_prefab.length)
	quit()
