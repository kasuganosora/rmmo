extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var model:=Model.new();model.body_type="female";model.appearance={"body_model":"female_base_v2","part_ids":{"FrontHair1":201}}
	root.add_child(model);model.set_process(false)
	var body:Node3D=model.axis_rig.body
	var spring:RefCounted=model.axis_rig.hair.spring
	assert(spring.contacts.size()==12)
	var results:Array=[]
	for enabled in [false,true]:
		body.set_angles(body.POSES.stand)
		spring.set_enabled(true);spring.set_contacts_enabled(enabled)
		var max_depth:=0.0;var intersections:=0;var samples:=0
		for frame in 110:
			var pose:Dictionary=body.POSES.stand.duplicate()
			var phase:float=clampf((frame-20)/40.0,0,1)*TAU
			pose.head=Vector3(20*sin(phase),35*sin(phase),0)
			body.set_angles(pose)
			# Negative-control measurement still needs current collider geometry,
			# even though production skips updates for disabled contacts.
			spring.sync_contacts(body,true)
			await process_frame
			if frame<20:continue
			for simulator:SpringBoneSimulator3D in spring.simulators:
				var skeleton:Skeleton3D=simulator.get_parent()
				if not spring.snapshots.has(skeleton.get_instance_id()):continue
				var poses:Array=spring.snapshots[skeleton.get_instance_id()]
				for chain in simulator.setting_count:
					for joint in range(1,simulator.get_joint_count(chain)):
						var point:Vector3=skeleton.global_transform*poses[simulator.get_joint_bone(chain,joint)].origin
						for contact:Dictionary in spring.contacts:
							var capsule:SpringBoneCollisionCapsule3D=contact.node
							if capsule.get_parent()!=simulator:continue
							var p:Vector3=capsule.global_transform.affine_inverse()*point
							var half:float=maxf(0,capsule.height*.5-capsule.radius)
							var closest:=Vector3(0,clampf(p.y,-half,half),0)
							var depth:float=capsule.radius+simulator.get_joint_radius(chain,joint)-p.distance_to(closest)
							max_depth=maxf(max_depth,depth);samples+=1
							if depth>.001:intersections+=1
		results.append({"enabled":enabled,"max_particle_depth_m":max_depth,"over_1mm":intersections,"samples":samples})
	var folder:String=Art.review_path("character_3d/source_hair_contacts_01");DirAccess.make_dir_recursive_absolute(folder)
	var file:=FileAccess.open(folder+"/particle_audit.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"\t"));file.close()
	print("CONTACT RESULTS ",JSON.stringify(results))
	var improved:bool=results[1].over_1mm<results[0].over_1mm and results[1].max_particle_depth_m<results[0].max_particle_depth_m
	model.free()
	for frame in 3:await process_frame
	print("PASS particle contact negative control improved" if improved else "FAIL particle contact effect; inspect saved results")
	quit(0 if improved else 1)
