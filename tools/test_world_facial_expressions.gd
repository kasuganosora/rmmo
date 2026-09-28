extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(120).timeout.connect(func():push_error("World facial test timeout");quit(2))
 var session=root.get_node("GameSession")
 var recipe:Dictionary={"gender":"female","customization":{}}
 preload("res://scripts/char/character_body_migration.gd").apply(recipe)
 recipe.merge({"id":-102,"name":"表情验收"})
 session.selected_character=recipe;session.spawn_data={}
 var folder:String=preload("res://scripts/world3d/map_paths.gd").cache_directory("facial_%d"%Time.get_ticks_usec())
 var doc=preload("res://scripts/world3d/world_document.gd").new()
 doc.add_box("floor",Vector3(0,-.1,0),Vector3(10,.2,10))
 var path:String=folder.path_join("map.gltf");assert(doc.save(path)==OK)
 session.world3d_map_path=path;session.world3d_spawn=Vector3(0,.9,0)
 var world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
 while not world.is_world_ready():await process_frame
 var model=world._player._model;model.set_process(false)
 world._hud._on_menu_item("emote")
 await process_frame
 assert(world._hud._emote_panel.visible)
 var blink:Button
 var reset:Button
 for node in world._hud._emote_body.find_children("*","Button",true,false):
  if node.text=="闭眼":blink=node
  if node.text=="恢复自然":reset=node
 assert(blink!=null and reset!=null)
 blink.pressed.emit();model._process(.09)
 assert(absf(float(model.axis_rig.body.expression_values.blink)-.5)<.001)
 var npc=preload("res://scripts/char/character_model_3d.gd").create_npc({"gender":"female","customization":{},"equipment":{}})
 world.add_child(npc);npc.set_process(false)
 assert(npc.axis_rig!=null,"Female NPC did not migrate to native model")
 assert(npc.axis_rig.body.expression_values.is_empty(),"Player expression leaked to NPC")
 assert(npc.set_expressions({"mouth_smile":.7}))
 assert(not model.axis_rig.body.expression_values.has("mouth_smile"))
 var face_buttons:Dictionary={}
 for node in world._hud._emote_body.find_children("*","Button",true,false):
  if node.has_meta("expression_id"):face_buttons[str(node.get_meta("expression_id"))]=node
 assert(face_buttons.size()==preload("res://scripts/char/character_expressions.gd").CHANNELS.size()+1)
 face_buttons.a.pressed.emit()
 face_buttons.blush.pressed.emit()
 face_buttons.star_eyes.pressed.emit()
 model._process(.18)
 assert(model.axis_rig.body.expression_values.has_all(["blink","a","blush","star_eyes"]))
 face_buttons.o.pressed.emit();model._process(.18)
 assert(not model.axis_rig.body.expression_values.has("a") and model.axis_rig.body.expression_values.has("o"))
 assert(not face_buttons.a.button_pressed and face_buttons.o.button_pressed)
 face_buttons.blink.pressed.emit();model._process(.18)
 assert(not model.axis_rig.body.expression_values.has("blink"))
 for surface in model.axis_rig.body.topology.materials.size():
  if model.axis_rig.body.topology.materials[surface]=="Irises":
   var player_material=model.axis_rig.body.mesh_instance.mesh.surface_get_material(surface)
   var npc_material=npc.axis_rig.body.mesh_instance.mesh.surface_get_material(surface)
   assert(player_material!=npc_material)
   assert(float(player_material.get_shader_parameter("expression_star"))==1)
   assert(float(npc_material.get_shader_parameter("expression_star"))==0)
 reset.pressed.emit();model._process(.18)
 assert(model.axis_rig.body.expression_values.is_empty())
 assert(npc.axis_rig.body.expression_values.get("mouth_smile")==.7)
 assert(not world.request_facial_expression("missing"))
 assert(npc.set_mmd_expressions({"あ":.7,"まばたき":.3,"照れ":.4}))
 assert(npc.axis_rig.body.expression_values.get("a")==.7)
 var valid_weights:Dictionary=npc.axis_rig.body.expression_values.duplicate()
 assert(not npc.set_mmd_expressions({"unsupported_mmd_tag":1.0}))
 assert(npc.axis_rig.body.expression_values==valid_weights,"Unknown MMD tag partially changed the face")
 assert(npc.set_mmd_expressions({}))
 var server=world.Net.server()
 var remote_id:="expression_peer"
 server._remote_players[remote_id]={"id":remote_id,"name":"Expression peer","gender":"female","customization":{"part_ids":{"FrontHair1":0}},"equipment":{},"position_m":[2,0,0],"map_path":world._map_path}
 var first:Dictionary=server.try_remote_facial_expression(remote_id,{"a":.8,"blush":1})
 assert(first.ok)
 # Packet can arrive before AOI spawn. Spawn restores the authoritative snapshot.
 world.apply_actions(first.actions)
 world.apply_actions([server._remote_spawn_action(remote_id)])
 var remote=world.remote_players.models[remote_id];remote.set_process(false)
 assert(remote.axis_rig!=null and remote.axis_rig.body.expression_values.get("a")==.8)
 var old_action:Dictionary=first.actions[0].duplicate(true)
 assert(server.try_remote_facial_expression(remote_id,{"star_eyes":1}).ok)
 world._process(0) # Real queued server delivery; no manual action injection.
 remote._process(.18)
 assert(remote.axis_rig.body.expression_values.has("star_eyes"))
 world.apply_actions([old_action]);remote._process(.18)
 assert(not remote.axis_rig.body.expression_values.has("a"),"Out-of-order packet restored stale mouth")
 assert(model.axis_rig.body.expression_values.is_empty(),"Remote expression changed local player")
 world.remote_players.despawn(remote_id)
 world.apply_actions([server._remote_spawn_action(remote_id)])
 remote=world.remote_players.models[remote_id];remote.set_process(false)
 assert(remote.axis_rig.body.expression_values.has("star_eyes"),"AOI reentry lost snapshot")
 assert(not server.try_remote_facial_expression(remote_id,{"bogus":1}).ok)
 assert(not server.try_remote_facial_expression("missing",{}).ok)
 assert(server.try_remote_facial_expression(remote_id,{}).ok)
 world._process(0);remote._process(.18)
 assert(remote.axis_rig.body.expression_values.is_empty())
 world.apply_actions(server.try_remote_despawn(remote_id).actions)
 assert(not world.remote_players.models.has(remote_id))
 server.awaiting_respawn=true
 assert(not world.request_facial_expression("blink"))
 server.awaiting_respawn=false
 print("PASS mocker authoritative local/remote delivery, out-of-order rejection, AOI snapshot reentry, reset/despawn, invalid/dead rejection")
 var output:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/native_expressions_02/world_panel.png")
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output)
 print("PASS real HUD category combinations, rapid targets, toggle/reset, mouth replacement, migrated NPC and material/geometry instance isolation")
 world.free();await process_frame
 preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(folder)
 quit()
