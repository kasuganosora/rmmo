extends RefCounted
## Application layer: AOI driver init and refresh.

const AoiDriver = preload("res://scripts/asset/aoi_driver.gd")

static func _init_aoi_driver(ctrl) -> void:
	if ctrl._aoi == null:
		ctrl._aoi = AoiDriver.new()
	ctrl._aoi.configure(ctrl.aoi_view_radius_cells, ctrl.aoi_radius_cells, ctrl.aoi_prefetch_radius_cells, ctrl.aoi_refresh_interval_sec)
	ctrl._aoi.reset()
	ctrl._refresh_aoi(true)

static func _refresh_aoi(ctrl, force: bool = false) -> void:
	var am: Node = ctrl._asset_mgr
	if ctrl._aoi == null or am == null:
		return
	if force:
		ctrl._aoi.refresh(ctrl.player, ctrl._npcs, am)
	else:
		ctrl._aoi.tick(0.0, ctrl.player, ctrl._npcs, am, true)

