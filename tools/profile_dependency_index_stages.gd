extends SceneTree
## Read-only CPU probe of the existing index path. Reports inside the workspace.
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Manifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Proof=preload("res://scripts/world3d/dependency_index_proof.gd")
const MAP="D:/code/rmmo_runtime/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf"
var report:Dictionary={"runs":[],"failures":0}
func _initialize()->void:run.call_deferred()
func measure(out:Dictionary,label_:String,task:Callable)->Variant:
	var started:=Time.get_ticks_usec();var result:Variant=task.call()
	out[label_]=Time.get_ticks_usec()-started;return result
func probe()->Dictionary:
	var out:Dictionary={};var root_:String=Paths.external_root()
	var opened:Dictionary=measure(out,"source",func():return Index._source(MAP,root_,""))
	if not opened.ok:return {"error":opened}
	var target:String=Index.cache_path(MAP,root_)
	var read_bytes:=func()->PackedByteArray:
		var file:=FileAccess.open(target,FileAccess.READ)
		if file==null or file.get_buffer(9).get_string_from_ascii()!=Index.MAGIC:return PackedByteArray()
		var length:=file.get_64();var checksum:=file.get_buffer(32);var bytes:=file.get_buffer(length)
		if bytes.size()!=length or Store._sha(bytes).hex_decode()!=checksum:return PackedByteArray()
		return bytes
	var bytes:PackedByteArray=measure(out,"read_hash",read_bytes)
	var data:Dictionary=measure(out,"decode",func():return bytes_to_var(bytes))
	var schema:bool=measure(out,"schema",func():return Index._valid_payload(data,opened.extras.rmmo_records,root_))
	var owner:bool=measure(out,"ownership",func():return Index._ownership_valid(opened.extras,data.rows,data.groups))
	var generator:String=measure(out,"generator",Index.generator_key)
	var changed:Dictionary={}
	measure(out,"model_manifests",func():
		for path:String in data.models:
			var current:Dictionary=Manifest.read(path) if Paths.allowed(path,root_) else {}
			var expected:Dictionary=data.models[path]
			if not current.get("known",false) or current.get("json_sha256")!=expected.json_sha256 or current.get("file_length")!=expected.file_length or current.get("local_bounds")!=expected.local_bounds:changed[path]=true
		for row:Dictionary in data.rows:
			if changed.has(row.asset_path):row.classification="global";row.reason="model_bounds_changed";row.bounds_known=false
		return true)
	var unchanged:bool=measure(out,"final_source",func():return Paths.allowed(target,root_) and opened.source.matches_disk())
	var index:Dictionary=Index._result(data,opened.extras,target)
	var proof:RefCounted=measure(out,"seal",func():return Proof.issue(index,MAP,root_,RefCounted.new()))
	out.ok=schema and owner and unchanged and proof!=null and data.generator==generator and data.source_sha256==opened.source._signature
	out.models=data.models.size();out.rows=data.rows.size();out.bytes=bytes.size();out.changed=changed.size()
	return out
func run()->void:
	if DisplayServer.get_name()!="headless":quit(2);return
	Index.batch_path_validation=true
	report.warmup=probe()
	if not report.warmup.get("ok",false):report.failures+=1
	for enabled:bool in [false,true,true,false]:
		Index.batch_path_validation=enabled
		var result:=probe()
		result.path_batching=enabled
		report.runs.append(result);print(JSON.stringify(result))
		if not result.get("ok",false):report.failures+=1
	DirAccess.make_dir_recursive_absolute("res://review_artifacts/loading_path_20261010")
	var file:=FileAccess.open("res://review_artifacts/loading_path_20261010/index_stages.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	quit(0 if report.failures==0 else 1)
