extends SceneTree
## Headless: build radar POI marker list from sample data; assert kinds/counts.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var Util = load("res://scripts/ui/radar_poi.gd")
	failed += _expect(Util != null, "radar_poi loaded")

	failed += _expect(Util.color_for_kind(Util.KIND_QUEST) == Util.COLOR_QUEST, "quest yellow")
	failed += _expect(Util.color_for_kind(Util.KIND_INN) == Util.COLOR_INN, "inn cyan")
	failed += _expect(Util.color_for_kind(Util.KIND_SMITH) == Util.COLOR_SMITH, "smith orange")
	failed += _expect(Util.color_for_kind(Util.KIND_GATHER) == Util.COLOR_GATHER, "gather green")
	failed += _expect(Util.color_for_kind(Util.KIND_FISH) == Util.COLOR_FISH, "fish blue")
	failed += _expect(Util.color_for_kind(Util.KIND_PIN) == Util.COLOR_PIN, "pin magenta")
	failed += _expect(Util.color_for_kind(Util.KIND_BOSS) == Util.COLOR_BOSS, "boss purple")

	var sample: Dictionary = {
		"npcs": [
			{"id": "actor_rest", "cell": {"x": 15, "y": 10}, "quest_offers": 2},
			{"id": "vendor_demo", "cell": {"x": 13, "y": 10}, "quest_offer": true},
			{"id": "innkeeper", "cell": {"x": 12, "y": 12}, "inn_rest": true},
			{"id": "blacksmith", "cell": {"x": 14, "y": 12}, "blacksmith": true},
			{"id": "repair_guy", "cell": {"x": 9, "y": 9}, "repair": true},
			{"id": "plain_npc", "cell": {"x": 1, "y": 1}},
		],
		"gather": [
			{"id": "herb_a", "cell": {"x": 10, "y": 22}, "depleted": false},
			{"id": "herb_b", "cell": {"x": 8, "y": 22}, "depleted": true},
			{"id": "herb_c", "cell": {"x": 11, "y": 21}},
		],
		"fish": [
			{"id": "fish_pond_a", "cell": {"x": 16, "y": 11}, "depleted": false},
			{"id": "fish_pond_b", "cell": {"x": 18, "y": 11}, "depleted": true},
		],
		"pins": [
			{"id": "pin_1", "name": "标记1", "cell": {"x": 5, "y": 5}},
		],
	}

	var markers: Array = Util.build_markers(sample)
	var counts: Dictionary = Util.count_by_kind(markers)

	failed += _expect(int(counts.get(Util.KIND_QUEST, 0)) == 2, "quest count 2")
	failed += _expect(int(counts.get(Util.KIND_INN, 0)) == 1, "inn count 1")
	failed += _expect(int(counts.get(Util.KIND_SMITH, 0)) == 2, "smith count 2 (blacksmith+repair)")
	failed += _expect(int(counts.get(Util.KIND_GATHER, 0)) == 2, "gather count 2 (skip depleted)")
	failed += _expect(int(counts.get(Util.KIND_FISH, 0)) == 1, "fish count 1 (skip depleted)")
	failed += _expect(int(counts.get(Util.KIND_PIN, 0)) == 1, "pin count 1")
	failed += _expect(markers.size() == 9, "total markers 9")

	# Depleted ids must not appear.
	var ids: Dictionary = {}
	for m in markers:
		ids[str(m.get("id", ""))] = true
	failed += _expect(not ids.has("herb_b"), "herb_b depleted hidden")
	failed += _expect(not ids.has("fish_pond_b"), "fish_pond_b depleted hidden")
	failed += _expect(not ids.has("plain_npc"), "plain npc not a POI")

	# Quest priority over inn if both set.
	var both: Array = Util.build_markers({
		"npcs": [{"id": "inn_q", "cell": {"x": 0, "y": 0}, "inn_rest": true, "quest_offer": true}],
		"gather": [],
		"fish": [],
	})
	failed += _expect(both.size() == 1, "priority single marker")
	failed += _expect(str(both[0].get("kind", "")) == Util.KIND_QUEST, "quest beats inn")


	# World boss POI: alive shows, depleted/dead hides.
	var boss_alive: Array = Util.build_markers({
		"npcs": [{"id": "world_boss_king", "name": "森林霸主", "cell": {"x": 24, "y": 17}, "world_boss": true}],
		"bosses": [],
	})
	failed += _expect(boss_alive.size() == 1 and str(boss_alive[0].get("kind", "")) == Util.KIND_BOSS, "boss alive POI")
	var boss_dead: Array = Util.build_markers({
		"npcs": [{"id": "world_boss_king", "cell": {"x": 24, "y": 17}, "world_boss": true, "depleted": true}],
		"bosses": [{"id": "boss_b", "cell": {"x": 1, "y": 1}, "dead": true}],
	})
	failed += _expect(boss_dead.is_empty(), "boss dead/depleted hidden")

	var legend: Array = Util.legend()
	failed += _expect(legend.size() == 7, "legend 7 kinds")
	failed += _expect(Util.legend_text().find("任务") >= 0, "legend text has 任务")
	failed += _expect(Util.legend_text().find("标记") >= 0, "legend text has 标记")

	# classify helpers
	failed += _expect(Util.classify_npc({"inn_rest": true}) == Util.KIND_INN, "classify inn")
	failed += _expect(Util.classify_npc({"blacksmith": true}) == Util.KIND_SMITH, "classify smith")
	failed += _expect(Util.classify_npc({"is_gather": true}) == Util.KIND_GATHER, "classify gather")
	failed += _expect(Util.classify_npc({"is_fish": true}) == Util.KIND_FISH, "classify fish")
	failed += _expect(Util.classify_npc({"world_boss": true}) == Util.KIND_BOSS, "classify boss")
	failed += _expect(Util.classify_npc({}) == "", "classify empty")


	# Big map (map_overview) helper must consume the same markers / colors (no fork).
	var MapOverview = load("res://scripts/ui/map_overview.gd")
	failed += _expect(MapOverview != null, "map_overview loaded")
	var big_markers: Array = MapOverview.poi_markers_from_sample(sample)
	failed += _expect(big_markers.size() == markers.size(), "big map same marker count")
	var big_counts: Dictionary = Util.count_by_kind(big_markers)
	failed += _expect(big_counts == counts, "big map same kind counts")
	# Depleted still hidden via shared builder.
	var big_ids: Dictionary = {}
	for bm in big_markers:
		big_ids[str(bm.get("id", ""))] = true
	failed += _expect(not big_ids.has("herb_b"), "big map herb_b depleted hidden")
	failed += _expect(not big_ids.has("fish_pond_b"), "big map fish_pond_b depleted hidden")
	# Colors match radar_poi table (same values via shared builder).
	var color_ok := true
	for bm2 in big_markers:
		var k2 := str(bm2.get("kind", ""))
		if bm2.get("color") != Util.color_for_kind(k2):
			color_ok = false
			break
	failed += _expect(color_ok and not big_markers.is_empty(), "big map colors match radar_poi")
	# Instance set_poi_markers stores list for draw.
	var ov = MapOverview.new()
	ov.set_poi_markers(big_markers)
	failed += _expect(int(ov.poi_marker_count()) == big_markers.size(), "overview stores markers")
	ov.free()

	if failed == 0:
		print("test_radar_poi: PASS")
		quit(0)
	else:
		print("test_radar_poi: FAIL %d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
