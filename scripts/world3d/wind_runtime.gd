extends Node3D
## Receivers are scoped to this World3D, including isolated editor playtest worlds.
const Response = preload("res://scripts/world3d/wind_response.gd")
const Materials = preload("res://scripts/world3d/wind_material.gd")
var camera: Camera3D
var receivers := {}
var scan_left := 0.0
var velocity := Vector3.ZERO
var elapsed := 0.0
var active_rows: Array = []
var range_camera_position := Vector3(INF,INF,INF)

func _physics_process(delta: float) -> void:
	scan_left -= delta
	if scan_left > 0 or not is_instance_valid(camera): return
	scan_left = .35
	refresh()

func refresh() -> void:
	var alive := {}
	active_rows.clear()
	for node in get_tree().get_nodes_in_group(Response.GROUP):
		if not node is MeshInstance3D or node.get_world_3d() != get_world_3d() or not node.is_visible_in_tree(): continue
		if node.global_position.distance_squared_to(camera.global_position) > 90*90: continue
		var id := node.get_instance_id(); alive[id] = true
		if not receivers.has(id): _bind(node)
		if receivers.has(id):
			var row: Dictionary = receivers[id]
			# Keep bindings warm across LOD boundaries, but hidden levels need
			# neither shelter queries nor per-frame uniform updates.
			if not _range_active(node): continue
			active_rows.append(row)
			row.exposure = 1.0
			if row.config.shelter:
				var bounds: AABB = node.global_transform * node.get_aabb()
				var top := Vector3(bounds.get_center().x,bounds.end.y+.05,bounds.get_center().z)
				var query := PhysicsRayQueryParameters3D.create(top,top+Vector3.UP*180,1)
				if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): row.exposure = 0.0
	for id in receivers.keys():
		if not alive.has(id): _restore(receivers[id]); receivers.erase(id)
	if is_instance_valid(camera): range_camera_position = camera.global_position
	advance(velocity,elapsed)

func _bind(node: MeshInstance3D) -> void:
	var error := Response.mesh_error(node)
	if not error.is_empty(): node.set_meta("wind_error",error); return
	var config: Dictionary = Response.defaults().merged(node.get_meta("extras").rmmo_wind,true)
	var original := {"override":node.material_override,"surfaces":[],"margin":node.extra_cull_margin}
	var materials: Array[ShaderMaterial] = []
	for slot in node.mesh.get_surface_count():
		original.surfaces.append(node.get_surface_override_material(slot))
		materials.append(Materials.make(node.get_active_material(slot),config,node.get_aabb()))
	node.set_meta("wind_original",original); node.material_override = null
	for slot in materials.size(): node.set_surface_override_material(slot,materials[slot])
	node.extra_cull_margin = maxf(node.extra_cull_margin,config.amplitude*3)
	receivers[node.get_instance_id()] = {"node":weakref(node),"original":original,"materials":materials,"config":config,"exposure":1.0}

func advance(wind: Vector3, time: float) -> void:
	velocity = wind; elapsed = time
	# A sub-metre camera cache stays safely inside the extra 1 m guard band.
	if is_instance_valid(camera) and camera.global_position.distance_squared_to(range_camera_position) > .25*.25: _update_active_rows()
	for row: Dictionary in active_rows:
		var force := wind*float(row.exposure)
		var force_changed: bool = row.get("last_velocity",Vector3(INF,INF,INF)) != force
		for material: ShaderMaterial in row.materials:
			if force_changed: material.set_shader_parameter("wind_velocity",force)
			material.set_shader_parameter("wind_time",time)
		row.last_velocity = force

func _update_active_rows() -> void:
	active_rows.clear()
	if is_instance_valid(camera): range_camera_position = camera.global_position
	for row: Dictionary in receivers.values():
		var node: MeshInstance3D = row.node.get_ref()
		if node != null and _range_active(node): active_rows.append(row)

func _range_active(node: MeshInstance3D) -> bool:
	if not is_instance_valid(camera): return true
	var begin := node.visibility_range_begin
	var end := node.visibility_range_end
	if begin == 0.0 and end == 0.0: return true
	# Same transformed AABB center as renderer range tests. Keep both levels
	# updating within the hysteresis band so a camera crossing never freezes.
	var bounds := node.custom_aabb
	if bounds.size == Vector3.ZERO: bounds = node.get_aabb()
	var distance := camera.global_position.distance_to(node.global_transform * bounds.get_center())
	return (begin == 0.0 or distance >= begin-node.visibility_range_begin_margin-1.0) and (end == 0.0 or distance <= end+node.visibility_range_end_margin+1.0)

func _restore(row: Dictionary) -> void:
	var node: MeshInstance3D = row.node.get_ref()
	if node == null: return
	node.material_override = row.original.override
	for slot in mini(node.mesh.get_surface_count(),row.original.surfaces.size()): node.set_surface_override_material(slot,row.original.surfaces[slot])
	node.extra_cull_margin = row.original.margin; node.remove_meta("wind_original")

func _exit_tree() -> void:
	for row in receivers.values(): _restore(row)
	receivers.clear()
	active_rows.clear()
