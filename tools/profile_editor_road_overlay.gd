extends "res://scripts/world_editor/city_overlay.gd"
## Probe-only wrapper; extra per-call clocks are never enabled in the editor.
var _inside_roads := false
var hoisted_cull := false

func check_hoist() -> bool:
	for id: String in _road_bounds:
		if super.road_in_view(id)!=_hoisted_cull(id): return false
	return true

func _hoisted_cull(id: String) -> bool:
	if not _road_bounds.has(id): return false
	var box: AABB=_road_bounds[id]
	var center:=box.get_center(); var extent:=box.size*.5
	var fringe: float=maxf(.01,center.distance_to(city.editor._camera.global_position)*.02)
	for plane: Plane in _frustum:
		if plane.distance_to(center)>plane.normal.abs().dot(extent)+fringe: return false
	return true

func _init() -> void:
	for key in ["road_cull_detail", "road_project_detail"]:
		profile_cpu_us[key]=0; profile_calls[key]=0

func draw_roads() -> void:
	_inside_roads=true
	super.draw_roads()
	_inside_roads=false

func road_in_view(id: String) -> bool:
	var measured:=Time.get_ticks_usec()
	var result:=_hoisted_cull(id) if hoisted_cull else super.road_in_view(id)
	_profile_end("road_cull_detail",measured)
	return result

func project(points: Array) -> PackedVector2Array:
	if not _inside_roads: return super.project(points)
	var measured:=Time.get_ticks_usec()
	var result:=super.project(points)
	_profile_end("road_project_detail",measured)
	return result
