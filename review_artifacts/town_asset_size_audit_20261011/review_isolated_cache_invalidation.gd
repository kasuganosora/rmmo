extends SceneTree
## Headless contract probe for a COMPLETED baseline/candidate review only.
## --report=<.../baseline.json> (or candidate.json)
## Mutates/restores only that report's isolated_content/assets/review.glb.
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Preparation=preload("res://scripts/world3d/compiled_asset_preparation.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var report_path:=""
var result:Dictionary={"checks":[],"failures":[],"scope":"Isolated source-copy invalidation; production source/map/cache untouched."}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->bool:
	result.checks.append({"ok":ok,"label":label})
	if not ok:result.failures.append(label);push_error(label)
	return ok
func read_json(path:String)->Dictionary:
	var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if raw is Dictionary else {}
func save()->void:
	result.passed=result.failures.is_empty() and result.get("status","")!="deferred"
	var path:=report_path.trim_suffix(".json")+"_cache_invalidation.json"
	var f:=FileAccess.open(path,FileAccess.WRITE)
	if f!=null:f.store_string(JSON.stringify(result,"  ",true,true));f.close()
	print("ISOLATED_CACHE_INVALIDATION passed=",result.passed," report=",path)
	quit(3 if result.get("status","")=="deferred" else (0 if result.passed else 1))
func mutated_copy(input:String,output:String)->Error:
	# Stream BIN untouched; do not allocate the hundreds-of-MiB source in RAM.
	var src:=FileAccess.open(input,FileAccess.READ)
	if src==null:return FileAccess.get_open_error()
	if src.get_32()!=0x46546c67 or src.get_32()!=2:src.close();return ERR_FILE_UNRECOGNIZED
	var original_length:=src.get_32();var json_length:=src.get_32()
	if original_length!=src.get_length() or src.get_32()!=0x4e4f534a:src.close();return ERR_FILE_CORRUPT
	var parsed:Variant=JSON.parse_string(src.get_buffer(json_length).get_string_from_utf8())
	if not parsed is Dictionary:src.close();return ERR_PARSE_ERROR
	var doc:Dictionary=parsed
	if doc.has("extras") and not doc.extras is Dictionary:src.close();return ERR_INVALID_DATA
	var extras:Dictionary=doc.get("extras",{}).duplicate(true)
	extras["review_cache_invalidation_probe"]={"isolated_only":true,"source_changed":true,"unique_probe":str(Time.get_ticks_usec()),"padding":"unchanged mesh and image binary payload; checksum identity must invalidate cache".repeat(8)}
	doc.extras=extras
	var encoded:=JSON.stringify(doc,"",true,true).to_utf8_buffer()
	while encoded.size()%4!=0:encoded.append(32)
	# Force different length as well as different SHA: Footprint.candidate is
	# intentionally a cheap source-size identity check, not a full SHA reader.
	if encoded.size()==json_length:encoded.append_array(PackedByteArray([32,32,32,32]))
	var dst:=FileAccess.open(output,FileAccess.WRITE)
	if dst==null:src.close();return FileAccess.get_open_error()
	dst.store_32(0x46546c67);dst.store_32(2);dst.store_32(original_length-json_length+encoded.size());dst.store_32(encoded.size());dst.store_32(0x4e4f534a);dst.store_buffer(encoded)
	while src.get_position()<src.get_length():dst.store_buffer(src.get_buffer(mini(1024*1024,src.get_length()-src.get_position())))
	dst.flush();var error:=dst.get_error();dst.close();src.close();return error
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=").replace("\\","/").simplify_path()
	var allowed:=report_path.to_lower().begins_with("d:/code/rmmo/review_artifacts/town_asset_size_audit_20261011/") or report_path.to_lower().begins_with("d:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011/")
	if not allowed or report_path.get_file() not in ["baseline.json","candidate.json"]:push_error("Expected an isolated completed baseline/candidate report");quit(2);return
	var review:=read_json(report_path)
	if not check(review.get("passed",false),"completed passing review required"):save();return
	var native:Dictionary=review.get("native",{});var root_path:String=native.get("content_root","");var local:String=native.get("source","");var original:String=review.get("original","");var source_sha:String=review.get("original_sha","")
	var expected_root:=report_path.get_base_dir().path_join(str(review.get("case_name",""))).path_join("isolated_content")
	if not check(root_path==expected_root and local==root_path.path_join("assets/review.glb") and Paths.allowed(local,root_path) and local!=original,"exact isolated source path and root"):save();return
	result.source=local;result.original=original;result.source_sha=source_sha
	if not check(FileAccess.get_sha256(original)==source_sha and FileAccess.get_sha256(local)==source_sha,"original and isolated source start identical"):save();return
	var manifest:=read_json(Compiled.index_path(local,root_path))
	var envelope:=read_json(Footprint.descriptor_path(local,root_path))
	var descriptor:Variant=JSON.parse_string(str(envelope.get("body","{}")))
	result.preflight={"engine":Engine.get_version_info(),"renderer_setting":ProjectSettings.get_setting("rendering/renderer/rendering_method",""),"current_compiled_generator":Compiled.generator(),"manifest_compiled_generator":manifest.get("generator",""),"current_footprint_generator":Footprint.generator(),"descriptor_footprint_generator":descriptor.get("footprint_generator","") if descriptor is Dictionary else "","isolated_source_sha":source_sha,"mutation_started":false}
	if result.preflight.current_compiled_generator!=result.preflight.manifest_compiled_generator or result.preflight.current_footprint_generator!=result.preflight.descriptor_footprint_generator:
		result.status="deferred"
		result.reason="The completed isolated review predates the current cache/footprint generator. Rebuild isolated products under a stable runtime revision; do not relabel old manifests or infer an asset failure. No source mutation attempted."
		result.isolated_restored=true
		save();return
	var frozen:Dictionary=Footprint.candidate(local,root_path,source_sha)
	if not check(not frozen.is_empty(),"pre-mutation footprint candidate exists"):save();return
	var initial:Dictionary=Compiled.read(local,source_sha,root_path)
	if not check(initial.get("hit",false),"pre-mutation compiled read succeeds"):initial.clear();save();return
	initial.clear();RenderingServer.force_sync()
	var scratch:=local+".invalidation.tmp.glb"
	if not check(mutated_copy(original,scratch)==OK,"write valid JSON-extras-only mutation with untouched BIN"):save();return
	if not check(DirAccess.copy_absolute(scratch,local)==OK,"replace only isolated source copy"):
		# Even a failed copy may have truncated its destination.
		result.isolated_restored=DirAccess.copy_absolute(original,local)==OK and FileAccess.get_sha256(local)==source_sha
		check(result.isolated_restored,"restore isolated source after failed replacement")
		DirAccess.remove_absolute(scratch);save();return
	result.preflight.mutation_started=true
	var changed_sha:=FileAccess.get_sha256(local);result.mutated_sha=changed_sha
	check(changed_sha!=source_sha,"mutated source has a new SHA")
	var cache:Dictionary=Compiled.read(local,source_sha,root_path)
	check(not cache.get("hit",false),"old Compiled.read rejects changed source");result.compiled_miss_reason=cache.get("reason","");cache.clear()
	var stale:Dictionary=Footprint.candidate(local,root_path,source_sha)
	check(stale.is_empty(),"old Footprint.candidate rejects changed source length")
	var preparation:Dictionary=Preparation.read(local,frozen,root_path)
	check(preparation.get("error",OK)!=OK and preparation.get("native_source_retry",false),"frozen Preparation.read rejects final source SHA and requests fresh admission")
	result.preparation={"error":preparation.get("error"),"reason":preparation.get("cache_reason",""),"native_source_retry":preparation.get("native_source_retry",false)}
	preparation.clear();RenderingServer.force_sync()
	# Always restore after mutation, including when an expected rejection failed.
	var restored:=DirAccess.copy_absolute(original,local)==OK
	check(restored and FileAccess.get_sha256(local)==source_sha,"restore isolated copy byte-for-byte")
	if FileAccess.file_exists(scratch):DirAccess.remove_absolute(scratch)
	if restored:
		var recovered:Dictionary=Compiled.read(local,source_sha,root_path);check(recovered.get("hit",false),"compiled read succeeds after restoration");recovered.clear()
		var recovered_footprint:Dictionary=Footprint.candidate(local,root_path,source_sha);check(not recovered_footprint.is_empty(),"footprint candidate recovers after restoration")
		var recovered_preparation:Dictionary=Preparation.read(local,frozen,root_path);check(recovered_preparation.get("error",FAILED)==OK and not recovered_preparation.get("fallback_required",false),"frozen preparation succeeds after restoration");recovered_preparation.clear()
	check(FileAccess.get_sha256(original)==source_sha,"original immutable source unchanged")
	result.source=local;result.original=original;result.source_sha=source_sha;result.isolated_restored=FileAccess.get_sha256(local)==source_sha
	save()
