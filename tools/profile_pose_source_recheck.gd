extends SceneTree
## Read-only comparison on the frozen town. Does not install or resign a baseline.
const Pose=preload("res://scripts/world3d/pose_save.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const SOURCE="D:/code/rmmo_runtime/cache/world3d/bridge_perf_20261006/map.gltf"
const OUTPUT="D:/code/rmmo_runtime/review_artifacts/pose_source_recheck_town_20261007.json"
func _initialize()->void:run.call_deferred()
func run()->void:
	var before:=FileAccess.get_sha256(SOURCE)
	var data:=Pose._json(SOURCE)
	var root_index:=Pose._root(data)
	if before.is_empty() or root_index<0:quit(1);return
	var records:Array=data.nodes[root_index].extras.rmmo_records
	var baseline:=Pose.source_files(records,Paths.external_root(),Io)
	if not baseline.ok:quit(1);return
	var report:={"source":SOURCE,"source_sha256":before,"records":records.size(),"files":baseline.files.size(),"samples":[],"all_checks_match":true}
	# ABBA with the same current-generation closure. The OS cache is not purged.
	for mode in ["rediscover","closed_set","closed_set","rediscover"]:
		var start:=Time.get_ticks_usec()
		var accepted:bool
		if mode=="rediscover":
			var current:=Pose.source_files(records,Paths.external_root(),Io)
			accepted=current.ok and current.generator==baseline.generator and Pose.same(current.files,baseline.files)
		else:accepted=Pose.verify_source_files(baseline,Paths.external_root())
		var row:={"mode":mode,"ms":(Time.get_ticks_usec()-start)/1000.0,"accepted":accepted}
		report.samples.append(row);report.all_checks_match=report.all_checks_match and accepted
		print("SOURCE_RECHECK_TOWN ",JSON.stringify(row))
	report.source_unchanged=FileAccess.get_sha256(SOURCE)==before
	var file:=FileAccess.open(OUTPUT,FileAccess.WRITE)
	if file==null:quit(1);return
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("SOURCE_RECHECK_TOWN_DONE ",JSON.stringify(report))
	quit(0 if report.all_checks_match and report.source_unchanged else 1)
