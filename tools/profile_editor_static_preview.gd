extends "res://scripts/world_editor/city_overlay.gd"
## Probe-only recreation of the former stationary-preview road invalidation.
var repeat_road_redraw:=false

func _process(delta:float)->void:
	if repeat_road_redraw and city!=null and not city.pending.is_empty():
		_roads_need_redraw=true
	super._process(delta)
