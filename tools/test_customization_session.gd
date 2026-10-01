extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(90).timeout.connect(func():push_error("Customization session timeout");quit(2))
 var server=root.get_node("MockServer")
 server.login("shape_isolation","test","local");await server.login_finished
 var input:Dictionary={"body_model":"female_base_v2","body_shapes":{"height":-.4,"hip_size":999,"nose_width":NAN,"unknown":1},"part_ids":{"FrontHair1":202}}
 var custom=Customization.from_dict(input)
 input.part_ids.FrontHair1=201
 assert(custom.part_ids.FrontHair1==202)
 var output:Dictionary=custom.to_dict();output.part_ids.FrontHair1=203
 assert(custom.part_ids.FrontHair1==202)
 server.create_character("ShapeA","warrior","1","female",input)
 input.body_shapes.height=.9;input.part_ids.FrontHair1=0
 var created:Array=await server.character_created;assert(created[0])
 var id:int=created[2].id
 assert(created[2].customization.body_shapes=={"height":-.4,"hip_size":1.0})
 created[2].customization.body_shapes.height=.8
 server.fetch_characters();var rows:Array=await server.characters_ready
 assert(rows[0].customization.body_shapes.height==-.4)
 assert(rows[0].customization.part_ids.FrontHair1==201)
 rows[0].customization.part_ids.FrontHair1=0
 server.create_character("ShapeB","warrior","1","female",{"body_shapes":{"height":.6}})
 var second:Array=await server.character_created;assert(second[0])
 server.enter_world3d(id);var first_world:Array=await server.enter_world_ready;assert(first_world[0])
 first_world[2].character.customization.body_shapes.height=0
 server.enter_world3d(second[2].id);var second_world:Array=await server.enter_world_ready;assert(second_world[0])
 assert(second_world[2].character.customization.body_shapes.height==.6)
 server.logout();server.login("shape_isolation","test","local");await server.login_finished
 server.enter_world3d(id);var restored:Array=await server.enter_world_ready;assert(restored[0])
 assert(restored[2].character.customization.body_shapes.height==-.4)
 assert(restored[2].character.customization.part_ids.FrontHair1==201)
 # An old delayed request must not execute in a new login session.
 server.login("shape_other","test","local")
 await create_timer(.1).timeout
 server.create_character("LateRequest","warrior","1","female",{})
 await server.login_finished
 var canceled:Array=await server.character_created
 assert(not canceled[0])
 server.fetch_characters();var other:Array=await server.characters_ready
 assert(other.is_empty(),"Old create request wrote into the new account")
 server.login("shape_isolation","test","local");await server.login_finished
 server.enter_world3d(id)
 server.logout()
 var canceled_enter:Array=await server.enter_world_ready
 assert(not canceled_enter[0],"Late world entry survived logout")
 var rng:=RandomNumberGenerator.new();rng.seed=345
 for sample in 100:
  var shape:Dictionary=Customization.Shapes.random_values(rng)
  assert(shape==Customization.Shapes.normalize(shape) and shape.size()==5)
 print("PASS request snapshot, response isolation, shape validation, create/list/enter/switch/relogin and random bounds")
 quit()
