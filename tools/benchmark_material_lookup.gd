extends SceneTree
const Library=preload("res://scripts/world_editor/surface_material_library.gd")
const Current=preload("res://scripts/world_editor/road_tools.gd")
const Baseline=preload("res://review_artifacts/material_lookup_20261017/road_guarded_baseline.gd")
const Fixture=preload("res://tools/road_prepare_fixture.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Evidence="D:/code/rmmo_runtime/review_artifacts/material_lookup_20261017/"
var checks:Array=[]
var report:Dictionary={"samples":[],"resources":{},"sources":{}}
var context:Node3D
var args:Dictionary
var expected:PackedByteArray
var before:PackedByteArray
var old:RefCounted
var current:RefCounted
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	checks.append({"ok":ok,"label":label_})
	if not ok:print("FAIL ",label_)
func sample(version:String,label_:String,profile:bool=false)->void:
	var tool:RefCounted=old if version=="baseline" else current
	tool.profile_enabled=profile
	var start:=Time.get_ticks_usec();var result:Dictionary=tool.prepare(args);var elapsed:=Time.get_ticks_usec()-start
	var bytes:=var_to_bytes(result)
	if expected.is_empty():expected=bytes
	check(result.ok and bytes==expected,label_+" exact complete successful result")
	check(before==var_to_bytes([Fixture.state(context),args]),label_+" no input/history mutation")
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	report.samples.append({"version":version,"label":label_,"request":args.duplicate(true),"result_sha256":hash.finish().hex_encode(),"prepare_ms":elapsed/1000.,"profile_enabled":profile,"profile":tool.last_profile.duplicate(true)})
func run()->void:
	DirAccess.make_dir_recursive_absolute(Evidence)
	var library:=Library.new()
	var ids:=["pack:default:paving/historic_cobble/material","pack:default:paving/automatic_limestone_kerb/material"]
	for id:String in ids:
		var value:=library.find(id);check(not value.is_empty(),"real shared PBR exists "+id)
		for field:String in Paint.MAP_FIELDS:
			if value.has(field):report.resources[value[field]]=FileAccess.get_sha256(value[field])
	var fixture:=Fixture.local_terrain();context=Fixture.context(fixture);context._material_tool.library=library
	old=Baseline.new();old.editor=context;current=Current.new();current.editor=context
	for mode:String in ["dual","single","plain"]:
		args=fixture.args.duplicate(true)
		args.material_id="" if mode=="plain" else ids[0]
		if mode=="dual":args.kerb_enabled=true;args.kerb_material_id=ids[1]
		expected=PackedByteArray();before=var_to_bytes([Fixture.state(context),args])
		for warmup in 2:
			for version:String in ["baseline","current"]:sample(version,mode+"_warmup_"+str(warmup))
		for i in 4:
			sample("baseline",mode+"_AA_%d_first"%i);sample("baseline",mode+"_AA_%d_second"%i)
		for i in 12:
			for version:String in (["baseline","current"] if i%2==0 else ["current","baseline"]):sample(version,mode+"_AB_%d"%i)
		for version:String in ["baseline","current"]:sample(version,mode+"_ON",true)
		print("MATERIAL_LOOKUP_CPU_COMPLETED ",mode)
	for path:String in report.resources:check(FileAccess.get_sha256(path)==report.resources[path],"actual texture dependency unchanged "+path)
	for path:String in ["res://tools/benchmark_material_lookup.gd","res://scripts/world_editor/surface_material_library.gd","res://scripts/world_editor/road_tools.gd","res://review_artifacts/material_lookup_20261017/road_guarded_baseline.gd","res://tools/road_prepare_fixture.gd"]:report.sources[path]=FileAccess.get_sha256(path)
	report.engine=Engine.get_version_info();report.engine_executable_sha256=FileAccess.get_sha256(OS.get_executable_path())
	report.method="Serial dual/single/plain terrain preparation; 2 warmups/version, 4 A/A pairs, 12 alternating A/B pairs, final ON per version. Identical full bytes and authored state each call; real shared PBR. Other user/session load uncontrolled; no cold/tail/significance claim. Control regression tolerance 10% or A/A variation."
	report.checks=checks;report.failures=checks.filter(func(c):return not c.ok).size()
	var file:=FileAccess.open(Evidence+"cpu.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	old.editor=null;current.editor=null;context._waterways.editor=null;context.free()
	print("MATERIAL_LOOKUP_CPU checks=",checks.size()," failures=",report.failures);quit(1 if report.failures else 0)
