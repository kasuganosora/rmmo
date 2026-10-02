extends Node3D
## Receivers are scoped to this World3D, including isolated editor playtest worlds.
const Response = preload("res://scripts/world3d/wind_response.gd")
const Materials = preload("res://scripts/world3d/wind_material.gd")
var camera: Camera3D
var receivers := {}
var scan_left := 0.0
var velocity := Vector3.ZERO
var elapsed := 0.0

func _physics_process(delta: float) -> void:
	scan_left -= delta
	if scan_left > 0 or not is_instance_valid(camera): return
	scan_left = .35
	refresh()

func refresh() -> void:
	var alive := {}
	for node in get_tree().get_nodes_in_group(Response.GROUP):
		if not node is MeshInstance3D or node.get_world_3d() != get_world_3d() or not node.is_visible_in_tree(): continue
		if node.global_position.distance_squared_to(camera.global_position) > 90*90: continue
		var id := node.get_instance_id(); alive[id] = true
		if not receivers.has(id): _bind(node)
		if receivers.has(id):
			var row: Dictionary = receivers[id]
			row.exposure = 1.0
			if row.config.shelter:
				var bounds: AABB = node.global_transform * node.get_aabb()
				var top := Vector3(bounds.get_center().x,bounds.end.y+.05,bounds.get_center().z)
				var query := PhysicsRayQueryParameters3D.create(top,top+Vector3.UP*180,1)
				if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): row.exposure = 0.0
	for id in receivers.keys():
		if not alive.has(id): _restore(receivers[id]); receivers.erase(id)
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
	for row: Dictionary in receivers.values():
		for material: ShaderMaterial in row.materials:
			material.set_shader_parameter("wind_velocity",wind*float(row.exposure))
			material.set_shader_parameter("wind_time",time)

func _restore(row: Dictionary) -> void:
	var node: MeshInstance3D = row.node.get_ref()
	if node == null: return
	node.material_override = row.original.override
	for slot in mini(node.mesh.get_surface_count(),row.original.surfaces.size()): node.set_surface_override_material(slot,row.original.surfaces[slot])
	node.extra_cull_margin = row.original.margin; node.remove_meta("wind_original")

func _exit_tree() -> void:
	for row in receivers.values(): _restore(row)
	receivers.clear()
