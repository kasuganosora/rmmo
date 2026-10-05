extends SceneTree
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var path:="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	var meta:=Cook.Envelope.read(path,FileAccess.get_sha256(path))
	var unique:Dictionary={}
	for r:Dictionary in meta.rmmo_records:
		if r.has("house_prefab"):unique[r.house_prefab.sha256]=r.house_prefab
	var totals:Dictionary={"base64":0,"decompress":0,"checksum":0,"deserialize":0,"validate":0,"geometry_hash":0,"index_boxed":0,"index_sorted":0}
	var index_count:=0;var exact:=true
	for value:Dictionary in unique.values():
		var start:=Time.get_ticks_usec();var compressed:=Marshalls.base64_to_raw(value.data)
		totals.base64+=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
		var bytes:=compressed.decompress(value.length,FileAccess.COMPRESSION_ZSTD)
		totals.decompress+=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
		exact=exact and Cook.Envelope.checksum(bytes).hex_encode()==value.sha256
		totals.checksum+=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
		var data:Dictionary=bytes_to_var(bytes)
		totals.deserialize+=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
		exact=exact and Cook.valid_data(data)
		totals.validate+=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
		for mesh:Dictionary in data.meshes:Cook.Envelope.checksum(var_to_bytes(mesh.surfaces))
		totals.geometry_hash+=Time.get_ticks_usec()-start
		for mesh:Dictionary in data.meshes:
			for surface:Array in mesh.surfaces:
				if surface[Mesh.ARRAY_INDEX]==null or surface[Mesh.ARRAY_INDEX].is_empty():continue
				var indices:PackedInt32Array=surface[Mesh.ARRAY_INDEX];index_count+=indices.size()
				start=Time.get_ticks_usec();var boxed:=Array(indices);var lo:int=boxed.min();var hi:int=boxed.max()
				totals.index_boxed+=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
				var ordered:=indices.duplicate();ordered.sort()
				totals.index_sorted+=Time.get_ticks_usec()-start
				exact=exact and lo==ordered[0] and hi==ordered[-1]
	print("PREFAB_DECODE_BENCHMARK ",JSON.stringify({"serial_us":totals,"unique":unique.size(),"indices":index_count,"equivalent":exact}))
	quit(0 if exact else 1)
