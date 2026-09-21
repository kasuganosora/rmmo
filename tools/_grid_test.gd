extends SceneTree

func _init() -> void:
	var bad := 0
	var GridUtil = load("res://scripts/util/grid_util.gd")
	if GridUtil == null:
		print("FAIL load grid_util"); quit(); return
	if GridUtil.chebyshev(Vector2i(0, 0), Vector2i(3, 4)) != 4:
		print("FAIL chebyshev"); bad += 1
	if GridUtil.chebyshev_cells(0, 0, 3, 4) != 4:
		print("FAIL chebyshev_cells"); bad += 1
	if GridUtil.manhattan(Vector2i(0, 0), Vector2i(3, 4)) != 7:
		print("FAIL manhattan"); bad += 1
	if not GridUtil.adjacent(Vector2i(0, 0), Vector2i(1, 1)):
		print("FAIL adjacent diag"); bad += 1
	if GridUtil.adjacent(Vector2i(0, 0), Vector2i(0, 0)):
		print("FAIL adjacent self"); bad += 1
	if GridUtil.adjacent(Vector2i(0, 0), Vector2i(2, 0)):
		print("FAIL adjacent far"); bad += 1
	# Wrappers still resolve to GridUtil.
	var NameplateUtil = load("res://scripts/game/nameplate_util.gd")
	var MobAI = load("res://scripts/net/combat/mob_ai.gd")
	var AoiDriver = load("res://scripts/asset/aoi_driver.gd")
	if NameplateUtil == null or NameplateUtil.chebyshev(Vector2i(0, 0), Vector2i(3, 5)) != 5:
		print("FAIL NameplateUtil.chebyshev"); bad += 1
	if MobAI == null or MobAI.chebyshev(Vector2i(0, 0), Vector2i(3, 5)) != 5:
		print("FAIL MobAI.chebyshev"); bad += 1
	if AoiDriver == null or AoiDriver.chebyshev(Vector2i(0, 0), Vector2i(3, 5)) != 5:
		print("FAIL AoiDriver.chebyshev"); bad += 1
	print("GRID_OK=", bad == 0, " bad=", bad)
	quit()
