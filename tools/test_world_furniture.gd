extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(160).timeout.connect(func():push_error("Furniture timeout");quit(2))
 var session=root.get_node("GameSession");var server=root.get_node("MockServer")
 session.selected_character={"id":-401,"name":"Seat test","gender":"female","customization":{"body_model":"female_base_v2","part_ids":{"FrontHair1":0}}}
 session.spawn_data={}
 var folder:String=preload("res://scripts/world3d/map_paths.gd").cache_directory("seat_%d"%Time.get_ticks_usec())
 var doc=preload("res://scripts/world3d/world_document.gd").new()
 doc.add_box("floor",Vector3(0,-.1,0),Vector3(12,.2,12))
 var uuid:String=doc.add_seat(Vector3(0,.46,0),Vector2(.55,.55),45)
 var path:String=folder.path_join("map.gltf");assert(doc.save(path)==OK)
 session.world3d_map_path=path;session.world3d_spawn=Vector3(0,.9,1.1)
 var world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
 while not world.is_world_ready():await process_frame
 await physics_frame
 var player=world._player;player.set_physics_process(false)
 var model=player._model;model.set_process(false)
 var chair:StaticBody3D
 for child in world.get_children():
  if str(child.get_meta("uuid",""))==uuid:chair=child
 assert(chair!=null and chair.has_meta("seat"),"Map save/load/stream dropped seat metadata")
 var original:Vector3=player.global_position
 assert(server.furniture.reserve(path,uuid,"other"))
 assert(not world.furniture.interact(chair),"Occupied seat accepted")
 server.furniture.release(path,uuid,"other")
 var key:=InputEventKey.new();key.keycode=KEY_E;key.pressed=true
 world._unhandled_input(key)
 assert(world.furniture.active() and server.sitting and model.action=="sit_chair","Normal E interaction failed")
 assert(is_equal_approx(player.rotation.y,PI/4))
 var target:Vector3=chair.to_global(Vector3(0,.02,0))
 assert(model.to_global(model.axis_rig.seat.top).distance_to(target)<.00001)
 var reference:Vector3=model.axis_rig.animations.reference_position(model.skeleton,"sit_chair_hold","hip")
 model.play("sit_chair_hold","front",true);model.pose_at(0)
 var hip:Vector3=model.rig.transform*model.axis_rig.body.get_solved_bone_pose(model.skeleton.find_bone("hip")).origin
 assert(Vector2(hip.x-reference.x,hip.z-reference.z).length()<.001,"Reference FK differs from rendered skeleton")
 model._process(1.0/60)
 await RenderingServer.frame_post_draw
 assert(model.axis_rig.seat.seat_vertices.size()>0)
 var lowest:=INF
 for index in model.axis_rig.seat.seat_vertices:
  lowest=minf(lowest,(model.rig.transform*(model.axis_rig.body.posed_points[index]+model.axis_rig.body.root_offset)).y)
 assert(absf(lowest-model.axis_rig.seat.top.y)<.01,"Actual seated body did not reach authored surface")
 world._on_movement_intent()
 assert(model.action=="stand_up_chair" and not server.sitting)
 model._process(model.action_duration()+.2);world.furniture.tick()
 assert(not world.furniture.active() and not model.axis_rig.seat.enabled and player.global_position.distance_to(original)<.001)
 assert(server.furniture.occupants.is_empty())
 assert(world.furniture.interact(chair))
 world.apply_actions([{"type":"sit","on":false}])
 assert(model.action=="stand_up_chair")
 world.furniture.cancel()
 assert(world.furniture.interact(chair))
 world._combat._apply({"actions":[{"type":"damage","target":"player","amount":1}]})
 assert(model.action=="stand_up_chair" and not server.sitting,"Damage failed to interrupt furniture rest")
 world.furniture.cancel()
 assert(world.furniture.interact(chair))
 chair.position.x+=.1;world.furniture.tick()
 assert(not world.furniture.active() and not server.sitting,"Moving seat retained stale attachment")
 assert(world.furniture.interact(chair))
 world.apply_actions([{"type":"player_died"}])
 assert(not world.furniture.active() and model.action=="death")
 player.input_locked=false;server.awaiting_respawn=false
 model.play("idle","front",true)
 assert(world.furniture.interact(chair))
 chair.queue_free();await process_frame;world.furniture.tick()
 assert(not world.furniture.active() and server.furniture.occupants.is_empty())
 # Explicit far/tilted/malformed seats are rejected without reservation.
 var bad:=StaticBody3D.new();world.add_child(bad);bad.set_meta("uuid","bad")
 bad.set_meta("seat",{"surface":[0,0,0],"size":[.5,.5]});bad.position=Vector3(20,.5,0)
 assert(not world.furniture.interact(bad))
 bad.position=Vector3(0,.5,0);bad.rotation.x=.3
 assert(not world.furniture.interact(bad))
 bad.rotation=Vector3.ZERO;bad.set_meta("seat",{"surface":[0,NAN,0],"size":[.5,.5]})
 assert(not world.furniture.interact(bad))
 bad.free()
 assert(await world.transfer_map(path,Vector3(0,.9,1.1)))
 player.set_physics_process(false);model.set_process(false)
 for child in world.get_children():
  if str(child.get_meta("uuid",""))==uuid:chair=child
 await physics_frame
 assert(world.furniture.interact(chair))
 assert(await world.transfer_map(path,Vector3(0,.9,1.1)))
 assert(not world.furniture.active() and not server.sitting and server.furniture.occupants.is_empty())
 player.set_physics_process(false);model.set_process(false)
 for child in world.get_children():
  if str(child.get_meta("uuid",""))==uuid:chair=child
 await physics_frame
 assert(world.furniture.interact(chair))
 world.free();await process_frame
 assert(server.furniture.occupants.is_empty() and not server.sitting,"World exit leaked seat occupancy")
 preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(folder)
 print("PASS seat save/load/E, actual seat contact, occupancy, source/yaw alignment, movement, damage, death, move/remove, malformed rejection, transfer and exit cleanup")
 quit()
