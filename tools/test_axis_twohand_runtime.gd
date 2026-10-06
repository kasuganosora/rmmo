extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(240).timeout.connect(func():push_error("Twohand runtime timeout");quit(2))
 var view=View.new();root.add_child(view)
 var recipe={"body_model":"female_base_v2","part_ids":{"FrontHair1":202}}
 var gear={"WeaponMain":1,"WeaponMainItem":"great_club","WeaponStyle":"heavy","SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE}
 view.configure("female",recipe,gear);view.model.set_process(false)
 var rig=view.model.axis_rig;var body=rig.body;var id:int=body.get_instance_id()
 var maximum:=0.0;var samples:=0
 var folder:String=preload("res://scripts/asset/art_paths.gd").review_path("character_3d/axis_twohand_04");DirAccess.make_dir_recursive_absolute(folder)
 view.viewport.size=Vector2i(640,800);view.camera.size=3.2;view.camera.position=Vector3(0,1,4);view.camera.look_at(Vector3(0,1,0))
 for height:float in [-1.0,1.0,0.0]:
  recipe.body_shapes={"height":height};view.model.configure("female",recipe,gear)
  for action:String in ["idle","walk","attack"]:
   view.model.play(action,"front",true)
   view.model._from_rotations.clear()
   for phase:float in [0.0,.22,.5,.72,1.0]:
    view.model.elapsed=view.model.action_duration()*phase
    view.model._process(0)
    await RenderingServer.frame_post_draw
    assert(body.get_instance_id()==id and rig.twohand.bridge.error.is_empty())
    assert(rig.twohand.bridge.completed_revision==rig.twohand.bridge.revision)
    for i in 2:
     var error:float=rig.twohand.palm("l" if i==0 else "r").origin.distance_to(rig.twohand.palm_targets[i].origin)
     maximum=maxf(maximum,error)
     assert(error<.005,"Unreachable grip "+str([height,action,phase,i,error]))
    samples+=1
    if height==0.0:
     assert(view.viewport.get_texture().get_image().save_png(folder+"/%s_%s.png"%[action,str(phase)])==OK)
    await process_frame
 gear.WeaponMain=0;gear.erase("WeaponMainItem");view.model.set_equipment(gear)
 assert(not rig.twohand.bridge.modifier.active)
 view.model.play("idle","front",true);view.model._from_rotations.clear();view.model._process(0)
 var reset:PackedVector3Array=body.posed_points.duplicate()
 await RenderingServer.frame_post_draw
 assert(body.posed_points==reset,"Cancelled IK restores stale equipped pose")
 var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE);file.store_string(JSON.stringify({"samples":samples,"max_grip_error_m":maximum,"cancel_stable":true,"scope":"Runtime height/action samples; not full continuous garment/contact acceptance"},"  "));file.close()
 view.free()
 for frame in 3:await process_frame
 print("PASS runtime two-hand club ",samples," samples, error ",maximum);quit()
