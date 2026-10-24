extends "res://tools/test_house_geometry_identity_reuse.gd"
## Reproduce a detailed render mesh paired with a small authored collider.
func run()->void:
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	preload("res://scripts/world3d/prefab_binary_cache.gd").enabled=false
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	controls.enable_white_materials();controls.discard_map_textures=true
	var data:=fixture();data.meshes.append(data.meshes[0].duplicate(true))
	data.entries[0][1]=[0,1]
	var indices:=PackedInt32Array();indices.resize(240000)
	for i in indices.size():indices[i]=i%3
	data.meshes[0].surfaces[0][Mesh.ARRAY_INDEX]=indices
	var value:=encode(data);var source:=record(value)
	var prepared:=House.prepare_cpu(source,{},true)
	var partial:Dictionary=House._decoded[value.sha256]
	check(prepared.collision_faces[0].is_empty() and prepared.collision_faces[1].size()==3,"cold reference preparation skips the unused render triangle soup")
	check(House._decoded_bytes==int(value.length)+3*12+2*16,"only actual face storage is charged, including empty slot overhead")
	check(House.publish_prepared(source,prepared),"partial faces publish complete render geometry and collision input")
	var visual:=House.visual(source,false)
	check(visual.get_meta("collision_solid")==House.geometry(source).source,"physics uses the authored collision source")
	var spec:=preload("res://scripts/world3d/world_stream.gd")._spec(visual,Transform3D.IDENTITY)
	check(spec.collision_mesh==visual.get_meta("collision_solid") and preload("res://scripts/world3d/world_navigation.gd")._source_geometry(spec)==spec.collision_mesh,"production stream and navigation select the prepared collider")
	check(visual.mesh._collision_faces.is_empty() and visual.mesh.surfaces[0][Mesh.ARRAY_INDEX]==indices,"render topology remains complete without its unused face cache")
	var original_faces:PackedVector3Array=prepared.collision_faces[1].duplicate()
	var other_job:=House.prepare_cpu(source,{},true)
	other_job.collision_faces[1][0]=Vector3(99,99,99)
	check(House.prepare_cpu(source,{},true).collision_faces[1]==original_faces,"partial preparation still owns independent packed storage")
	var full:=House.prepare_cpu(source)
	check(full.collision_faces[0].size()==240000 and full.collision_faces[1]==original_faces,"a generic caller lazily upgrades every missing face slot")
	check(House.publish_prepared(source,full) and visual.mesh._collision_faces==full.collision_faces[0],"a full prepared packet upgrades an already published partial mesh")
	check(partial.collision_faces[0].is_empty() and partial.collision_face_slots.size()==1 and is_same(partial.data,House._decoded[value.sha256].data),"upgrade preserves old snapshots and reuses decoded arrays")
	check(House._decoded_bytes==int(value.length)+240003*12+2*16,"upgrade replaces accounting instead of double charging")
	visual.free();House.evict_geometry({value.sha256:true})
	var early:=House.geometry(source)
	check(early.source._collision_faces.is_empty(),"early geometry cache has no prepared collision faces")
	var late:=House.prepare_cpu(source,{},true)
	check(House.publish_prepared(source,late) and early.source._collision_faces==original_faces,"late preparation installs faces into an existing geometry owner")
	House.evict_geometry({value.sha256:true})
	# Different definitions with identical geometry/material owners share their
	# render mesh. Installation must target the surviving alias, not the throwaway.
	House.publish_prepared(source,House.prepare_cpu(source,{},true))
	var alias_mesh:Mesh=House.geometry(source).mesh
	var variant:=data.duplicate(true);variant.entries[0][0]=["variant"]
	var variant_value:=encode(variant);var variant_source:=record(variant_value,"variant")
	var variant_full:=House.prepare_cpu(variant_source)
	check(House.publish_prepared(variant_source,variant_full),"second definition publishes shared render geometry")
	check(House.geometry(variant_source).mesh==alias_mesh and alias_mesh._collision_faces==variant_full.collision_faces[0],"render alias retains the prepared faces after canonicalization")
	House.evict_geometry({value.sha256:true,variant_value.sha256:true})
	# Mixed concurrent requests must never return a partial packet to a full
	# consumer, irrespective of which decode/upgrade flight wins the race.
	var ready:=Semaphore.new();var start:=Semaphore.new();var workers:Array=[]
	for i in 6:
		var selected:bool=i%2==0;var worker:=Thread.new()
		worker.start(func():ready.post();start.wait();return House.prepare_cpu(source,{},selected));workers.append(worker)
	for i in workers.size():ready.wait()
	for i in workers.size():start.post()
	for i in workers.size():
		var result:Dictionary=workers[i].wait_to_finish()
		check(result.collision_faces[1]==original_faces and result.collision_faces[0].size()==(0 if i%2==0 else 240000),"mixed worker receives its complete requested faces "+str(i))
	House.evict_geometry({value.sha256:true})
	var trials:Array=[]
	for selected:bool in [false,true,true,false]:
		House.source_collision_faces_enabled=selected
		var began:=Time.get_ticks_usec();var vertices:=0
		for i in 12:
			evict(value.sha256)
			var result:=House.prepare_cpu(source,{},true);vertices+=result.face_work.prepared_vertices
		trials.append({"selected":selected,"cold_preparations":12,"us":Time.get_ticks_usec()-began,"face_vertices":vertices})
	House.source_collision_faces_enabled=true;House.evict_geometry({value.sha256:true})
	controls.discard_map_textures=false
	check(House.prepare_cpu(source,{},true).collision_faces[0].size()==240000,"ordinary material path keeps its prior face policy")
	House.evict_geometry({value.sha256:true});controls.discard_map_textures=true
	# Some prefabs use one mesh for both roles; selection must not omit it.
	var shared:=fixture();var shared_value:=encode(shared)
	check(House.prepare_cpu(record(shared_value),{},true).collision_faces[0].size()==3,"shared render/collision slot remains ready")
	House.evict_geometry({shared_value.sha256:true})
	check(House._decoded_bytes==0 and House._decoding.is_empty(),"eviction releases partial/full owners and flights")
	print("PREFAB_SELECTED_FACES ",JSON.stringify({"trials":trials,"failures":failures}))
	quit(1 if failures else 0)
