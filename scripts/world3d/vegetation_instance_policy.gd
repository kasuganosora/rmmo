extends RefCounted
## Cutout MultiMeshes are an interior, distant-view optimization. Native LOD,
## occlusion and screen-edge decisions always stay with individual instances.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const NEAR_DISTANCE=48.
const MIN_MEMBERS=128
const MAX_ACTIVE_MEMBERS=4096

static func is_cutout(node:MeshInstance3D)->bool:
	for slot in node.mesh.get_surface_count():
		var material:Material=node.get_active_material(slot)
		if material is StandardMaterial3D and material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:return true
	return false

static func preserves_lods(mesh:Mesh)->bool:
	for lods:Dictionary in Cpu.capture(mesh).lods:
		if not lods.is_empty():return false
	return true

static func can_instance(bounds:AABB,camera:Camera3D)->bool:
	if not is_instance_valid(camera) or (camera.get_viewport().use_occlusion_culling or camera.get_viewport().use_xr):return false
	if bounds.get_center().distance_to(camera.global_position)<NEAR_DISTANCE+bounds.size.length()*.5:return false
	# All corners inside all camera planes. At an edge, use original engine
	# instances rather than amplifying submitted leaf geometry with a common AABB.
	for plane:Plane in camera.get_frustum():
		for i in 8:
			if plane.is_point_over(bounds.get_endpoint(i)):return false
	return true

static func profitable(cpu_ms:float,gpu_ms:float)->bool:
	# No timing support, small stands and GPU-bound views stay on engine draws.
	return cpu_ms>.5 and gpu_ms>0 and cpu_ms>gpu_ms*2.
