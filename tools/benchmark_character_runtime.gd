extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func sample(count:int)->Dictionary:
 var times:Array[float]=[]
 for frame in count:
  var start:int=Time.get_ticks_usec()
  await process_frame
  await RenderingServer.frame_post_draw
  times.append((Time.get_ticks_usec()-start)/1000.0)
 times.sort()
 return {"median_ms":times[times.size()/2],"p95_ms":times[mini(times.size()-1,int(times.size()*.95))],"frames":count}
func run()->void:
 create_timer(240).timeout.connect(func():push_error("Character benchmark timeout");quit(2))
 var frame_count:=16
 if OS.get_cmdline_user_args().size()>1:frame_count=clampi(int(OS.get_cmdline_user_args()[1]),16,600)
 var warmup_frames:=3
 if OS.get_cmdline_user_args().size()>2:warmup_frames=clampi(int(OS.get_cmdline_user_args()[2]),3,120)
 var stage:String="before"
 if not OS.get_cmdline_user_args().is_empty():stage=OS.get_cmdline_user_args()[0]
 var folder:String=Art.review_path("character_3d/runtime_performance_01");DirAccess.make_dir_recursive_absolute(folder)
 var results:Dictionary={"stage":stage,"gpu":RenderingServer.get_video_adapter_name(),"viewport":str(root.size),"scope":"wall frame time incl renderer; same approved mesh/materials, no cloth; small sample, not GPU timer"}
 results["warmup_frames"]=warmup_frames
 var server=root.get_node("MockServer");server.inventory.clear();server.equipment.clear()
 var hud=load("res://scenes/ui/game_hud.tscn").instantiate()
 hud._character={"id":45,"name":"Benchmark","gender":"female","customization":{"body_model":"female_base_v2","part_ids":{"FrontHair1":202}}}
 var start:int=Time.get_ticks_usec()
 root.add_child(hud);hud._windows.character.visible=true;hud._fill_window("character")
 var view=hud._equipment_panel_logic._character_view
 results["cold_body_phases"]=view.model.axis_rig.body.load_timings.duplicate()
 results["hud_create_ms"]=(Time.get_ticks_usec()-start)/1000.0
 for i in 4:await process_frame
 results["hud_visible"]=await sample(frame_count)
 hud._windows.character.visible=false
 for i in 3:await process_frame
 var time_before:float=view.model.elapsed
 results["hud_hidden"]=await sample(frame_count)
 results["hidden_animation_advanced"]=view.model.elapsed-time_before
 results["hidden_viewport_mode"]=view.viewport.render_target_update_mode
 hud._windows.character.visible=true
 for i in 3:await process_frame
 results["hud_reopened"]=await sample(frame_count)
 hud.free();await process_frame
 var nodes_before:int=Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
 var actors:Array=[];var creation:Array=[];var phases:Array=[]
 for count in [1,2,4]:
  while actors.size()<count:
   start=Time.get_ticks_usec()
   var actor=preload("res://scripts/char/character_view_3d.gd").new();root.add_child(actor)
   actor.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":202}}, {})
   actor.position.x=actors.size()*180
   actors.append(actor);creation.append((Time.get_ticks_usec()-start)/1000.0)
   phases.append(actor.model.axis_rig.body.load_timings.duplicate())
  for i in warmup_frames:await process_frame
  results["actors_%d"%count]=await sample(frame_count)
 for actor in actors:actor.play("walk","front",true)
 for i in maxi(12,warmup_frames):await process_frame
 results["actors_4_walk"]=await sample(frame_count)
 results["actor_create_ms"]=creation
 results["body_load_phases"]=phases
 for actor in actors:actor.free()
 actors.clear()
 for i in 4:await process_frame
 results["node_delta_after_release"]=int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))-nodes_before
 var file:=FileAccess.open(folder+"/"+stage+".json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 print(JSON.stringify(results))
 quit()
