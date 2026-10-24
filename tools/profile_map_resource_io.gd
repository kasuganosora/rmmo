extends SceneTree
## Isolate actual rmres IO/Variant decoding before changing its storage layout.
## The temporary bundle concatenates original bytes; no source is modified.
const MAP="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017"
func _initialize()->void:run.call_deferred()
func digest(value:Variant)->String:
	var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(var_to_bytes(value));return hashing.finish().hex_encode()
func run()->void:
	var output:=OUT.path_join("resource_io70.json")
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var map_sha:=FileAccess.get_sha256(MAP)
	var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MAP))
	var rows:Array=[];var seen:Dictionary={};var expected:Dictionary={};var failures:Array=[]
	var bundle_path:=OUT.path_join("resource_io70_%d.bin"%OS.get_process_id())
	var bundle:=FileAccess.open(bundle_path,FileAccess.WRITE)
	for record:Dictionary in document.nodes[0].extras.rmmo_records:
		if not record.has("rmmo_ref") or seen.has(record.rmmo_ref.uri):continue
		var path:=MAP.get_base_dir().path_join(record.rmmo_ref.uri);seen[record.rmmo_ref.uri]=true
		var bytes:=FileAccess.get_file_as_bytes(path)
		rows.append({"path":path,"sha256":record.rmmo_ref.sha256,"offset":bundle.get_position(),"length":bytes.size()})
		bundle.store_buffer(bytes)
	var bundle_bytes:=bundle.get_length();bundle.close()
	var trials:Array=[]
	for mode:String in ["loose","bundle","bundle","loose"]:
		var totals:Dictionary={"open_us":0,"read_us":0,"close_us":0,"decompress_us":0,"variant_us":0,"file_opens":0,"raw_bytes":0,"frozen_encoded_bytes":0}
		var handle:FileAccess
		if mode=="bundle":
			var began:=Time.get_ticks_usec();handle=FileAccess.open(bundle_path,FileAccess.READ);totals.open_us+=Time.get_ticks_usec()-began;totals.file_opens+=1
		for row:Dictionary in rows:
			if mode=="loose":
				var began:=Time.get_ticks_usec();handle=FileAccess.open(row.path,FileAccess.READ);totals.open_us+=Time.get_ticks_usec()-began;totals.file_opens+=1
			var began:=Time.get_ticks_usec()
			if mode=="bundle":handle.seek(row.offset)
			var bytes:=handle.get_buffer(row.length);totals.read_us+=Time.get_ticks_usec()-began
			if mode=="loose":began=Time.get_ticks_usec();handle.close();totals.close_us+=Time.get_ticks_usec()-began
			began=Time.get_ticks_usec();var raw:=bytes.slice(16).decompress(bytes.decode_u64(8),FileAccess.COMPRESSION_ZSTD);totals.decompress_us+=Time.get_ticks_usec()-began
			began=Time.get_ticks_usec();var definition:Variant=bytes_to_var(raw);totals.variant_us+=Time.get_ticks_usec()-began
			totals.raw_bytes+=raw.size()
			if definition is Dictionary and definition.has("house_prefab"):totals.frozen_encoded_bytes+=str(definition.house_prefab.data).length()
			# Exact authored payload checks run outside the measured IO/decode spans.
			var identity:=digest(definition)
			if not expected.has(row.sha256):expected[row.sha256]=identity
			elif identity!=expected[row.sha256]:failures.append({"source":row.path,"mode":mode})
		if mode=="bundle":var began:=Time.get_ticks_usec();handle.close();totals.close_us+=Time.get_ticks_usec()-began
		trials.append({"mode":mode,"totals":totals});print("RESOURCE_IO_TRIAL ",JSON.stringify(trials.back()))
	if FileAccess.get_sha256(MAP)!=map_sha:failures.append("map changed")
	var report:={"map_sha256":map_sha,"unique_resources":rows.size(),"bundle_path":bundle_path,"bundle_bytes":bundle_bytes,"trials":trials,"failures":failures,"scope":"Warm isolated IO/decompression/object-free Variant decode only. Audit hashes and conversion outside timers. No production bundle integration or whole-map speed claim."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));quit(0 if failures.is_empty() else 1)
