extends "res://tools/test_road_prepare_differential.gd"
## Baseline after main merge; compare every author byte and failure witness.
const Baseline=preload("res://review_artifacts/road_projection_20261017/road_tools_ref.gd")
const BaselineFit=preload("res://review_artifacts/road_projection_20261017/terrain_projection_ref.gd")
const BaselineAdaptive=preload("res://review_artifacts/road_projection_20261017/road_terrain_fit_ref.gd")
const Probed=preload("res://review_artifacts/road_projection_20261017/road_tools_profile.gd")
const Probe=preload("res://review_artifacts/road_projection_20261017/terrain_projection_profile.gd")
const ARCHIVE="res://review_artifacts/road_projection_20261017/"
const EVIDENCE="D:/code/rmmo_runtime/review_artifacts/road_projection_20261017/"
var diagnostic:=false

func initialize()->bool:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
		elif arg=="--diagnostic":diagnostic=true
		elif arg.begins_with("--case="):selected=arg.trim_prefix("--case=")
		else:check(false,"unknown argument",arg)
	if not ProjectSettings.globalize_path(report_path).replace("\\","/").simplify_path().begins_with(EVIDENCE):
		push_error("Report must be inside "+EVIDENCE);quit(2);return false
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ARCHIVE+"reference.json"))
	for filename:String in manifest.files:check(FileAccess.get_sha256(ARCHIVE+filename)==manifest.files[filename],"frozen baseline "+filename)
	var hashes:Dictionary={};source_hashes("res://scripts/world3d",hashes);source_hashes("res://scripts/world_editor",hashes)
	for path:String in ["res://tools/test_road_projection_reuse.gd","res://tools/benchmark_road_projection.gd","res://tools/road_prepare_fixture.gd","res://tools/test_road_prepare_differential.gd","res://project.godot"]:
		if FileAccess.file_exists(path):hashes[path]=FileAccess.get_sha256(path)
	report={"reference":manifest,"script_sha256":hashes,"engine":Engine.get_version_info(),"engine_executable_sha256":FileAccess.get_sha256(OS.get_executable_path()),"fixtures":[]}
	return failures==0

func fixture_names()->Array:
	return Fixture.names()+["terrain64_wavy","terrain64_kerbs","terrain64_far_kerbs","terrain64_existing"]

func build_fixture(name_:String)->Dictionary:
	if name_ in Fixture.names():return Fixture.build(name_)
	var fixture:=Fixture.local_terrain(name_=="terrain64_far_kerbs");fixture.name=name_
	if name_=="terrain64_wavy":
		for z in 65:
			for x in 65:fixture.records[0].terrain_mesh.heights[z*65+x]=.02*sin(x*.73)*cos(z*.61)+.005*sin(x*1.2+z*.4)
	elif name_.ends_with("kerbs"):fixture.args.merge({"kerb_enabled":true,"kerb_material_id":"builtin:white"},true)
	elif name_=="terrain64_existing":
		var context:=Fixture.context(fixture);var tool:=Baseline.new();tool.editor=context
		var result:Dictionary=tool.prepare(fixture.args)
		if result.ok:
			fixture.records.append_array(result.records.duplicate(true));fixture.layout.roads=result.graph.duplicate(true);fixture.layout.road_surface=result.manifest.duplicate(true)
		else:fixture.construction_error=str(result)
		tool.editor=null;context._waterways.editor=null;context.free()
	return fixture

func compare_context(name_:String,context:Node3D,args:Dictionary,current:RefCounted,_original:RefCounted,expected_ok:Variant=null,conflict:="")->Dictionary:
	var baseline:=Baseline.new();baseline.editor=context
	var result:=super.compare_context(name_,context,args,current,baseline,expected_ok,conflict)
	baseline.editor=null;return result

func compare_record_order_correctness(fixture:Dictionary)->void:
	var result:=compare_prepare(fixture,true)
	var previous:Dictionary=fixture.records[-1]
	var matches:Array=result.get("records",[]).filter(func(record):return record.uuid==previous.uuid)
	check(matches.size()==1 and var_to_bytes(matches[0])==var_to_bytes(previous),"decorated author bytes retained")

func compare_projection(name_:String,record:Dictionary,terrains:Array,expected_ok:Variant=null,adaptive_limit:=-1)->void:
	var before:=var_to_bytes([record,terrains])
	var actual:Dictionary=Adaptive.fit([record],terrains,.025,adaptive_limit) if adaptive_limit>=0 else Projector.fit(record,terrains)
	var expected:Dictionary=BaselineAdaptive.fit([record],terrains,.025,adaptive_limit) if adaptive_limit>=0 else BaselineFit.fit(record,terrains)
	record_comparison(name_,actual,expected,[record,terrains,adaptive_limit],expected_ok)
	check(before==var_to_bytes([record,terrains]),name_+" inputs immutable")
	if actual.get("ok",false):
		var records:Array=actual.records if adaptive_limit>=0 else [actual.record]
		check(records.all(func(r):return Surface.valid(r)),name_+" native geometry valid")

func diagnose(fixture:Dictionary)->void:
	var context:=Fixture.context(fixture);var original:=Baseline.new();original.editor=context
	var tool:=Probed.new();tool.editor=context;tool.profile_enabled=true
	var before:=var_to_bytes([Fixture.state(context),fixture.args]);var expected:=var_to_bytes(original.prepare(fixture.args))
	var samples:Array=[]
	for i in 3:
		Probe.trace={};var result:Dictionary=tool.prepare(fixture.args)
		check(var_to_bytes(result)==expected,fixture.name+" diagnostic exact return")
		check(before==var_to_bytes([Fixture.state(context),fixture.args]),fixture.name+" diagnostic unchanged input")
		samples.append({"stages":tool.last_profile.duplicate(true),"projection":Probe.trace.duplicate(true)})
	report.fixtures.append({"name":fixture.name,"samples":samples,"input_sha256":bytes_sha(before),"result_sha256":bytes_sha(expected)})
	print("PROJECTION_PROFILE ",fixture.name," ",JSON.stringify(samples[-1]))
	original.editor=null;tool.editor=null;context._waterways.editor=null;context.free()

func reuse_matrix()->void:
	var settings:Dictionary=Plan.defaults().merged({"kerb_enabled":true,"kerb_material_id":"builtin:white"},true)
	var built:=Plan.build(Fixture.graph([[[-6.,0.,0.],[6.,0.,0.]]]),settings)
	check(built.ok,"native kerbs for reuse lifetime matrix")
	var tile:=Fixture.terrain("same_id",16)
	for state in 7:
		match state:
			1:
				for z in 17:
					for x in 17:tile.terrain_mesh.heights[z*17+x]=.02*sin(x*.7)*cos(z*.8)
			2:tile.position[1]=.04;tile.rotation[1]=17.
			3:tile.terrain_mesh.holes[8*16+8]=true
			4:tile.terrain_mesh.holes.fill(false);tile.rotation=[.00009,17.,0.]
			5:tile.rotation=[0.,0.,0.];tile.size[1]=2.
			6:tile=Fixture.terrain("same_id",16)
		for index in built.records.size():compare_projection("kerb_mutation_%d_%d"%[state,index],built.records[index],[tile])
	# Sparse/empty windows must remain lazy, and a second tile with an identical
	# UUID cannot alias a row/height result from the preceding terrain.
	tile.terrain_mesh.holes.fill(true);tile.terrain_mesh.holes[8*16+8]=false
	for index in built.records.size():
		compare_projection("sparse_holes_%d"%index,built.records[index],[tile],false)
		compare_projection("duplicate_id_overlap_%d"%index,built.records[index],[Fixture.terrain("same_id",16),Fixture.terrain("same_id",8)],false)
	# Source kerbs and fitted elevation records are both reused after a sculpt.
	var ground:=Fixture.terrain("refit",16)
	for index in built.records.size():
		var seed:Dictionary=BaselineFit.fit(built.records[index],[ground])
		check(seed.ok,"first native follower with kerbs")
		if seed.ok:
			ground.terrain_mesh.heights[8*17+8]=.04
			compare_projection("existing_kerb_follower_%d"%index,seed.record,[ground],true)
	var intricate:Dictionary=built.records[0].duplicate(true)
	var part:Dictionary=intricate.road_mesh.kerbs[0].duplicate(true)
	intricate.road_mesh.kerbs=[]
	var unique:Dictionary={}
	for i in 1800:
		var next:=part.duplicate(true)
		for side:String in ["a","b"]:
			for point:Array in next[side]:
				point[0]+=i*.00021
				unique[Vector3(point[0]+intricate.position[0],0,point[2]+intricate.position[2])]=true
		intricate.road_mesh.kerbs.append(next)
	check(unique.size()>Projector.KERB_SAMPLE_CACHE_LIMIT,"fixture exceeds the local kerb cache cap",unique.size())
	compare_projection("kerb_cache_limit_exact_fallback",intricate,[Fixture.terrain("cache_cap",16)],true)

func run()->void:
	report_path=EVIDENCE+"differential.json"
	if not initialize():finish();return
	if diagnostic:
		for name_:String in fixture_names():
			if selected.is_empty() or selected==name_:diagnose(build_fixture(name_))
		report.method="Frozen baseline with per-loop probes ON. Three observations, substage overhead included in total. Attribution only, not a speed comparison."
	else:
		prepare_matrix();projection_matrix();window_path_checks();reuse_matrix()
		for name_:String in fixture_names():
			if not name_ in Fixture.names():compare_prepare(build_fixture(name_),true)
		report.cases=cases;report.case_count=cases.size()
	finish()
