extends SceneTree
## Explicit one-time migration. Validation writes only isolated temporary maps;
## --apply requires the successful validation report and its source digests.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Pose=preload("res://scripts/world3d/pose_save.gd")
var report:Dictionary={"maps":[],"failures":0}
var output:String
var apply_mode:=false
var validation_path:=""

func _init()->void:call_deferred("run")
func persist()->void:
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
func inventory(base:String,found:Array)->void:
	var dir:=DirAccess.open(base)
	if dir==null:return
	for file:String in dir.get_files():
		if file.get_extension().to_lower()=="gltf" and Paths.allowed(base.path_join(file)):found.append(base.path_join(file))
	for folder:String in dir.get_directories():
		if folder.ends_with(".versions") or folder.ends_with(".resources") or folder.ends_with(".save-lock") or dir.is_link(folder):continue
		inventory(base.path_join(folder),found)
func fail(row:Dictionary,message:String)->void:
	row.error=message;report.failures+=1;print("MIGRATION_FAIL ",row.source," ",message);persist()
func equivalent(a:RefCounted,b:RefCounted)->bool:
	return b!=null and Pose.same(a.records,b.records) and Pose.same(a.map_meta,b.map_meta)
func run()->void:
	var arguments:=OS.get_cmdline_user_args()
	apply_mode=arguments.has("--apply")
	for argument:String in arguments:
		if argument.begins_with("--validated="):validation_path=argument.trim_prefix("--validated=")
	var review:=Paths.external_root().path_join("review_artifacts")
	DirAccess.make_dir_recursive_absolute(review)
	output=review.path_join("reference_map_migration_%s_20261007.json"%["applied" if apply_mode else "validation"])
	report.mode="apply" if apply_mode else "validate"
	var candidates:Array=[];var baselines:Dictionary={}
	if apply_mode:
		var checked:Variant=JSON.parse_string(FileAccess.get_file_as_string(validation_path))
		if not checked is Dictionary or checked.get("mode")!="validate" or checked.get("failures",1)!=0:
			print("MIGRATION_FAIL requires successful --validated report");quit(1);return
		for row:Dictionary in checked.maps:
			if row.get("already_current",false):continue
			if not row.get("verified",false):print("MIGRATION_FAIL incomplete validation");quit(1);return
			candidates.append(row.source);baselines[row.source]=row.sha256_before
	else:
		inventory(Paths.external_root().path_join("maps"),candidates)
		var packs:=DirAccess.open(Paths.external_root().path_join("packs"))
		if packs!=null:
			for pack:String in packs.get_directories():
				if not packs.is_link(pack):inventory(Paths.external_root().path_join("packs").path_join(pack).path_join("maps"),candidates)
		# These two generated maps are the default playable scene and warp target.
		for sample in ["p4_yard","p4_inn"]:
			var sample_path:=Paths.cache_directory(sample).path_join("map.gltf")
			if FileAccess.file_exists(sample_path):candidates.append(sample_path)
	candidates.sort()
	var temporary:=Paths.cache_directory("reference_migration_%d"%Time.get_ticks_usec())
	for source:String in candidates:
		var row:Dictionary={"source":source,"sha256_before":FileAccess.get_sha256(source)}
		report.maps.append(row);persist()
		if apply_mode and row.sha256_before!=baselines[source]:fail(row,"Source changed since validation; revalidate before publishing");continue
		print("MIGRATION_OPEN ",source)
		var started:=Time.get_ticks_usec()
		var original:Variant=JSON.parse_string(FileAccess.get_file_as_string(source))
		var root_index:=Cursor.native_root(original,true)
		if root_index<0:fail(row,"Not an editable native map");continue
		row.version_before=original.nodes[root_index].extras.rmmo_version
		if int(row.version_before)==2:
			row.already_current=true;row.verified=Doc.open_file(source)!=null
			if not row.verified:fail(row,"Current reference map validation failed")
			continue
		row.bytes_before=FileAccess.get_file_as_bytes(source).size()
		var doc=Doc.open_file(source,{},Callable(),true)
		row.open_ms=(Time.get_ticks_usec()-started)/1000.0
		if doc==null:fail(row,"Legacy authoring validation failed");continue
		row.records=doc.records.size()
		var target:String=source if apply_mode else temporary.path_join(str(report.maps.size())).path_join("map.gltf")
		row.target=target
		if FileAccess.get_sha256(source)!=row.sha256_before:fail(row,"Source changed during validation");continue
		var err:Error=doc.save(target)
		row.save_metrics=doc.last_save_metrics.duplicate(true)
		if err!=OK:fail(row,"Reference save failed: "+str(err));continue
		started=Time.get_ticks_usec();var reopened=Doc.open_file(target)
		row.reopen_ms=(Time.get_ticks_usec()-started)/1000.0
		if not equivalent(doc,reopened):fail(row,"Reopened records or metadata differ");continue
		row.bytes_after=FileAccess.get_file_as_bytes(target).size()
		row.sha256_after=FileAccess.get_sha256(target)
		if apply_mode:
			row.previous_preserved=FileAccess.get_sha256(source+".previous")==row.sha256_before
			if not row.previous_preserved:fail(row,"Original migration checkpoint not retained");continue
		else:
			if FileAccess.get_sha256(source)!=row.sha256_before:fail(row,"Formal source changed");continue
			if not doc.records.is_empty():doc.records[0].position[0]+=0.123
			err=doc.save(target)
			row.move_save_metrics=doc.last_save_metrics.duplicate(true)
			if err!=OK or doc.last_save_metrics.export.resources_written!=0:fail(row,"Position-only save rewrote resource definitions");continue
			if not equivalent(doc,Doc.open_file(target)):fail(row,"Moved map failed roundtrip");continue
		row.verified=true;persist()
		print("MIGRATION_PASS ",source," records=",row.records," bytes=",row.bytes_before," -> ",row.bytes_after," save_ms=",row.save_metrics.total_ms)
		await process_frame
	persist();print("REFERENCE_MIGRATION_FINISHED mode=",report.mode," maps=",report.maps.size()," failures=",report.failures," report=",output)
	quit(0 if report.failures==0 else 1)
