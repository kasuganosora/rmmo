extends SceneTree
## Read-only profile of an already published temporary map; never installs a manifest.
const Pose=preload("res://scripts/world3d/pose_save.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
var report:Dictionary={}
var content_root:String=""
func _initialize()->void:run.call_deferred()
func timed(label:String,started:int)->void:
	report[label]=(Time.get_ticks_usec()-started)/1000.0
	print("HASH_PROBE ",label," ",report[label])
func hash_entries(entries:Array)->Dictionary:
	var result:Dictionary={};var allowed_us:=0;var hash_us:=0
	for path:String in entries:
		var started:=Time.get_ticks_usec()
		if not Paths.allowed(path,content_root):return {"ok":false,"path":path}
		allowed_us+=Time.get_ticks_usec()-started;started=Time.get_ticks_usec()
		var digest:=FileAccess.get_sha256(path)
		hash_us+=Time.get_ticks_usec()-started
		if digest.is_empty():return {"ok":false,"path":path}
		result[path]=digest
	return {"ok":true,"files":result,"allowed_ms":allowed_us/1000.0,"hash_ms":hash_us/1000.0}
func parallel_hash(entries:Array,count_:int)->Dictionary:
	var groups:Array=[];var sizes:Array=[]
	for index in count_:groups.append([]);sizes.append(0)
	var lengths:Dictionary={}
	for path:String in entries:
		var file:=FileAccess.open(path,FileAccess.READ)
		lengths[path]=file.get_length() if file!=null else 0
	entries.sort_custom(func(a,b):return lengths[a]>lengths[b])
	for path:String in entries:
		var smallest:int=sizes.find(sizes.min())
		groups[smallest].append(path);sizes[smallest]+=lengths[path]
	var threads:Array=[]
	for group:Array in groups:
		var worker:=Thread.new()
		if worker.start(hash_entries.bind(group))!=OK:return {"ok":false}
		threads.append(worker)
	var result:Dictionary={};var workers:Array=[];var ok:=true
	for worker:Thread in threads:
		var outcome:Dictionary=worker.wait_to_finish()
		ok=ok and outcome.ok
		result.merge(outcome.get("files",{}));workers.append({"allowed_ms":outcome.get("allowed_ms"),"hash_ms":outcome.get("hash_ms")})
	return {"ok":ok,"files":result,"workers":workers,"bytes":sizes}
func run()->void:
	content_root=Paths.external_root()
	var path:="D:/code/rmmo_runtime/cache/world3d/town_pose_save_9586014/map.gltf"
	var started:=Time.get_ticks_usec();var bytes:=FileAccess.get_file_as_bytes(path);timed("read_bytes_ms",started)
	started=Time.get_ticks_usec();var text:=bytes.get_string_from_utf8();timed("decode_utf8_ms",started)
	started=Time.get_ticks_usec();var data:Dictionary=JSON.parse_string(text);timed("json_parse_ms",started)
	var manifest:Dictionary=data.extras[Pose.MANIFEST]
	started=Time.get_ticks_usec();report.valid_content=Pose.valid_content(text,manifest);timed("current_string_checksum_ms",started)
	started=Time.get_ticks_usec()
	var digest:String=manifest.rmmo_saved_content_sha256
	var needle:String='"rmmo_saved_content_sha256":"'+digest+'"'
	var offset:=text.find(needle)
	var byte_offset:=text.left(offset+needle.length()-65).to_utf8_buffer().size()
	var original:=bytes.slice(byte_offset,byte_offset+64)
	for index in 64:bytes[byte_offset+index]=48
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes)
	report.bytes_checksum_matches=context.finish().hex_encode()==digest
	for index in 64:bytes[byte_offset+index]=original[index]
	timed("bytes_checksum_with_offset_ms",started)
	started=Time.get_ticks_usec();context=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes)
	report.map_sha256=context.finish().hex_encode();timed("map_bytes_sha_ms",started)
	started=Time.get_ticks_usec();var collected:Dictionary={};Pose._paths(data.nodes[Pose._root(data)].extras.rmmo_records,collected);timed("record_path_walk_ms",started)
	report.direct_paths=collected.size()
	var expected:Dictionary=manifest.sources.duplicate()
	for uri:String in manifest.dependencies:
		expected[path.get_base_dir().path_join(Io.decode_dependency_uri(uri)).simplify_path()]=manifest.dependencies[uri]
	report.source_files=manifest.sources.size();report.all_files=expected.size()
	started=Time.get_ticks_usec();var source_serial:=hash_entries(manifest.sources.keys());timed("serial_sources_ms",started)
	report.source_allowed_ms=source_serial.get("allowed_ms");report.source_hash_ms=source_serial.get("hash_ms")
	var published:Array=[]
	for dependency:String in expected:
		if not manifest.sources.has(dependency):published.append(dependency)
	started=Time.get_ticks_usec();var serial:=hash_entries(published);timed("serial_dependencies_ms",started)
	report.dependency_allowed_ms=serial.get("allowed_ms");report.dependency_hash_ms=serial.get("hash_ms")
	serial.files.merge(source_serial.files)
	report.serial_matches=serial.ok and source_serial.ok and Pose.same(expected,serial.files)
	for count_ in [2,4]:
		started=Time.get_ticks_usec();var parallel:=parallel_hash(expected.keys(),count_);timed("threads_%d_total_ms"%count_,started)
		report["threads_%d_matches"%count_]=parallel.ok and Pose.same(expected,parallel.files)
		report["threads_%d_workers"%count_]=parallel.workers
	report.path=path
	var file:=FileAccess.open("D:/code/rmmo_runtime/review_artifacts/pose_save_hash_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("HASH_PROBE_FINISHED ",JSON.stringify(report))
	quit(0 if report.valid_content and report.bytes_checksum_matches and report.serial_matches and report.threads_2_matches and report.threads_4_matches else 1)
