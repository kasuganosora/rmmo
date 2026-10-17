extends SceneTree
const Native=preload("res://scripts/world_editor/surface_material_library.gd")
const Original=preload("res://review_artifacts/material_targeted_20261017/surface_material_library_baseline.gd")
const Current=preload("res://review_artifacts/material_targeted_20261017/library_current_profile.gd")
const Baseline=preload("res://review_artifacts/material_targeted_20261017/library_baseline_profile.gd")
const Evidence="D:/code/rmmo_runtime/review_artifacts/material_targeted_20261017/"
var checks:Array=[]
var samples:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	checks.append({"ok":ok,"label":label_});print("PASS " if ok else "FAIL ",label_)
func sample(name_:String,ids:Array,folder:String="")->void:
	var now:=Current.new(folder);var old:=Baseline.new(folder)
	var native:=Native.new(folder);var original:=Original.new(folder)
	Current.descriptors_read=0;Baseline.descriptors_read=0
	var actual:=now.find_many(ids);var expected:=old.find_many(ids)
	check(var_to_bytes(actual)==var_to_bytes(expected),name_+" baseline/current bytes identical")
	check(var_to_bytes(actual)==var_to_bytes(native.find_many(ids)) and var_to_bytes(expected)==var_to_bytes(original.find_many(ids)),name_+" instrumentation preserves exact native outputs")
	var state:=native._lookup_candidates(ids,preload("res://scripts/world3d/map_paths.gd").external_root())
	samples.append({"name":name_,"ids":ids,"baseline_reads":Baseline.descriptors_read,"current_reads":Current.descriptors_read,"candidate_scan":state})
	if state.complete:
		check(Current.descriptors_read<=state.paths.size(),name_+" parses only selected candidate descriptors")
	else:
		check(Current.descriptors_read==Baseline.descriptors_read,name_+" fallback reads original full catalog")
func run()->void:
	var pavement:="pack:default:paving/historic_cobble/material"
	var kerb:="pack:default:paving/automatic_limestone_kerb/material"
	sample("real_shared_dual",[pavement,kerb])
	sample("real_shared_single",[pavement])
	sample("builtin",["builtin:white"])
	sample("missing",["not-a-material"])
	var manager:=root.get_node("AssetManager");var previous:String=manager.content_root_override
	var fixture:String=JSON.parse_string(FileAccess.get_file_as_string(Evidence+"targeted_tests.json")).fixture
	manager.content_root_override=fixture
	sample("cap_fallback",["2045","later/hidden"],fixture.path_join("cap"))
	sample("wide_fallback",["d256/valid"],fixture.path_join("wide"))
	manager.content_root_override=previous
	var failures:=checks.filter(func(c):return not c.ok).size()
	var file:=FileAccess.open(Evidence+"work_counts.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"samples":samples,"checks":checks,"failures":failures},"\t"));file.close()
	print("MATERIAL_TARGETED_COUNTS checks=",checks.size()," failures=",failures);quit(1 if failures else 0)
