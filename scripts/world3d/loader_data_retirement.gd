extends RefCounted
## RuntimeMeshCache.read produces CPU values; restore adds exactly one native
## owner field. Keep that boundary explicit instead of scanning a value graph.
static func retain_cooked(data:Dictionary)->void:
	if data.is_empty() or not Thread.is_main_thread() or Engine.get_main_loop()==null:return
	var retirement=preload("res://scripts/world3d/resource_retirement.gd")
	if retirement.existing_service()==null:return
	var cpu:Dictionary=data.duplicate()
	var restored:Array=cpu.get("_restored_meshes",[])
	cpu.erase("_restored_meshes")
	# The input may still be borrowed. Neither it nor its nested arrays may be
	# cleared; only these new outer transfer containers belong to retirement.
	retirement.defer_private_array(restored.duplicate(),true)
	retirement.defer_cpu_values([cpu],0)
