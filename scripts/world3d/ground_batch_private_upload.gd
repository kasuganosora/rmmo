extends RefCounted
## Private layered materials, retained by the existing batch worker lease.
## No additional worker, result queue, texture upload, or geometry copy.
const Geometry=preload("res://scripts/world3d/ground_batch_geometry.gd")
const Streaming=preload("res://scripts/world3d/streaming_surface_shader.gd")

static func snapshot(members:Array)->Array:
	assert(Thread.is_main_thread())
	# Standard materials remain shared live owners. Their lazy shader/RID
	# mutation is not safe to race across workers; preserve their current path.
	for source:Dictionary in members:
		for material:Material in source.materials:
			if not material is ShaderMaterial or not Streaming.is_terrain(material.shader) or material.next_pass!=null:return []
	var copies:Dictionary={};var result:Array=[]
	for source:Dictionary in members:
		var copy:Dictionary=source.duplicate();copy.materials=[]
		# Grouping already proved these keys equivalent. Images excluded from
		# that key are per-source layers, not a reason to clone another material.
		copy.private_height_image=source.materials[0].get_meta("terrain_height_image") if source.materials[0].has_meta("terrain_height_image") else null
		copy.private_ground_mask=source.materials[0].get_meta("ground_mask_image") if source.materials[0].has_meta("ground_mask_image") else null
		for slot:int in source.materials.size():
			var key:String=source.keys[slot]
			if not copies.has(key):copies[key]=source.materials[slot].duplicate()
			copy.materials.append(copies[key])
		result.append(copy)
	if not result.is_empty():result[0].private_upload_material_copies=copies.size()
	return result

static func build(members:Array,origin:Vector3)->Dictionary:
	assert(not Thread.is_main_thread())
	var began:=Time.get_ticks_usec()
	var data:=Geometry.build(members,origin,true)
	var built:=Time.get_ticks_usec()
	data.private_layered_materials=true
	var output:=Geometry.upload_private(data)
	output.private_upload_info={"surfaces":data.get("prepared_surface_count",0),"surface_prepare_us":data.get("surface_prepare_us",0),"build_us":built-began,"upload_us":Time.get_ticks_usec()-built,"thread":OS.get_thread_caller_id()}
	output.batch_worker_interval=[began,Time.get_ticks_usec()]
	return output
