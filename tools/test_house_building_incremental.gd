extends SceneTree
## CPU transaction tests. Full editor node retention/HTTP checks run separately.
const Tools = preload("res://scripts/world_editor/building_tools.gd")
const Blueprint = preload("res://scripts/world3d/building_blueprint.gd")
const Fixtures = preload("res://scripts/world3d/building_fixtures.gd")

class MeasuredDocument extends "res://scripts/world3d/world_document.gd":
	var finds := 0
	func _find(uuid: String) -> Dictionary:
		finds += 1
		return super._find(uuid)

class Guard extends RefCounted:
	func guard() -> Dictionary: return {"ok":true}

class TestPanel extends RefCounted:
	var selected := ""
	var previews_cleared := 0
	func refresh_list(id := "") -> void: selected = id
	func clear_preview() -> void: previews_cleared += 1

class TestCity extends RefCounted:
	var refreshes := 0
	func refresh() -> void: refreshes += 1

class Host extends Node3D:
	var _doc := MeasuredDocument.new()
	var _gameplay := Guard.new()
	var _building_panel := TestPanel.new()
	var _city := TestCity.new()
	var _dirty := false
	var commits: Array = []
	var rebuilds := 0
	func _record_editable(record: Dictionary) -> bool:
		return not record.get("editor_locked",false) and not record.get("editor_hidden",false) and not record.get("test_floor_excluded",false)
	func _commit_records(ids: Array) -> void: commits.append(ids.duplicate())
	func _rebuild() -> void: rebuilds += 1

var failed := 0
var checked := 0
var host: Host
var tools: RefCounted

func _init() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checked += 1
	if not value: failed += 1; push_error(label)
	else: print("PASS ",label)

func box(uuid: String, id: String, part: String, x: float) -> Dictionary:
	return {"uuid":uuid,"kind":"box","surface_id":"block","position":[x,1.,0.],"rotation":[0.,0.,0.],"size":[.5,2.,.5],"collision":"block","building":{"id":id,"part":part,"role":"shell","floor":0,"floor_y":0.}}

func register(id: String, records: Array, baked := false) -> void:
	var value := {"version":Blueprint.VERSION,"parameters":Blueprint.defaults(),"position":[0.,0.,0.],"yaw":0.,"parts":{},"signatures":{},"baked":baked}
	for record: Dictionary in records:
		value.parts[record.building.part] = record.uuid
		value.signatures[record.building.part] = Blueprint.geometry_signature(record)
		host._doc.records.append(record)
	if not host._doc.map_meta.has("building_instances"): host._doc.map_meta.building_instances = {}
	host._doc.map_meta.building_instances[id] = value

func old_conflicts(id: String) -> Array:
	var rows: Array = []
	var value: Dictionary = tools.instances()[id]
	for part in value.parts:
		var record: Dictionary = host._doc._find(value.parts[part])
		if record.is_empty(): rows.append({"part":part,"reason":"构件已被删除"}); continue
		if record.get("building",{}).get("id")!=id or Blueprint.geometry_signature(record)!=value.signatures[part]: rows.append({"id":record.uuid,"part":part,"reason":"构件已手工改动"})
		elif not host._record_editable(record): rows.append({"id":record.uuid,"part":part,"reason":"构件被锁定、隐藏或不在当前楼层"})
	return rows

func snapshot() -> Dictionary:
	return {"state":host._doc.recovery_snapshot(),"undo":host._doc._undo.size(),"redo":host._doc._redo.size(),"commits":host.commits.size(),"dirty":host._dirty,"previews":host._building_panel.previews_cleared,"city_refreshes":host._city.refreshes}

func same_ids(left: Array, right: Array) -> bool:
	var a := left.duplicate(); var b := right.duplicate(); a.sort(); b.sort()
	return a==b

func run() -> void:
	host = Host.new(); tools = Tools.new(); tools.editor = host
	# Match the town's house/record scale, with a mix of every conflict category.
	for i in 61:
		var records: Array = []
		for j in 37: records.append(box("house_%d_part_%d"%[i,j],"house_%d"%i,"part_%d"%j,i*30.+j))
		register("house_%d"%i,records,true)
	while host._doc.records.size()<4437:
		var extra := box("extra_%d"%host._doc.records.size(),"","",9999.)
		extra.erase("building"); host._doc.records.push_front(extra)
	host._doc._find("house_1_part_1").position[0] += 1.
	host._doc._find("house_2_part_1").editor_locked = true
	host._doc._find("house_3_part_1").editor_hidden = true
	host._doc._find("house_4_part_1").test_floor_excluded = true
	host._doc._find("house_5_part_1").building.id = "other"
	host._doc.records = host._doc.records.filter(func(r): return r.uuid!="house_6_part_1")
	var expected: Dictionary = {}; var started := Time.get_ticks_usec()
	for id in tools.instances(): expected[id] = old_conflicts(id)
	var old_ms := (Time.get_ticks_usec()-started)/1000.
	host._doc.finds = 0; started = Time.get_ticks_usec()
	var listed: Dictionary = tools.list_buildings(); var new_ms := (Time.get_ticks_usec()-started)/1000.
	check(listed.buildings.size()==61 and listed.buildings.all(func(row): return row.conflicts==expected[row.id]),"61-house list keeps exact missing/modified/ownership/protection conflicts")
	check(host._doc.finds==0,"building list does not call per-part linear document lookup")
	print("HOUSE_LIST_CPU_MS ",JSON.stringify({"old":old_ms,"indexed":new_ms,"records":host._doc.records.size(),"houses":61}))
	var before := snapshot(); var rejected := true
	for id in tools.instances(): rejected = rejected and not tools.update(id,{"width":16}).ok
	check(rejected and snapshot()==before,"all 61 frozen houses reject parameter updates without state/history/view effects")
	host._doc._find("house_2_part_1").erase("editor_locked")
	check(tools.conflicts("house_2").is_empty(),"next conflict call sees live mutation without stale persistent index")
	check(tools.conflicts("missing")==["建筑不存在"],"missing building conflict API unchanged")
	# Real bake transactions, using tiny untextured box groups (no scene/GPU).
	host._doc = MeasuredDocument.new(); host.commits.clear(); host._dirty = false
	var sentinel := box("sentinel","","",10000.); sentinel.erase("building")
	host._doc.records.append(sentinel)
	var plan := {"parameters":Blueprint.defaults(),"position":[0.,0.,0.],"yaw":0.,"instance_id":"new_house","records":[box("a","new_house","a",0.),box("b","new_house","b",1.),box("c","new_house","c",2.)]}
	before = snapshot()
	var layout := {"test_layout_marker":"block-placement"}
	var result: Dictionary = tools.commit([plan],"",layout)
	check(result.ok and tools.instances().new_house.baked and tools.instances().new_house.source_part_count==3,"new placement uses real frozen prefab bake and registration")
	var new_ids: Array = tools.instances().new_house.parts.values()
	check(same_ids(host.commits.back(),new_ids) and is_same(sentinel,host._doc.records[0]) and host.rebuilds==0,"new placement commits only created UUIDs and retains unrelated record identity")
	check(host._doc._undo.size()==before.undo+1 and host._building_panel.selected=="new_house","new placement retains one recovery transaction and panel selection")
	check(host._building_panel.previews_cleared==before.previews+1 and host._city.refreshes==before.city_refreshes+1 and host._doc.map_meta.editor_layout==layout,"placement clears preview and updates dependent city metadata when layout changes")
	var frozen := host._doc.recovery_snapshot()
	check(host._doc.undo() and host._doc.records==before.state.records and host._doc.map_meta==before.state.map_meta,"undo restores pre-placement records and metadata")
	check(host._doc.redo() and host._doc.records==frozen.records and host._doc.map_meta==frozen.map_meta,"redo restores exact frozen records and registration")
	for field in ["editor_locked","editor_hidden","test_floor_excluded"]:
		var member: Dictionary = host._doc._find(new_ids[0]); member[field] = true; before = snapshot()
		check(not tools.remove("new_house").ok and snapshot()==before,"delete rejects "+field+" without side effects")
		member.erase(field)
	before = snapshot()
	check(not tools.remove("new_house",true).ok and snapshot()==before,"frozen prefab cannot detach into editable parts")
	result = tools.remove("new_house")
	check(result.ok and not tools.instances().has("new_house") and same_ids(host.commits.back(),new_ids) and host._doc.records.size()==1,"delete commits only removed UUIDs and clears registry")
	check(host._doc.undo() and host._doc.records==before.state.records and host._doc.map_meta==before.state.map_meta,"delete undo restores prefab and registration")
	check(host._doc.redo() and host._doc.records.size()==1,"delete redo removes prefab again")
	# Explicit legacy migration replaces both removed and added component UUIDs.
	register("legacy",[box("legacy_a","legacy","a",0.),box("legacy_b","legacy","b",1.),box("legacy_c","legacy","c",2.)])
	before = snapshot(); host._doc.finds = 0
	result = tools.bake_existing("legacy")
	var migrated: Array = tools.instances().legacy.parts.values()
	check(result.ok and tools.instances().legacy.baked and migrated.size()==1,"legacy migration still bakes three static members into one component")
	check(host._doc.finds==0 and same_ids(host.commits.back(),["legacy_a","legacy_b","legacy_c"]+migrated),"migration indexes old members once and invalidates removed plus added UUIDs")
	check(host._doc.undo() and host._doc.records==before.state.records and host._doc.map_meta==before.state.map_meta,"migration undo restores editable legacy members")
	var door: Dictionary = host._doc._find("legacy_a")
	door.fixture = {"id":"door","kind":"door","pivot":[-.25,0.,0.],"angle":90.,"open":.5}
	var pose := Fixtures.transform(door); before = snapshot()
	result = tools.remove("legacy",true)
	var detached: Dictionary = host._doc._find("legacy_a")
	check(result.ok and not detached.has("building") and not detached.has("fixture") and Transform3D(Basis.from_euler(Blueprint.vec(detached.rotation)*PI/180.),Blueprint.vec(detached.position)).is_equal_approx(pose),"legacy detach preserves current hinge pose without moving unrelated records")
	check(same_ids(host.commits.back(),["legacy_a","legacy_b","legacy_c"]) and host.rebuilds==0,"legacy detach remains an incremental member-only commit")
	check(host._doc.undo() and host._doc.records==before.state.records and host._doc.map_meta==before.state.map_meta,"detach undo restores hinge and building metadata")
	var source: Dictionary = host._doc._find("legacy_b"); source.event_template = "kept-event"
	before = snapshot()
	check(not tools.bake_existing("legacy").ok and snapshot()==before,"failed bake leaves document/history/preview unchanged")
	source.erase("event_template")
	before = snapshot()
	result = tools.update("legacy",{"floors":1,"roof":"flat","width":14.})
	check(result.ok and tools.instances().legacy.baked and tools.instances().legacy.parameters.width==14.,"unfrozen parameter update still generates and freezes new geometry")
	var updated: Array = tools.instances().legacy.parts.values()
	check(same_ids(host.commits.back(),["legacy_a","legacy_b","legacy_c"]+updated) and host.rebuilds==0,"parameter update invalidates complete replacement union without full rebuild")
	check(host._doc.undo() and host._doc.records==before.state.records and host._doc.map_meta==before.state.map_meta,"parameter update undo restores original legacy structure")
	result = tools.generate({"parameters":{"floors":1,"roof":"flat"},"placements":[{"position":[100.,0.,0.]}]})
	check(result.ok and result.building_ids.size()==1 and tools.instances()[result.building_ids[0]].baked,"new generate entry point preserves validation, placement and real bake")
	check(same_ids(host.commits.back(),tools.instances()[result.building_ids[0]].parts.values()) and host.rebuilds==0,"generate entry point commits only generated component UUIDs")
	host.free()
	print("HOUSE_BUILDING_INCREMENTAL_FINISHED checks=",checked," failures=",failed)
	quit(1 if failed else 0)
