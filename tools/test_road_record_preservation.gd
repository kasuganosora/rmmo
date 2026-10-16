extends SceneTree
## CPU-only correctness evidence, separate from strict prepare performance A/B.
## Uses native CPU reference save/read; full editor HTTP is covered by district_http.
const Roads=preload("res://scripts/world_editor/road_tools.gd")
const Fixture=preload("res://tools/road_prepare_fixture.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const ReferenceSave=preload("res://scripts/world3d/reference_map_save.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const ReferencePath="res://review_artifacts/road_prepare_20261016/reference.gd.txt"
const ReferenceSHA="061c4df3a456ff9ae0d0a950d18d8380dee438f725559af5ec27d9a69caa41eb"
var failures:=0
var checks:Array=[]
var report:Dictionary={"scope":"CPU native reference save/read and real shared road_tools.prepare/generate. Intentional record representation and diff correction; not an all-results-identical performance claim."}
var report_path:="res://review_artifacts/road_prepare_20261016/record_preservation.json"

class Controls:
	extends RefCounted
	func guard()->Dictionary:return {"ok":true}
	func refresh()->void:pass
	func invalidate_pivot()->void:pass

class Context:
	extends Fixture.Context
	var _city=Controls.new()
	var _selection_tools=Controls.new()
	var _object_list=Controls.new()
	var refreshed:Array=[]
	var _dirty:bool:
		get:return _doc.editor_dirty
		set(value):_doc.editor_dirty=value
	func _refresh_records(ids:Array)->void:refreshed=ids.duplicate()
	func _refresh_selection(_expand:bool)->void:pass

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->void:
	checks.append({"ok":ok,"label":label})
	print(("PASS " if ok else "FAIL ")+label)
	if not ok:failures+=1

func sha(value:Variant)->String:
	var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(value));return hashing.finish().hex_encode()

func context(source:Dictionary)->Context:
	var value:=Context.new();value._doc.records=source.records.duplicate(true)
	value._doc.map_meta=source.map_meta.duplicate(true);return value

func reversed_keys(value:Variant)->Variant:
	if value is Dictionary:
		var result:Dictionary={};var keys:Array=value.keys();keys.reverse()
		for key:Variant in keys:result[key]=reversed_keys(value[key])
		return result
	if value is Array:
		var result:Array=[]
		for item:Variant in value:result.append(reversed_keys(item))
		return result
	return value

func state(value:Context)->String:
	return sha([Fixture.state(value),value.refreshed])

func differences(left:Variant,right:Variant,path:String="")->Array:
	var result:Array=[]
	if left is Dictionary and right is Dictionary:
		for key:Variant in left:
			if right.has(key):result.append_array(differences(left[key],right[key],path+"."+str(key)))
			else:result.append({"path":path+"."+str(key),"missing":"right"})
		for key:Variant in right:
			if not left.has(key):result.append({"path":path+"."+str(key),"missing":"left"})
	elif left is Array and right is Array and left.size()==right.size():
		for i in left.size():result.append_array(differences(left[i],right[i],path+"[%d]"%i))
	elif not Roads._same(left,right):
		result.append({"path":path,"left":left,"right":right,"left_type":typeof(left),"right_type":typeof(right),"left_precise":"%.17f"%left if left is float else str(left),"right_precise":"%.17f"%right if right is float else str(right)})
	return result

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	var folder:=ProjectSettings.globalize_path("res://review_artifacts/road_prepare_20261016/").replace("\\","/").simplify_path().trim_suffix("/")+"/"
	if not ProjectSettings.globalize_path(report_path).replace("\\","/").simplify_path().begins_with(folder):push_error("Report must stay in this worktree's road preparation evidence directory");quit(2);return
	check(FileAccess.get_sha256(ReferencePath)==ReferenceSHA,"frozen original road_tools source SHA is exact")
	var reference:=GDScript.new();reference.source_code=FileAccess.get_file_as_string(ReferencePath)
	check(reference.reload()==OK,"frozen original source parses for independent correctness comparison")
	check(Roads._same({"rotation":[0,0,0],"nested":{"x":1}}, {"nested":{"x":1.0},"rotation":[0.0,0.0,0.0]}),"equal nested numbers and dictionary order are semantically identical")
	check(not Roads._same({"x":1.0},{"x":1.0+1e-12}),"a real 1e-12 numeric difference is never swallowed")
	check(not Roads._same({"x":0},{"x":false}) and not Roads._same({"x":1},{"x":"1"}) and not Roads._same({"x":null},{}),"bool, string and missing fields remain distinct")
	check(not Roads._same([1,2],[2,1]) and not Roads._same([1],{"0":1}),"array order and container types remain distinct")
	check(Roads._same(9007199254740993,9007199254740993) and not Roads._same(9007199254740993,9007199254740992.0),"same-type integers remain exact and unsafe int-to-double rounding cannot merge changes")
	check(Roads._same(9007199254740992,9007199254740992.0) and not Roads._same(0,INF),"safe cross-type integers compare exactly and nonfinite conversion is refused")
	var fixture:=Fixture.make("json_records",[Fixture.box("ground",[50.,-.25,40.],[240.,.5,180.])],Fixture.graph([[[-12.,0.,0.],[12.,0.,0.]],[[80.,0.,80.],[112.,0.,80.]]],4.0))
	var initial:=context({"records":fixture.records,"map_meta":{"editor_layout":fixture.layout}})
	var tools:=Roads.new();tools.editor=initial
	var generated:Dictionary=tools.prepare({});check(generated.get("ok",false),"native unpainted near/far roads prepare in a CPU-only context")
	if not generated.get("ok",false):initial.free();await finish();return
	initial._doc.records.append_array(generated.records)
	initial._doc.map_meta.editor_layout.roads=generated.graph
	initial._doc.map_meta.editor_layout.road_surface=generated.manifest
	var original:Dictionary={"records":initial._doc.records.duplicate(true),"map_meta":initial._doc.map_meta.duplicate(true)}
	# Real native saves keep geometry in immutable binary definitions; only
	# the compact pose/state and metadata travel through JSON. Serializing the
	# whole road_mesh as JSON instead would introduce unrelated one-ULP drift.
	var map_path:=Paths.cache_directory("road_record_preservation_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]).path_join("map.gltf")
	var saved:=ReferenceSave.save(map_path,null,original.records,original.map_meta,Paths.external_root(),Io)
	check(saved.error==OK,"native CPU reference writer saves a unique temporary map")
	if saved.error!=OK:initial.free();await finish();return
	var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(map_path))
	var extras:Dictionary=document.nodes[0].extras
	var decoded:=Store.read_records(extras.rmmo_records,map_path,Paths.external_root(),extras.rmmo_resource_dependencies)
	check(decoded.get("ok",false),"native resource reader restores verified binary definitions and JSON poses")
	if not decoded.get("ok",false):initial.free();await finish();return
	var metadata:Dictionary=extras.duplicate(true)
	for key:Variant in metadata.keys():
		if str(key).begins_with("rmmo_"):metadata.erase(key)
	var restored:Dictionary={"records":decoded.records,"map_meta":metadata}
	report.fixture={"path":map_path,"sha256":FileAccess.get_sha256(map_path),"save_mode":saved.mode,"writer":"reference_map_save","reader":"map_resource_store.read_records"}
	# Keep a deliberately lossy whole-record JSON control separate: those
	# geometric changes must be treated as real, not hidden by this fix.
	var lossy_context:=context(JSON.parse_string(JSON.stringify(original)))
	var lossy_tool:=Roads.new();lossy_tool.editor=lossy_context
	var lossy:Dictionary=lossy_tool.prepare({})
	check(lossy.get("ok",false) and lossy.diff.updated>0,"whole-record lossy JSON geometry remains a real change and is never reused")
	report.lossy_json_control={"diff":lossy.get("diff",{}),"scope":"Deliberately serializes binary geometry as default-precision JSON; not the native persistence path."}
	lossy_context.free()
	# Reordering represents legal parsed author dictionaries and must not be
	# discarded just because the generator inserts equivalent keys differently.
	for i in restored.records.size():
		if restored.records[i].has("road_mesh"):restored.records[i]=reversed_keys(restored.records[i])
	var source:=context(restored);var candidate:=Roads.new();candidate.editor=source
	var old_context:=context(restored);var old_tools=reference.new();old_tools.editor=old_context
	var before:=state(source);var old_before:=state(old_context)
	var previous_result:Dictionary=old_tools.prepare({})
	var result:Dictionary=candidate.prepare({})
	check(previous_result.get("ok",false) and result.get("ok",false),"original and corrected prepare accept the same reloaded authored map")
	check(state(source)==before and state(old_context)==old_before,"both prepare implementations leave source document and history untouched")
	check(result.diff.updated==0 and result.diff.unchanged==result.records.size(),"corrected diff counts semantically unchanged reloaded records accurately")
	check(previous_result.diff.updated>0,"frozen original reproduces spurious updates after JSON reload")
	var preserved:=true;var changed_by_old:=false;var identity_rows:Array=[]
	for record:Dictionary in result.records:
		var prior:Dictionary=source._doc._find(record.uuid)
		var old_record:Dictionary=previous_result.records.filter(func(row):return row.uuid==record.uuid)[0]
		preserved=preserved and var_to_bytes(record)==var_to_bytes(prior)
		changed_by_old=changed_by_old or var_to_bytes(old_record)!=var_to_bytes(prior)
		var real_differences:=differences(prior,record)
		if not real_differences.is_empty():print("EXACT_RECORD_DIFFERENCES ",JSON.stringify(real_differences))
		identity_rows.append({"id":record.uuid,"author_sha256":sha(prior),"corrected_sha256":sha(record),"original_sha256":sha(old_record),"author_rotation_type":typeof(prior.rotation[0]),"original_rotation_type":typeof(old_record.rotation[0]),"real_value_differences":real_differences})
	check(preserved and changed_by_old,"corrected candidates retain exact author bytes while original candidates replace representation")
	check(var_to_bytes(result.manifest)==var_to_bytes(previous_result.manifest) and result.plan_token==previous_result.plan_token,"manifest and plan-token definitions remain byte-identical to original prepare")
	var detached:Dictionary=result.records[0]
	detached.rotation[0]=17.0
	check(state(source)==before,"retained candidate is a deep copy and cannot mutate the live document")
	# The direct repeat after JSON reload must not require a preceding edit.
	var no_op:Dictionary=candidate.generate({})
	check(no_op.get("ok",false) and not no_op.get("changed",true) and state(source)==before,"direct repeated generate after JSON reload is a no-op with no history or refresh")
	var original_repeat:Dictionary=old_tools.generate({})
	check(original_repeat.get("changed",false) and old_context._doc._undo.size()==1,"original implementation reproduces unnecessary repeated-generate history")
	# Change only one road in the graph; the distant component must retain bytes.
	var changed_layout:Dictionary=source._doc.map_meta.editor_layout.duplicate(true)
	changed_layout.roads.nodes[1].position[0]=14.0
	var local:Dictionary=candidate.prepare({},changed_layout)
	check(local.get("ok",false) and local.diff.updated>0 and local.diff.unchanged>0,"a genuine local endpoint change remains an update beside unchanged far roads")
	var far_ok:=true;var far_count:=0
	if local.get("ok",false):
		for record:Dictionary in local.records:
			if float(record.position[2])>64.0:
				far_count+=1;far_ok=far_ok and var_to_bytes(record)==var_to_bytes(source._doc._find(record.uuid))
	check(far_count>0 and far_ok,"legal local preparation preserves every distant authored road byte")
	# clearance participates in the complete record, but not polygon rounding.
	var precise:Dictionary=candidate.prepare({"clearance":3.0+1e-10})
	check(precise.get("ok",false) and precise.diff.updated==precise.records.size() and precise.diff.unchanged==0,"a real 1e-10 authored clearance change updates every affected record")
	report.merge({"reference_sha256":ReferenceSHA,"current_sha256":FileAccess.get_sha256("res://scripts/world_editor/road_tools.gd"),"test_sha256":FileAccess.get_sha256("res://tools/test_road_record_preservation.gd"),"original_diff":previous_result.diff,"corrected_diff":result.diff,"local_diff":local.get("diff",{}),"exact_change_diff":precise.get("diff",{}),"record_evidence":identity_rows,"original_repeat":original_repeat,"corrected_repeat":no_op,"prepare_manifest_sha256":sha(result.manifest),"engine":Engine.get_version_info()},true)
	initial.free();source.free();old_context.free()
	await finish()

func finish()->void:
	report.failures=failures;report.checks=checks
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("ROAD_RECORD_PRESERVATION checks=%d failures=%d report=%s"%[checks.size(),failures,report_path])
	quit(0 if failures==0 else 1)
