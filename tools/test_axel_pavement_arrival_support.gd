extends "res://tools/review_axel_functional_building_exteriors.gd"
## Headless predicate regression using SHA-pinned actual native physics rays.
## No map save, GPU, game traversal or acceptance result overwrite.
const PROBE_SHA="98bd9987f446f1ff41126dadb85fddd2594b105cc96a0d0b519dccaf7092bd84"
const TEST_MAP="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf"
var replay_rays:Array=[]
func ray_surface(point:Vector3,_up:float=4.,_down:float=8.)->Dictionary:
	for row:Dictionary in replay_rays:
		if Vector2(row.at[0]-point.x,row.at[2]-point.z).length()<.00001:
			var hit:Dictionary=row.combined.duplicate(true);hit.ok=not hit.is_empty() and float(hit.get("normal",[0,0,0])[1])>=cos(deg_to_rad(45));return hit
	return {"ok":false,"at":xyz(point)}
func rejected(name_:String,source:Dictionary,hit:Dictionary,patch:Array)->void:
	check(not pavement_arrival_patch_result(source,hit,patch).passed,name_)
func run()->void:
	started_ms=Time.get_ticks_msec();report={"checks":[],"scope":"Headless node-support regression using SHA-pinned isolated native physics evidence; not GPU functional acceptance"}
	var path:=FB_OUT+"/mill_approach_road_readonly_probe.json"
	if not check(FileAccess.get_sha256(path)==PROBE_SHA,"actual native physics evidence SHA"):quit(1);return
	var probe:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path));replay_rays=probe.rays
	if not check(FileAccess.get_sha256(TEST_MAP)==probe.map_sha256,"same exact candidate used by isolated physics"):quit(1);return
	document=Document.open_file(TEST_MAP)
	for record:Dictionary in document.records:records[record.uuid]=record
	var authored:=saved_pavement_point(vector(probe.center));var center:=ray_surface(vector(probe.center));var result:=pavement_arrival_support(authored)
	check(result.passed and result.mode=="strict_four_corner_support","actual seam center miss accepted only with four real source-interior road hits",result)
	check(result.contact_patch.size()==4 and result.contact_patch.all(func(row):return row.source_interior and row.hit.id==authored.id),"all four actual source polygon interiors and exact road UUIDs checked")
	check(result.hit.id=="axel_terrain_05_03" and absf(float(result.authored.position[1])-float(result.hit.position[1])-.025)<.000001,"center terrain miss retained with actual 25mm road clearance")
	check(result.diagnosis.sha256==FileAccess.get_sha256(result.diagnosis.path),"diagnosis SHA reference matches independent report")
	var patch:Array=result.contact_patch
	if patch.size()!=4:quit(1);return
	check(pavement_arrival_patch_result(patch[0].source,patch[0].hit,[]).passed,"ordinary exact center road hit still passes without fallback")
	var edge:=authored.duplicate(true);edge.position=[296.,3.8,208.]
	check(not pavement_source_interior(edge),"actual road tile corner cannot count as source-interior support")
	var changed:=patch.duplicate(true);changed[0].source_interior=false
	rejected("road edge outside strict polygon interior rejected",authored,center,changed)
	changed=patch.duplicate(true);changed[0].source={"ok":false}
	rejected("missing authored quarter rejected",authored,center,changed)
	changed=patch.duplicate(true);changed[0].hit={"ok":false};changed[1].hit={"ok":false}
	rejected("missing live half-road rejected",authored,center,changed)
	changed=patch.duplicate(true);changed[0].hit=center.duplicate(true)
	rejected("terrain-only corner rejected",authored,center,changed)
	changed=patch.duplicate(true);changed[0].hit.id="foreign_obstruction"
	rejected("foreign live collider rejected",authored,center,changed)
	var foreign:Dictionary=records[authored.id].duplicate(true);foreign.uuid="different_road";records[foreign.uuid]=foreign
	changed=patch.duplicate(true);changed[0].hit.id=foreign.uuid
	rejected("different overlapping road owner rejected",authored,center,changed)
	changed=patch.duplicate(true);changed[0].source.id=foreign.uuid;changed[0].hit.id=foreign.uuid
	rejected("source patch crossing to other road UUID rejected",authored,center,changed)
	changed=patch.duplicate(true);changed[0].hit.position[1]+=.006
	rejected("raised road obstruction beyond existing 5mm error rejected",authored,center,changed)
	changed=patch.duplicate(true);changed[0].hit.normal=[1.,0.,0.]
	rejected("non-upward live support rejected",authored,center,changed)
	changed=patch.duplicate(true);changed[0].source.position[1]+=.006
	rejected("incorrect source height rejected",authored,center,changed)
	changed=patch.duplicate(true);changed[1].offset=changed[0].offset.duplicate()
	rejected("duplicate corner offsets cannot replace four corners",authored,center,changed)
	changed=patch.duplicate(true);changed[1].source.position=changed[0].source.position.duplicate();changed[1].hit.position=changed[0].hit.position.duplicate()
	rejected("duplicate measured position cannot replace missing quarter",authored,center,changed)
	rejected("only three corners rejected",authored,center,patch.slice(0,3))
	var wrong_center:=center.duplicate(true);wrong_center.id="foreign_obstruction"
	rejected("center foreign obstruction cannot activate patch",authored,wrong_center,patch)
	wrong_center=center.duplicate(true);wrong_center.position[1]=authored.position[1]+.025
	rejected("center raised terrain cannot activate patch",authored,wrong_center,patch)
	wrong_center=center.duplicate(true);wrong_center.position[1]=authored.position[1]-.05
	rejected("center terrain too low cannot activate patch",authored,wrong_center,patch)
	wrong_center=center.duplicate(true);wrong_center.position[1]=authored.position[1]-.01
	rejected("center terrain too high cannot activate patch",authored,wrong_center,patch)
	wrong_center=center.duplicate(true);wrong_center.normal=[1.,0.,0.]
	rejected("center steep terrain cannot activate patch",authored,wrong_center,patch)
	rejected("missing source road cannot activate patch",{"ok":false},center,patch)
	check(FileAccess.get_sha256(TEST_MAP)==probe.map_sha256,"candidate unchanged after all fixtures")
	report.passed=failures==0;report.failures=failures;report.map_sha256=probe.map_sha256;report.physics_probe_sha256=PROBE_SHA
	report.predicate_script_sha256=FileAccess.get_sha256("res://tools/review_axel_functional_building_exteriors.gd")
	report.fixture_script_sha256=FileAccess.get_sha256("res://tools/test_axel_pavement_arrival_support.gd")
	var file:=FileAccess.open(FB_OUT+"/pavement_arrival_support_precheck.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("PAVEMENT_ARRIVAL_SUPPORT_PRECHECK failures=",failures," checks=",report.checks.size());quit(0 if failures==0 else 1)
