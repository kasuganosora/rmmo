extends SceneTree
## Publish reviewed derived kerbs while rejecting every unrelated scene edit.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Roads=preload("res://scripts/world_editor/road_tools.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var output:=""
var report:Dictionary={"published":false,"checks":[]}
var failures:=0
func check(ok:bool,label:String)->bool:
	report.checks.append({"name":label,"passed":ok})
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label);return ok
func read(path:String)->Dictionary:
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}
func finish()->void:
	report.failures=failures
	var f:=FileAccess.open(output+".pending",FileAccess.WRITE)
	if f==null:quit(1);return
	f.store_string(JSON.stringify(report,"  "));f.close()
	if Atomic.publish(output+".pending",output)!=OK:failures+=1
	quit(0 if failures==0 else 1)
func _initialize()->void:
	var review_path:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--review="):review_path=arg.trim_prefix("--review=")
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	if not Paths.allowed(review_path) or not Paths.allowed(output) or FileAccess.file_exists(output):quit(1);return
	var review:=read(review_path)
	if not check(review.get("accepted",false),"explicit scoped road visual acceptance"):finish();return
	var source:=str(review.source);var candidate:=str(review.candidate)
	check(Paths.allowed(source) and Paths.allowed(candidate) and source!=candidate,"external native map paths")
	for name:String in ["authoring","runtime","geometry","shared_geometry"]:
		check(FileAccess.get_sha256(review[name+"_path"])==review[name+"_sha256"],"exact "+name+" evidence")
	var authored:=read(review.authoring_path);var runtime:=read(review.runtime_path)
	var shared:=read(review.shared_geometry_path)
	var geometry:=read(review.geometry_path)
	check(geometry.get("passed",false) and geometry.get("candidate_sha256","")==review.candidate_sha256,"exact geometry audit passed")
	check(authored.get("saved",false) and authored.get("failures",-1)==0,"native authoring passed")
	check(runtime.get("status","")=="passed" and runtime.get("failures",-1)==0,"outdoor runtime passed")
	check(shared.get("identical",false) and shared.get("map_sha256","")==review.candidate_sha256,"editor and runtime mesh arrays identical")
	check(FileAccess.get_sha256(source)==review.source_sha256,"formal source conflict check")
	check(FileAccess.get_sha256(candidate)==review.candidate_sha256 and runtime.get("map_sha256","")==review.candidate_sha256 and authored.get("target_sha256","")==review.candidate_sha256,"same authored and reviewed candidate")
	check(not review.get("viewed_images",[]).is_empty(),"images actually reviewed")
	for image:Dictionary in review.get("viewed_images",[]):
		check(FileAccess.get_sha256(image.path)==image.sha256 and image.quality==90 and image.lossless==false,"exact Q90 image "+str(image.id))
	if failures:finish();return
	var formal=Doc.open_file(source);var staged=Doc.open_file(candidate)
	if not check(formal!=null and staged!=null,"native source and candidate open"):finish();return
	check(staged.validate_save()==OK,"native candidate validates")
	check(formal.records.size()==staged.records.size(),"record count unchanged")
	var changed:Array=[];var unexpected:Array=[]
	for row:Dictionary in formal.records:
		var current:Dictionary=staged._find(row.uuid)
		if Roads._same(row,current):continue
		changed.append(row.uuid)
		if not row.has("road_mesh") or not current.has("road_mesh"):unexpected.append(row.uuid);continue
		var a:=row.duplicate(true);var b:=current.duplicate(true)
		a.road_mesh.erase("kerbs");b.road_mesh.erase("kerbs")
		if not Roads._same(a,b):unexpected.append(row.uuid)
	check(not changed.is_empty() and unexpected.is_empty(),"only derived road kerbs change; all placements and materials preserved")
	report.changed_ids=changed;report.unexpected=unexpected
	var old_meta:Dictionary=formal.map_meta.duplicate(true);var new_meta:Dictionary=staged.map_meta.duplicate(true)
	old_meta.editor_layout.erase("road_surface");new_meta.editor_layout.erase("road_surface")
	check(Roads._same(old_meta,new_meta),"authored road graph and all other metadata preserved")
	if failures:finish();return
	var before:Dictionary=formal.recovery_snapshot()
	formal.apply_recovery(staged.recovery_snapshot());formal.commit_recovery_change(before)
	if not check(formal.save(source)==OK,"native formal atomic save with conflict detection"):finish();return
	var reopened=Doc.open_file(source)
	check(reopened!=null and reopened.validate_save()==OK and Roads._same(reopened.records,staged.records) and Roads._same(reopened.map_meta,staged.map_meta),"formal map reopens with exact reviewed content")
	report.published=failures==0;report.source=source;report.before_sha256=review.source_sha256
	report.after_sha256=FileAccess.get_sha256(source);report.review_path=review_path;report.review_sha256=FileAccess.get_sha256(review_path)
	finish()
