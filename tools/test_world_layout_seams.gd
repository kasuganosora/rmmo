extends SceneTree
const Seams = preload("res://scripts/world_editor/world_layout_seams.gd")
const LayoutTools = preload("res://scripts/world_editor/world_layout_tools.gd")
const Resources = preload("res://scripts/world3d/map_resource_store.gd")
const Location = preload("res://scripts/world3d/world_location.gd")
class FakeAddresses extends RefCounted:
	var catalog: RefCounted
	func _init(root_: String) -> void:
		catalog=preload("res://scripts/world_editor/world_map_catalog.gd").new(root_)
class ObservedStore extends RefCounted:
	var root: String
	var observations: Array
	var calls := 0
	func _init(root_: String, values: Array) -> void:
		root=root_; observations=values
	func get_layout(_document_id: String) -> Dictionary:
		var result: Dictionary=observations[mini(calls,observations.size()-1)].duplicate(true)
		calls+=1
		return result
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",label)
func terrain(id: String, size_x: float, size_z: float, columns: int, rows: int) -> Dictionary:
	var heights := []; heights.resize((columns+1)*(rows+1)); heights.fill(0.0)
	var holes := []; holes.resize(columns*rows); holes.fill(false)
	return {"uuid":id,"kind":"box","position":[size_x*.5,0,size_z*.5],"rotation":[0,0,0],"size":[size_x,1,size_z],"terrain_mesh":{"version":1,"columns":columns,"rows":rows,"floor":-16,"heights":heights,"holes":holes}}
func has_code(report: Dictionary, code: String) -> bool:
	return report.diagnostics.any(func(row):return row.code==code)
func excluded(report: Dictionary, reason: String) -> bool:
	return report.diagnostics.any(func(row):return row.get("excluded_a",{}).has(reason) or row.get("excluded_b",{}).has(reason))
func regions() -> Dictionary:
	return {"materials":["soil"],"regions":[{"id":"field","polygon":[[0,0],[3,0],[3,3],[0,3]],"feather":1,"opacity":1,"layer":0}]}
func native_map(path: String, content_root: String, record: Dictionary, map_ref: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var written: Dictionary=Resources.write_records([record],path,content_root)
	if not written.ok: return false
	var extra := {"rmmo_format":Location.FORMAT,"rmmo_version":Location.FORMAT_VERSION,"rmmo_storage":Location.STORAGE,"map_ref":map_ref,"rmmo_records":written.records,"rmmo_resource_dependencies":written.dependencies}
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify({"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"extras":extra}]},"",true,true))
	file.close()
	return true
func observed_report(api: RefCounted, content_root: String, before: Dictionary, after: Dictionary, seam_id: String = "low") -> Dictionary:
	api.store=ObservedStore.new(content_root,[before,after])
	return api.validate_seams({"document_id":"layout:fixture","space_id":"outdoor","seam_id":seam_id})
func report_proof_regression() -> void:
	var fixture := "D:/code/rmmo_runtime/review_artifacts/world_layout_d2_20261101/seam_sources_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	var path_a:=fixture.path_join("packs/demo/maps/Map1.gltf")
	var path_b:=fixture.path_join("packs/demo/maps/Map2.gltf")
	var ground_a:=terrain("proof_a",10,10,10,10)
	var ground_b:=terrain("proof_b",20,10,20,10)
	ground_b.terrain_mesh.heights[8*21]=0.25
	var written:=native_map(path_a,fixture,ground_a,"demo/a") and native_map(path_b,fixture,ground_b,"demo/b")
	check(written,"source-proof regression writes isolated native reference fixtures")
	if not written: return
	var low := {"id":"low","a":{"placement_id":"a","edge":"x_max","interval_m":[0,5]},"b":{"placement_id":"b","edge":"x_min","interval_m":[0,5]},"mode":"continuous"}
	var high := low.duplicate(true); high.id="high"; high.a.interval_m=[5,10]; high.b.interval_m=[5,10]
	var layout := {"schema_version":1,"world_key":"proof","units":"meters","up_axis":"Y","spaces":[{"id":"outdoor","placements":[{"id":"a","pack_id":"demo","map_number":"1","origin_m":[-10,0,-10],"ownership_xz_m":[0,0,10,10]},{"id":"b","pack_id":"demo","map_number":"2","origin_m":[0,0,-10],"ownership_xz_m":[0,0,20,10]}],"seams":[low,high]}]}
	var baseline := {"ok":true,"document":{"document_id":"layout:fixture","edit_revision":3,"disk_sha":"layout_sha","read_only":false,"disk_conflict":false},"layout":layout,"bindings":[{"space_id":"outdoor","placement_id":"a","path":path_a,"source_sha":FileAccess.get_sha256(path_a)},{"space_id":"outdoor","placement_id":"b","path":path_b,"source_sha":FileAccess.get_sha256(path_b)}],"inputs":{"owner":{"metadata_sha":"owner_metadata"},"packs":[{"metadata_sha":"dependency_metadata","catalog_sha":"catalog_sha","catalog_edit_revision":2}],"maps":[{"path":path_a,"source_sha":FileAccess.get_sha256(path_a)},{"path":path_b,"source_sha":FileAccess.get_sha256(path_b)}]}}
	var api:=LayoutTools.new(null,FakeAddresses.new(fixture))
	var report:=observed_report(api,fixture,baseline,baseline)
	check(report.ok and report.heightfields_match and api.store.calls==2,"facade retains real native inspect and reobserves its layout source")
	if not report.ok: return
	check(report.inputs.size()==2 and not report.inputs[0].dependencies.is_empty(),"report retains byte-verified immutable native dependencies")
	check(report.layout_inputs==baseline.inputs and report.document==baseline.document and report.selection=={"space_id":"outdoor","seam_id":"low"} and report.layout_sha.length()==64,"report exposes exact layout provenance and selection")
	var other:=observed_report(api,fixture,baseline,baseline,"high")
	check(other.ok and not other.heightfields_match and other.report_id!=report.report_id,"different selected seams over identical source files have distinct report IDs")
	check(observed_report(api,fixture,baseline,baseline).report_id==report.report_id,"unchanged sources and scope retain stable report identity")
	var changed:=baseline.duplicate(true); changed.document.edit_revision+=1
	check(not observed_report(api,fixture,baseline,changed).ok,"edit revision changing during native inspect discards its successful report")
	changed=baseline.duplicate(true); changed.document.disk_sha="replacement_layout"
	check(not observed_report(api,fixture,baseline,changed).ok,"layout disk baseline changing during native inspect discards its successful report")
	changed=baseline.duplicate(true); changed.layout.spaces[0].placements[0].origin_m[1]=1.0
	check(not observed_report(api,fixture,baseline,changed).ok,"layout payload change cannot pass with an unchanged revision number")
	changed=baseline.duplicate(true); changed.inputs.packs[0].catalog_sha="replacement_catalog"
	check(not observed_report(api,fixture,baseline,changed).ok,"catalogue baseline changing during native inspect discards its successful report")
	changed=baseline.duplicate(true); changed.inputs.owner.metadata_sha="replacement_owner"
	check(not observed_report(api,fixture,baseline,changed).ok,"owner metadata changing during native inspect discards its successful report")
	changed=baseline.duplicate(true); changed.inputs.packs[0].metadata_sha="replacement_dependency"
	check(not observed_report(api,fixture,baseline,changed).ok,"dependency metadata changing during native inspect discards its successful report")
	other=observed_report(api,fixture,changed,changed)
	check(other.ok and other.report_id!=report.report_id,"report identity includes package proof even when native bytes are unchanged")
	changed=baseline.duplicate(true); changed.bindings[0].catalog_revision="replacement_binding"
	check(not observed_report(api,fixture,baseline,changed).ok,"changed placement binding cannot inherit the previous evidence")
	changed=baseline.duplicate(true); changed.document.read_only=true; changed.document.reason_code="pack_revision_changed"
	var rejected:=observed_report(api,fixture,baseline,changed)
	check(not rejected.ok and rejected.reason_code=="pack_revision_changed" and not rejected.has("heightfields_match") and not rejected.has("report_id"),"late read-only conflict returns failure without stale success evidence")
	changed=baseline.duplicate(true); changed.document.disk_conflict=true; changed.document.reason_code="layout_conflict"
	check(not observed_report(api,fixture,baseline,changed).ok,"late disk conflict invalidates the report")
	rejected=observed_report(api,fixture,baseline,{"ok":false,"reason_code":"pack_unavailable","message":"fixture unavailable"})
	check(not rejected.ok and rejected.reason_code=="pack_unavailable","late get_layout failure is not overwritten with native success")
func run() -> void:
	var pa := {"id":"a","origin_m":[-10,0,-10],"ownership_xz_m":[0,0,10,10]}
	var pb := {"id":"b","origin_m":[0,0,-10],"ownership_xz_m":[0,0,20,10]}
	var seam := {"id":"ab","a":{"placement_id":"a","edge":"x_max","interval_m":[0,10]},"b":{"placement_id":"b","edge":"x_min","interval_m":[0,10]}}
	var a := terrain("ta",10,10,10,10)
	var b := terrain("tb",20,10,20,10)
	var records := {"a":[a],"b":[b]}
	var placements := {"a":pa,"b":pb}
	var initial := records.duplicate(true)
	var report := Seams.compare("outdoor",seam,placements,records)
	check(report.ok and report.heightfields_match and report.samples==21,"different dimensions align across negative world coordinates")
	check(records==initial,"diagnosis never mutates native source records")
	check(not report.can_transfer,"height match grants no traversal")
	b.position[1]=0.25
	report=Seams.compare("outdoor",seam,placements,records)
	check(not report.heightfields_match and report.max_height_delta_m==0.25,"height step diagnosed")
	check(report.diagnostics[0].local_a_m[0]==10 and report.diagnostics[0].local_b_m[0]==0 and report.diagnostics[0].space_position_m[0]==0,"both local and space locations are reproducible")
	pb.origin_m[1]=-0.25
	check(Seams.compare("outdoor",seam,placements,records).heightfields_match,"map vertical origin accounts for actual surface height")
	b.terrain_mesh.holes[0]=true
	report=Seams.compare("outdoor",seam,placements,records)
	check(not report.heightfields_match and report.diagnostics.any(func(row):return row.code=="terrain_support_unverified"),"open cell not treated as support")
	b.terrain_mesh.holes[0]=false
	var coarse := terrain("coarse",20,10,10,5)
	coarse.position[1]=0.25
	report=Seams.compare("outdoor",seam,placements,{"a":[a],"b":[coarse]})
	check(not report.heightfields_match and report.diagnostics.any(func(row):return row.code=="terrain_sampling_mismatch"),"unequal tangent sampling cannot pass")
	b.rotation[1]=90
	check(not Seams.compare("outdoor",seam,placements,records).heightfields_match,"rotated native terrain remains unverified")
	b.rotation[1]=0
	a.position[0]=100
	check(not Seams.compare("outdoor",seam,placements,records).heightfields_match,"terrain outside seam cannot provide coverage")
	a.position[0]=5
	var duplicate := b.duplicate(true); duplicate.position[1]+=2
	check(not Seams.compare("outdoor",seam,placements,{"a":[a],"b":[b,duplicate]}).heightfields_match,"ambiguous stacked support is not silently chosen")
	# Raise one edge knot, keeping its adjacent endpoints flat: sampling must catch it.
	b.terrain_mesh.heights[5*21]=0.5
	report=Seams.compare("outdoor",seam,placements,records)
	check(report.max_height_delta_m==0.5 and not report.heightfields_match,"interior boundary knot mismatch is detected")
	b.terrain_mesh.heights[5*21]=0
	b.position[1]=0; pb.origin_m[1]=0
	# A real sub-millimetre gap is not filled by the independent height tolerance.
	b.position[0]+=0.0005
	report=Seams.compare("outdoor",seam,placements,records)
	check(not report.heightfields_match and excluded(report,"native_outer_edge_not_coincident"),"0.5 mm native coverage gap remains unverified")
	check(has_code(report,"terrain_support_unverified") and report.diagnostics[0].message.contains("外边"),"unsupported native boundary coverage is explicitly explained")
	b.position[0]=10
	pb.origin_m[0]=0.0005
	report=Seams.compare("outdoor",seam,placements,records)
	check(not report.heightfields_match and absf(report.diagnostics[0].horizontal_offset_m+0.0005)<1e-12,"layout tolerance does not certify separate native edge lines")
	pb.origin_m[0]=0
	duplicate=b.duplicate(true)
	report=Seams.compare("outdoor",seam,placements,{"a":[a],"b":[b,duplicate]})
	check(not report.heightfields_match and report.diagnostics[0].coverage_b=="overlapping_native_edges","identical coplanar overlapping native records are ambiguous")
	# Interior cuts can intersect triangle diagonals between tangent grid knots;
	# the outer-edge checker must decline them even if all sampled heights agree.
	var interior := b.duplicate(true); interior.position[0]=5.7
	interior.terrain_mesh.heights[5]=0.75
	report=Seams.compare("outdoor",seam,placements,{"a":[a],"b":[interior]})
	check(not report.heightfields_match and excluded(report,"interior_cut_unsupported"),"diagonal-crossing interior slice requires a future explicit cut sampler")
	var tile_low := terrain("low",20,5,20,5)
	var tile_high := terrain("high",20,5,20,5); tile_high.position[2]=7.5
	report=Seams.compare("outdoor",seam,placements,{"a":[a],"b":[tile_low,tile_high]})
	check(report.heightfields_match,"adjacent native tiles may share an agreeing endpoint")
	tile_high.position[2]+=0.0005
	report=Seams.compare("outdoor",seam,placements,{"a":[a],"b":[tile_low,tile_high]})
	check(not report.heightfields_match and has_code(report,"terrain_support_unverified"),"small tangent gap between tiles is sampled without deduplicating it away")
	tile_high.position[2]=7.4995
	report=Seams.compare("outdoor",seam,placements,{"a":[a],"b":[tile_low,tile_high]})
	check(not report.heightfields_match and report.diagnostics.any(func(row):return row.coverage_b=="overlapping_native_edges"),"small positive tile overlap is ambiguous")
	# Optional region definitions arrive from byte-verified native references but
	# still need semantic/type validation before any furrow dictionary access.
	var malformed: Array = [null,[],false,{}, {"materials":["soil"],"regions":false}, {"materials":["soil"],"regions":[null]}]
	for bad in malformed:
		var invalid := b.duplicate(true); invalid.terrain_regions=bad
		report=Seams.compare("outdoor",seam,placements,{"a":[a],"b":[invalid]})
		check(not report.heightfields_match and excluded(report,"invalid_terrain_regions"),"malformed terrain_regions safely rejected: "+str(bad))
	for bad in [null,false,[],{"height":"bad"},{"height":NAN}]:
		var invalid := b.duplicate(true); invalid.terrain_regions=regions(); invalid.terrain_regions.regions[0].furrows=bad
		report=Seams.compare("outdoor",seam,placements,{"a":[a],"b":[invalid]})
		check(not report.heightfields_match and excluded(report,"invalid_terrain_regions"),"malformed furrow descriptor safely rejected: "+str(bad))
	var painted := b.duplicate(true); painted.terrain_regions=regions()
	check(Seams.compare("outdoor",seam,placements,{"a":[a],"b":[painted]}).heightfields_match,"valid material region without furrows preserves native edge comparison")
	painted.terrain_regions.regions[0].furrows={"spacing":1,"height":0.1,"angle":0,"phase":0,"margin":1}
	report=Seams.compare("outdoor",seam,placements,{"a":[a],"b":[painted]})
	check(not report.heightfields_match and excluded(report,"unsupported_furrows"),"valid raised furrows require separate surface validation")
	# Minimum-size native terrain can have sub-mm sampling. A fixed 1 mm
	# sampling tolerance would incorrectly accept a factor-of-two grid change.
	var tiny_pa := {"id":"a","origin_m":[0,0,0],"ownership_xz_m":[0,0,0.01,0.01]}
	var tiny_pb := {"id":"b","origin_m":[0.01,0,0],"ownership_xz_m":[0,0,0.01,0.01]}
	var tiny_seam := seam.duplicate(true); tiny_seam.a.interval_m=[0,0.01]; tiny_seam.b.interval_m=[0,0.01]
	var tiny_a := terrain("tiny_a",0.01,0.01,32,32)
	var tiny_b := terrain("tiny_b",0.01,0.01,32,64)
	report=Seams.compare("tiny",tiny_seam,{"a":tiny_pa,"b":tiny_pb},{"a":[tiny_a],"b":[tiny_b]})
	check(not report.heightfields_match and has_code(report,"terrain_sampling_mismatch"),"tiny 32 versus 64 row grids fail sampling compatibility")
	tiny_b=terrain("tiny_b",0.01,0.01,32,32)
	check(Seams.compare("tiny",tiny_seam,{"a":tiny_pa,"b":tiny_pb},{"a":[tiny_a],"b":[tiny_b]}).heightfields_match,"equal tiny grids still match")
	var phase_seam := tiny_seam.duplicate(true); phase_seam.a.interval_m=[0.001,0.009]; phase_seam.b.interval_m=[0.001,0.009]
	tiny_b.position[2]+=0.0001
	report=Seams.compare("tiny",phase_seam,{"a":tiny_pa,"b":tiny_pb},{"a":[tiny_a],"b":[tiny_b]})
	check(not report.heightfields_match and has_code(report,"terrain_sampling_mismatch"),"sub-mm phase change on equal fine grids is not a height tolerance")
	tiny_b.position[2]=0.005
	tiny_pa.origin_m[2]=999999999000.125; tiny_pb.origin_m[2]=999999999000.125
	check(Seams.compare("tiny",tiny_seam,{"a":tiny_pa,"b":tiny_pb},{"a":[tiny_a],"b":[tiny_b]}).heightfields_match,"large tangent origin retains small map-local grid phases")
	# Sub-mm height differences remain within the stated height contract; this
	# does not widen support, nor does it hide >1 mm deltas at large Y origins.
	b.position[1]=0.0005
	check(Seams.compare("outdoor",seam,placements,records).heightfields_match,"height tolerance is independent from strict horizontal coverage")
	pa.origin_m[1]=999999999000.0; pb.origin_m[1]=999999999000.0; b.position[1]=0.00101
	report=Seams.compare("outdoor",seam,placements,records)
	check(not report.heightfields_match and absf(report.max_height_delta_m-0.00101)<1e-12,"large vertical origin does not erase a greater-than-tolerance height step")
	pa.origin_m[1]=0; pb.origin_m[1]=0; b.position[1]=0
	# Large origins use scalar differences rather than float32 vectors.
	pa.origin_m[0]=999999999000.125; pb.origin_m[0]=999999999010.125
	check(Seams.compare("outdoor",seam,placements,records).heightfields_match,"large origin does not collapse map-local edge detail")
	report_proof_regression()
	print("WORLD_LAYOUT_SEAMS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
