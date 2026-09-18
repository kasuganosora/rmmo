extends SceneTree
## Headless: resolve quest-tracker nav cell from sample snapshot + world_ctx.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var Util = load("res://scripts/ui/quest_tracker_util.gd")
	failed += _expect(Util != null, "util loaded")

	var world_ctx: Dictionary = {
		"npcs": [
			{"id": "actor_rest", "name": "休息中的少女", "cell": {"x": 15, "y": 10}},
			{"id": "vendor_demo", "name": "杂货商人", "cell": {"x": 13, "y": 10}},
			{"id": "slime", "name": "史莱姆", "cell": {"x": 17, "y": 12}},
		],
		"gather": [
			{
				"id": "herb_a",
				"name": "野生药草",
				"cell": {"x": 10, "y": 22},
				"depleted": false,
				"yields": [{"item_id": "wild_herb", "qty": 1, "weight": 1.0}],
			},
			{
				"id": "herb_dead",
				"name": "枯竭药草",
				"cell": {"x": 1, "y": 1},
				"depleted": true,
				"yields": [{"item_id": "wild_herb", "qty": 1, "weight": 1.0}],
			},
		],
		"fish": [
			{
				"id": "fish_pond_a",
				"name": "小水塘",
				"cell": {"x": 16, "y": 11},
				"depleted": false,
				"yields": [{"item_id": "fish_small", "qty": 1, "weight": 1.0}],
			},
		],
		"warps": [
			{
				"from_cell": {"x": 15, "y": 9},
				"to_map_id": "street_map",
				"to_pack": "res://street_map",
				"message": "前往中央市街",
			},
		],
	}

	# Ready quest → turn-in NPC
	var ready_q: Dictionary = {
		"id": "pond_fishing",
		"title": "池边垂钓",
		"status": "ready",
		"giver": "vendor_demo",
		"turn_in_npc": "vendor_demo",
		"objectives": [{"text": "鲜鱼", "cur": 3, "max": 3, "fish_catch": "any"}],
	}
	var nav_ready: Dictionary = Util.resolve_quest_nav(ready_q, world_ctx)
	failed += _expect(bool(nav_ready.get("ok", false)), "ready ok")
	failed += _expect(nav_ready.get("cell") == Vector2i(13, 10), "ready → vendor cell")
	failed += _expect(str(nav_ready.get("label", "")) == "杂货商人", "ready label vendor")
	failed += _expect(str(nav_ready.get("reason", "")) == "turn_in", "ready reason turn_in")

	# Gather objective → herb POI (skip depleted)
	var herb_q: Dictionary = {
		"id": "herb_gather",
		"title": "采集药草",
		"status": "in_progress",
		"giver": "vendor_demo",
		"turn_in_npc": "vendor_demo",
		"objectives": [
			{
				"text": "采集药草",
				"cur": 2,
				"max": 5,
				"item": "wild_herb",
				"gather": "wild_herb",
				"gather_item": "wild_herb",
			},
		],
	}
	var nav_herb: Dictionary = Util.resolve_quest_nav(herb_q, world_ctx)
	failed += _expect(bool(nav_herb.get("ok", false)), "herb ok")
	failed += _expect(nav_herb.get("cell") == Vector2i(10, 22), "herb → gather cell")
	failed += _expect(str(nav_herb.get("label", "")) == "野生药草", "herb label")
	failed += _expect(str(nav_herb.get("reason", "")) == "gather", "herb reason gather")

	# Fish objective (in progress) → fish POI
	var fish_q: Dictionary = {
		"id": "pond_fishing",
		"title": "池边垂钓",
		"status": "in_progress",
		"giver": "vendor_demo",
		"turn_in_npc": "vendor_demo",
		"objectives": [{"text": "鲜鱼", "cur": 1, "max": 3, "fish_catch": "any"}],
	}
	var nav_fish: Dictionary = Util.resolve_quest_nav(fish_q, world_ctx)
	failed += _expect(bool(nav_fish.get("ok", false)), "fish ok")
	failed += _expect(nav_fish.get("cell") == Vector2i(16, 11), "fish → pond cell")
	failed += _expect(str(nav_fish.get("reason", "")) == "fish", "fish reason")

	# Map-reach → warp from_cell
	var reach_q: Dictionary = {
		"id": "village_trial",
		"title": "村庄的试炼",
		"status": "in_progress",
		"giver": "actor_rest",
		"turn_in_npc": "actor_rest",
		"objectives": [
			{"text": "与村庄长老对话", "cur": 1, "max": 1, "talk": "actor_rest"},
			{"text": "抵达 street_map 入口", "cur": 0, "max": 1, "reach": "street_map", "map_id": "street_map"},
		],
	}
	var nav_reach: Dictionary = Util.resolve_quest_nav(reach_q, world_ctx)
	failed += _expect(bool(nav_reach.get("ok", false)), "reach ok")
	failed += _expect(nav_reach.get("cell") == Vector2i(15, 9), "reach → warp from_cell")
	failed += _expect(str(nav_reach.get("label", "")).find("市街") >= 0, "reach label 市街")
	failed += _expect(str(nav_reach.get("reason", "")) == "reach_warp", "reach reason")

	# Explicit objective cell
	var cell_obj: Dictionary = {
		"text": "抵达标记点",
		"cur": 0,
		"max": 1,
		"cell": {"x": 7, "y": 8},
	}
	var nav_cell: Dictionary = Util.resolve_objective_nav(cell_obj, world_ctx)
	failed += _expect(bool(nav_cell.get("ok", false)), "explicit cell ok")
	failed += _expect(nav_cell.get("cell") == Vector2i(7, 8), "explicit cell coords")

	# Objective index: click fish line on multi-obj quest
	var multi: Dictionary = {
		"id": "multi",
		"status": "in_progress",
		"giver": "vendor_demo",
		"turn_in_npc": "vendor_demo",
		"objectives": [
			{"text": "假人", "cur": 0, "max": 3, "kill": "slime"},
			{"text": "鲜鱼", "cur": 0, "max": 3, "fish_catch": "any"},
		],
	}
	var nav_oi0: Dictionary = Util.resolve_quest_nav(multi, world_ctx, 0)
	failed += _expect(nav_oi0.get("cell") == Vector2i(17, 12), "obj0 → slime")
	var nav_oi1: Dictionary = Util.resolve_quest_nav(multi, world_ctx, 1)
	failed += _expect(nav_oi1.get("cell") == Vector2i(16, 11), "obj1 → fish")

	# Unknown quest with no world match → not ok
	var bare: Dictionary = {
		"id": "orphan",
		"status": "in_progress",
		"giver": "missing_npc",
		"objectives": [{"text": "探索", "cur": 0, "max": 1}],
	}
	var nav_bare: Dictionary = Util.resolve_quest_nav(bare, world_ctx)
	failed += _expect(not bool(nav_bare.get("ok", false)), "unresolvable → ok=false")

	# Live catalog smoke: herb_gather from journal + demo-like ctx
	var QuestJournal = load("res://scripts/net/combat/quest_journal.gd")
	var j = QuestJournal.new()
	j.load_catalog()
	j.clear()
	failed += _expect(j.accept_quest("herb_gather"), "accept herb_gather")
	var live_rows: Array = j.snapshot()
	var live_q: Dictionary = {}
	for row in live_rows:
		if str(row.get("id", "")) == "herb_gather":
			live_q = row
			break
	failed += _expect(not live_q.is_empty(), "live herb in snapshot")
	var nav_live: Dictionary = Util.resolve_quest_nav(live_q, world_ctx)
	failed += _expect(bool(nav_live.get("ok", false)), "live herb nav ok")
	failed += _expect(nav_live.get("cell") == Vector2i(10, 22), "live herb cell")

	if failed == 0:
		print("PASS quest tracker nav")
		quit(0)
	else:
		push_error("FAIL quest tracker nav (%d)" % failed)
		quit(1)


func _expect(cond: bool, msg: String) -> int:
	if cond:
		print("  ok: ", msg)
		return 0
	push_error("FAIL: " + msg)
	print("  FAIL: ", msg)
	return 1
