extends SceneTree
## CPU-only repeat-encoding benchmark; writes only its independent temp map.
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
func _init()->void:run.call_deferred()
func run()->void:
	var records:Array=[]
	var source:="";var source_sha:="";var open_ms:=0.
	if "--town" in OS.get_cmdline_user_args():
		source="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
		source_sha=FileAccess.get_sha256(source)
		var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(source))
		var compact:Array=[]
		for node:Dictionary in data.nodes:
			if node.get("extras",{}).has("rmmo_records"):compact=node.extras.rmmo_records;break
		var mark:=Time.get_ticks_usec()
		var opened:=Store.read_records(compact,source,Paths.external_root())
		open_ms=(Time.get_ticks_usec()-mark)/1000.
		if not opened.ok or opened.records.is_empty():push_error(str(opened));quit(1);return
		records=opened.records
	else:
		var crypto:=Crypto.new()
		for index in 48:
			records.append({"uuid":"sample_%d"%index,"position":[0.,0.,0.],"rotation":[0.,0.,0.],"size":[1.,1.,1.],"kind":"cpu_fixture","payload":crypto.generate_random_bytes(1024*1024),"nested":{"index":index}})
	var output:Dictionary={"record_count":records.size(),"source":source,"source_read_ms":open_ms,"passes":[]}
	if "--components" in OS.get_cmdline_user_args():
		var phases:Dictionary={"safe_ms":0.,"variant_hash_ms":0.,"serialize_ms":0.,"raw_sha_ms":0.,"raw_bytes":0}
		for record:Dictionary in records:
			var definition:=Store._definition(record)
			var mark:=Time.get_ticks_usec();var safe:=Store._safe(definition,[],[2000000]);phases.safe_ms+=(Time.get_ticks_usec()-mark)/1000.
			mark=Time.get_ticks_usec();var key:int=hash(definition);phases.variant_hash_ms+=(Time.get_ticks_usec()-mark)/1000.
			mark=Time.get_ticks_usec();var raw:=var_to_bytes(definition);phases.serialize_ms+=(Time.get_ticks_usec()-mark)/1000.;phases.raw_bytes+=raw.size()
			mark=Time.get_ticks_usec();var digest:=Store._sha(raw);phases.raw_sha_ms+=(Time.get_ticks_usec()-mark)/1000.
			if not safe or digest.is_empty() or key<0:push_error("invalid component input");quit(1);return
		output.components=phases
	elif "--encode-only" in OS.get_cmdline_user_args():
		for pass_index in 3:
			var start:=Time.get_ticks_usec();var hits:=0;var misses:=0;var raw:=0
			for record:Dictionary in records:
				var encoded:=Store._encode(Store._definition(record))
				if not encoded.ok:push_error(str(encoded));quit(1);return
				hits+=int(encoded.cache_hit);misses+=int(not encoded.cache_hit);raw+=int(encoded.encoded_raw_bytes)
			output.passes.append({"index":pass_index,"ms":(Time.get_ticks_usec()-start)/1000.,"hits":hits,"misses":misses,"compressed_raw_bytes":raw})
	else:
		var directory:=Paths.cache_directory("encoding_profile_%d"%Time.get_ticks_usec())
		var path:=directory.path_join("map.gltf")
		DirAccess.make_dir_recursive_absolute(directory)
		for pass_index in 3:
			if pass_index==1:records[0].position[0]=5.
			if pass_index==2:records.remove_at(0)
			var start:=Time.get_ticks_usec()
			var saved:=Store.write_records(records,path,Paths.external_root())
			if not saved.ok:push_error(str(saved));quit(1);return
			var measured:Dictionary={"index":pass_index,"ms":(Time.get_ticks_usec()-start)/1000.}
			for key in ["resources_written","resources_reused","bytes_written","encoding_cache_hits","encoding_cache_misses","encoded_raw_bytes","encoding_ms","verified_bytes","identity_cache_hits","serialized_raw_bytes","compression_count","identity_cache_entries"]:
				if saved.has(key):measured[key]=saved[key]
			output.passes.append(measured)
			print("REFERENCE_ENCODING_PASS ",JSON.stringify(measured))
		Io._remove_tree(directory)
	output.source_sha_unchanged=source.is_empty() or source_sha==FileAccess.get_sha256(source)
	Store._mutex.lock()
	output.identity_index_serialized_bytes=var_to_bytes(Store._identities).size()
	output.identity_entries=Store._identities.size()
	output.hot_cache_accounted_bytes=Store._cache_size
	Store._mutex.unlock()
	print("REFERENCE_ENCODING_PROFILE ",JSON.stringify(output))
	quit(0 if output.source_sha_unchanged else 1)
