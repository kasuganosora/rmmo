extends "res://tools/test_road_prepare_differential.gd"
## Strict post-main baseline for CPU default painting and first-surface grouping.
const Baseline = preload("res://review_artifacts/road_paint_20261017/road_tools_chain_ref.gd")
const ROOT := "res://review_artifacts/road_paint_20261017/"
const BASE_SHA := "96b5ff93d77ea323fe70003aa4399d1bb37810f2951ea66e0dcc1eefb55cc5a9"
const Paint = preload("res://scripts/world3d/surface_materials.gd")
const OriginalPaint = preload("res://review_artifacts/road_paint_20261017/surface_materials_ref.gd")
const CpuMesh = preload("res://scripts/world3d/ground_cpu_mesh.gd")

func initialize() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
		elif argument.begins_with("--case="): selected = argument.trim_prefix("--case=")
		else: check(false, "unknown argument", argument)
	var absolute := ProjectSettings.globalize_path(report_path).replace("\\", "/").simplify_path()
	var allowed := ProjectSettings.globalize_path(ROOT).replace("\\", "/").simplify_path().trim_suffix("/") + "/"
	if not absolute.begins_with(allowed):
		push_error("Report must be inside this worktree's " + ROOT); quit(2); return false
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	check(FileAccess.get_sha256(ROOT + "road_tools_chain_ref.gd") == BASE_SHA, "d2cd069 independent paint chain bytes pinned")
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"reference.json"))
	for filename:String in manifest.files:
		check(FileAccess.get_sha256(ROOT+filename)==manifest.files[filename].sha256,"frozen dependency bytes "+filename)
	check(selected.is_empty() or selected in fixture_names(), "selected fixture exists")
	var scripts := {}
	source_hashes("res://scripts/world_editor", scripts); source_hashes("res://scripts/world3d", scripts)
	for path: String in ["res://tools/road_prepare_fixture.gd", "res://tools/test_road_prepare_differential.gd", "res://tools/benchmark_road_prepare.gd", "res://tools/test_road_default_paint.gd", "res://tools/benchmark_road_paint.gd", "res://project.godot"]:
		scripts[path] = FileAccess.get_sha256(path)
	var commit: Array = []; OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "HEAD"], commit)
	report = {"version": 1, "engine": Engine.get_version_info(), "engine_executable_sha256": FileAccess.get_sha256(OS.get_executable_path()),
		"head_commit": "".join(commit).strip_edges(), "reference_sha256": BASE_SHA, "script_sha256": scripts, "display": DisplayServer.get_name()}
	return failures == 0

func compare_context(name_: String, context: Node3D, args: Dictionary, current: RefCounted, _old: RefCounted, expected_ok: Variant = null, conflict := "") -> Dictionary:
	var baseline := Baseline.new(); baseline.editor = context
	var result := super.compare_context(name_, context, args, current, baseline, expected_ok, conflict)
	baseline.editor = null
	return result

func compare_record_order_correctness(fixture: Dictionary) -> void:
	# In this batch author-byte preservation is already in the reference.
	# It must be completely equal too; no exception or normalized comparison.
	var result := compare_prepare(fixture, true)
	var previous: Dictionary = fixture.records[-1]
	var matches: Array = result.get("records", []).filter(func(record): return record.uuid == previous.uuid)
	check(matches.size() == 1 and var_to_bytes(matches[0]) == var_to_bytes(previous), "decorated record retains original author bytes")

func fixture_names()->Array:
	return Fixture.names()+["terrain64_wavy","terrain64_existing"]

func build_fixture(name_:String)->Dictionary:
	if name_ in Fixture.names():return Fixture.build(name_)
	var fixture:=Fixture.local_terrain();fixture.name=name_
	if name_=="terrain64_wavy":
		for z in 65:
			for x in 65:fixture.records[0].terrain_mesh.heights[z*65+x]=.02*sin(x*.73)*cos(z*.61)+.005*sin(x*1.2+z*.4)
	elif name_=="terrain64_existing":
		var context:=Fixture.context(fixture);var baseline:=Baseline.new();baseline.editor=context
		var prepared:Dictionary=baseline.prepare(fixture.args)
		if prepared.get("ok",false):
			fixture.records.append_array(prepared.records.duplicate(true));fixture.layout.roads=prepared.graph.duplicate(true);fixture.layout.road_surface=prepared.manifest.duplicate(true)
		else:fixture.construction_error=str(prepared)
		baseline.editor=null;context._waterways.editor=null;context.free()
	return fixture

func paint_compare(name_:String,record:Dictionary,material:Dictionary,ok:bool=true)->void:
	var current:=Roads.new();var baseline:=Baseline.new()
	var actual_record:=record.duplicate(true);var expected_record:=record.duplicate(true)
	var before:=var_to_bytes([record,material])
	var actual:Dictionary=current.paint_default(actual_record,material);var expected:Dictionary=baseline.paint_default(expected_record,material)
	check(var_to_bytes([actual,actual_record])==var_to_bytes([expected,expected_record]),name_+" entire paint result and author record exact",actual)
	check(actual.get("ok",false)==ok,name_+" expected outcome",actual)
	check(before==var_to_bytes([record,material]),name_+" input record and material immutable")

func geometry_checks(record:Dictionary)->void:
	var node:=MeshInstance3D.new();var original:=MeshInstance3D.new()
	node.mesh=Surface.mesh(record,null);original.mesh=node.mesh
	var expected:Dictionary=OriginalPaint.geometry(original)
	var top:Dictionary=Paint.geometry(node,true)
	check(top.ok and top.surfaces.size()==1 and var_to_bytes(top.surfaces[0])==var_to_bytes(expected.surfaces[0]),"top includes exact arrays, face roots, order and signature")
	check(not node.has_meta("paint_geometry"),"partial analysis never fills full manual-paint cache")
	var complete:Dictionary=Paint.geometry(node)
	check(var_to_bytes(complete)==var_to_bytes(expected),"full manual geometry remains byte identical after top-only call")
	check(var_to_bytes(Paint.geometry(node,true))==var_to_bytes(top),"full cache can serve the exact top-only view")
	check(var_to_bytes(Paint.geometry(node))==var_to_bytes(complete),"top-only cache view never truncates full result")
	node.free();original.free()
	# A later slot still participates in validation before default paint.
	for kind:String in ["empty","over_budget","custom","bones"]:
		var arrays:Array=Surface.arrays(record)[0].duplicate(true)
		match kind:
			"empty":arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array();arrays[Mesh.ARRAY_INDEX]=PackedInt32Array()
			"over_budget":
				var indices:=PackedInt32Array();indices.resize((Paint.MAX_TRIANGLES+1)*3);indices.fill(0);arrays[Mesh.ARRAY_INDEX]=indices
			"custom":arrays[Mesh.ARRAY_CUSTOM0]=PackedByteArray([1])
			"bones":arrays[Mesh.ARRAY_BONES]=PackedInt32Array([0])
		var cpu:=CpuMesh.new();cpu.surfaces=[Surface.arrays(record)[0],arrays]
		node=MeshInstance3D.new();original=MeshInstance3D.new();node.set_meta("paint_source",cpu);original.set_meta("paint_source",cpu)
		var actual:=Paint.geometry(node,true);expected=OriginalPaint.geometry(original)
		check(not actual.ok and var_to_bytes(actual)==var_to_bytes(expected),"unused slot rejects exactly: "+kind,actual)
		node.free();original.free()

func paint_matrix()->void:
	var material:Dictionary=Fixture.MaterialTool.new().library.find("builtin:white")
	var seed_record:Dictionary={};var kerb_record:Dictionary={}
	for name_:String in fixture_names():
		var fixture:=build_fixture(name_);var context:=Fixture.context(fixture);var baseline:=Baseline.new();baseline.editor=context
		var prepared:Dictionary=baseline.prepare(fixture.args)
		check(prepared.get("ok",false),name_+" native paint seed",prepared.get("error",""))
		for index in prepared.get("records",[]).size():
			var record:Dictionary=prepared.records[index].duplicate(true);record.erase("surface_paint")
			paint_compare(name_+"/"+str(index),record,material)
			if seed_record.is_empty():seed_record=record.duplicate(true)
			if record.road_mesh.has("kerbs") and kerb_record.is_empty():kerb_record=record.duplicate(true)
		baseline.editor=null;context._waterways.editor=null;context.free()
	geometry_checks(kerb_record)
	var pbr:Dictionary=preload("res://scripts/world_editor/surface_material_library.gd").new().find("pack:default:paving/outdoor_flagstone/material")
	check(not pbr.is_empty(),"real PBR fixture available")
	if not pbr.is_empty():
		paint_compare("actual_PBR",seed_record,pbr)
		report.material_dependencies={}
		for field:String in Paint.MAP_FIELDS:
			var path:String=pbr.get(field,"")
			if not path.is_empty():report.material_dependencies[path]=FileAccess.get_sha256(path)
	var invalid:=material.duplicate(true);invalid.color=[1,1,1,2]
	paint_compare("invalid_material",seed_record,invalid,false)
	invalid=material.duplicate(true);invalid.texture_path="D:/code/rmmo_runtime/__road_paint_missing_20261017.png"
	check(not FileAccess.file_exists(invalid.texture_path),"missing dependency fixture is absent")
	paint_compare("missing_dependency",seed_record,invalid,false)
	var fragmented:=seed_record.duplicate(true);fragmented.road_mesh.erase("kerbs");fragmented.erase("road_kerb_material")
	fragmented.road_mesh.polygons=[];fragmented.road_mesh.erase("elevations");fragmented.erase("terrain_follow")
	for i in 129:
		var x:float=-.45+(i%16)*.05;var z:float=-.45+floori(i/16.)*.05
		fragmented.road_mesh.polygons.append([[x,z],[x+.02,z],[x,z+.02]])
	paint_compare("129_disjoint_faces",fragmented,material,false)
	fragmented.road_mesh.polygons.pop_back()
	paint_compare("128_disjoint_faces_allowed",fragmented,material,true)
	var over_kerbs:=kerb_record.duplicate(true);var part:Dictionary=over_kerbs.road_mesh.kerbs[0].duplicate(true)
	part.cap_a=false;part.cap_b=false;over_kerbs.road_mesh.kerbs=[]
	for i in 4200:over_kerbs.road_mesh.kerbs.append(part.duplicate(true))
	paint_compare("unpainted_kerb_triangle_budget",over_kerbs,material,false)
	var shift:=seed_record.duplicate(true);shift.road_mesh.uv_origin[0]+=.1
	paint_compare("changed_UV",shift,material)
	shift=seed_record.duplicate(true);shift.size[1]*=1.1
	paint_compare("changed_thickness",shift,material)

func run()->void:
	report_path=ROOT+"differential.json"
	if not initialize():finish();return
	if selected.is_empty():
		prepare_matrix()
		for name_:String in ["terrain64_wavy","terrain64_existing"]:compare_prepare(build_fixture(name_),true)
		paint_matrix()
	else:compare_prepare(build_fixture(selected),true)
	report.cases=cases;report.case_count=cases.size()
	report.method={"reference":"Frozen d2cd069 road_tools -> original surface_materials and road_surface; all other helpers shared and unchanged.",
		"comparison":"Full prepare and direct paint return/record bytes; full manual geometry and selected top arrays/face IDs/signatures exact. No normalization or omissions.",
		"scope":"CPU correctness only. Real UI/HTTP, rendering batches, sculpt follow and save/reopen verified separately."}
	finish()
