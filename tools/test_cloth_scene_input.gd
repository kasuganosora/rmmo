extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var body:=Node3D.new();root.add_child(body)
 body.position=Vector3(4,-.7,2)
 body.rotation.y=.6
 var floor_mesh:=MeshInstance3D.new();floor_mesh.mesh=PlaneMesh.new();root.add_child(floor_mesh)
 floor_mesh.position=Vector3(4,0,2)
 floor_mesh.rotation.z=.15
 var distant:=MeshInstance3D.new();distant.mesh=BoxMesh.new();root.add_child(distant);distant.position=Vector3(100,0,0)
 var runtime=preload("res://scripts/char/character_runtime_cloth.gd").new()
 runtime.configure(body,body);runtime.set_scene_colliders([distant,floor_mesh])
 assert(runtime.scene_colliders==[floor_mesh],"Distant scene collider selected")
 var adapter=preload("res://scripts/char/garment_candidate_cloth.gd").new();body.add_child(adapter)
 adapter.collision_objects=runtime.scene_colliders.duplicate()
 var triangles:PackedVector3Array=adapter._scene_points()
 assert(triangles.size()==6)
 # Root displacement/rotation must not move the world floor with the actor.
 var world_points:PackedVector3Array=[]
 for p:Vector3 in triangles:world_points.append(adapter.global_transform*p)
 body.position.y=-1.2;body.rotation.y=-.8
 var moved:PackedVector3Array=adapter._scene_points()
 for i in moved.size():assert((adapter.global_transform*moved[i]).distance_to(world_points[i])<.00001)
 floor_mesh.position.y=.4
 var raised:PackedVector3Array=adapter._scene_points()
 for i in raised.size():assert((adapter.global_transform*raised[i]).distance_to(world_points[i]+Vector3(0,.4,0))<.00001)
 floor_mesh.free()
 runtime.set_scene_colliders([floor_mesh,distant])
 assert(runtime.scene_colliders.is_empty(),"Unloaded collider retained")
 body.free();distant.free()
 print("PASS scene collider residency and world-to-actor transform under lowered/rotated root and moving furniture")
 quit()
