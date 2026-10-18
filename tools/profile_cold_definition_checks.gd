extends SceneTree
## Actual immutable definitions; compare full index identities under both
## traversal policies. No author writes and no directory/cache publication.
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const MAP="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const ROOT="D:/code/rmmo_runtime"
func _initialize()->void:run.call_deferred()
func numeric_array_leaves(value:Variant)->int:
	var count:=0
	if value is Array:
		for item in value:
			if typeof(item) in [TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_FLOAT]:count+=1
			elif item is Array or item is Dictionary:count+=numeric_array_leaves(item)
	elif value is Dictionary:
		for key in value:
			if value[key] is Array or value[key] is Dictionary:count+=numeric_array_leaves(value[key])
	return count
func run()->void:
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if DisplayServer.get_name()!="headless" or not Index.Paths.allowed(output,ROOT+"/review_artifacts"):quit(2);return
	var source:=Index._source(MAP,ROOT,"")
	if not source.ok:quit(1);return
	var read:=Store.read_records(source.extras.rmmo_records,MAP,ROOT,source.dependencies)
	if not read.ok:quit(1);return
	var unique:Dictionary={};var jobs:Array=[];var removed_calls:=0
	for i:int in read.records.size():
		var ref:Dictionary=source.extras.rmmo_records[i].rmmo_ref
		if unique.has(ref.sha256):continue
		unique[ref.sha256]=true
		var definition:=Store._definition(read.records[i]);removed_calls+=numeric_array_leaves(definition)
		jobs.append({"definition":definition,"sha256":ref.sha256,"length":int(ref.length)})
	var report:={"sha":source.source._signature,"definitions":jobs.size(),"removed_scalar_calls_per_scan":removed_calls,"runs":[],"failures":[]}
	var expected:Array=[]
	for enabled:bool in [false,true,true,false]:
		Store.inline_numeric_safety_enabled=enabled
		var started:=Time.get_ticks_usec()
		var batch:=Store._read_many(jobs,false,4,Index._encode_index_definition)
		var elapsed:=Time.get_ticks_usec()-started
		if not batch.ok:report.failures.append("batch_failed");break
		if expected.is_empty():expected=batch.entries
		if batch.entries!=expected:report.failures.append("identity_changed")
		for i in jobs.size():
			if batch.entries[i].sha256!=jobs[i].sha256 or batch.entries[i].length!=jobs[i].length:report.failures.append("reference_mismatch")
		report.runs.append({"inline":enabled,"elapsed_us":elapsed,"profile":batch.read_profile})
	Store.inline_numeric_safety_enabled=true
	report.unchanged=source.source.matches_disk()
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report))
	quit(0 if report.failures.is_empty() and report.unchanged else 1)
