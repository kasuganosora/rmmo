extends SceneTree
const LoadJob=preload("res://scripts/world_editor/load_job.gd")

# Exercise the same decision method used by initial planning and cache retry;
# keep the real caller's branch selection and return contracts intact.
class CountingJob extends LoadJob:
	var native_calls:=0
	var candidate:Dictionary={}
	func _native_model_candidate(_path:String,_root:String)->Dictionary:
		native_calls+=1
		return candidate.duplicate()

var passed:=0
var failures:=0
func check(condition:bool,message:String)->void:
	if condition:passed+=1;print("PASS: ",message)
	else:failures+=1;printerr("FAIL: ",message)

func _initialize()->void:run.call_deferred()

func run()->void:
	var old:bool=LoadJob.native_model_footprints_enabled
	var job:=CountingJob.new()
	LoadJob.native_model_footprints_enabled=true
	job.candidate={"estimated_bytes":800,"exclusive":true,"source_sha":"a".repeat(64)}
	var native:Dictionary=job._asset_load_estimate("model.glb","root")
	check(job.native_calls==1 and not native.raw_computed,"eligible native plan never reads raw estimator")
	check(native.candidate==job.candidate and not native.raw_computed,"native plan preserves exact candidate and records omitted raw estimate")
	job.native_calls=0;job.candidate={}
	var missing:Dictionary=job._asset_load_estimate("model.glb","root")
	check(job.native_calls==1 and not missing.raw_computed and missing.estimate.is_empty(),"missing native product never enters raw import")
	job.native_calls=0;job.candidate={"estimated_bytes":800,"exclusive":true,"source_sha":"b".repeat(64)}
	LoadJob.native_model_footprints_enabled=false
	var legacy:Dictionary=job._asset_load_estimate("model.glb","root")
	check(job.native_calls==1 and not legacy.raw_computed,"legacy diagnostic switch cannot re-enable raw import")
	check(legacy.estimate.estimated_bytes==800 and legacy.estimate.exclusive,"native-only route retains exact native admission")
	# Exercise the real first-lookahead caller and queue with a small private
	# placeholder, while the candidate seam prevents any real native load.
	var source:=preload("res://scripts/world3d/map_paths.gd").external_root().path_join("cache/world3d/missing_estimate_fixture.glb")
	root.add_child(job)
	job.native_calls=0;job.candidate={"estimated_bytes":800,"exclusive":true,"source_sha":"c".repeat(64)}
	job._begin_asset_lookahead([{"kind":"asset","asset_path":source},{"kind":"asset","asset_path":source}])
	var planned:Dictionary=job._timings.asset_lookahead
	var key:="model:"+source;var actual:Dictionary=job._preparation.rows.get(key,{})
	check(job.native_calls==1 and job._asset_paths.size()==1 and not FileAccess.file_exists(source),"actual first-lookahead deduplicates native path without GLB")
	check(actual.get("estimate",{}).get("estimated_bytes")==800 and actual.get("estimate",{}).get("exclusive")==true and actual.get("estimate",{}).get("stage")=="compiled_read","actual queue retains fixed-native admission")
	check(planned.planned_model_reservation_bytes==800 and planned.legacy_model_reservation_bytes==null and planned.legacy_model_known_reservation_bytes==0 and planned.legacy_estimate_skipped_paths==1,"lookahead reports actual reservation and unknown legacy total")
	var ledger:RefCounted=job._preparation.ledger
	job._clear_asset_lookahead()
	for i:int in 60:
		if ledger.reserved_bytes==0:break
		await process_frame
	check(ledger.reserved_bytes==0,"cancelled first-lookahead candidate releases its reservation")
	LoadJob.native_model_footprints_enabled=old
	job.free()
	print("EDITOR_NATIVE_ESTIMATE_PLAN passed=",passed," failures=",failures)
	quit(1 if failures else 0)
