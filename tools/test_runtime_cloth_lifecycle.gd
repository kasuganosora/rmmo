extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 var twohand:bool="--twohand" in OS.get_cmdline_user_args()
 create_timer(300).timeout.connect(func():push_error("Runtime cloth lifecycle timeout");quit(2))
 var view=View.new();root.add_child(view)
 var recipe={"body_model":"female_base_v2","part_ids":{"FrontHair1":202}}
 var parts={"SurfaceEquipment":{"Clothing2":"maid_separate/item_01","UnderwearTop":"underlayer_lace/item_00","UnderwearBottom":"underlayer_briefs/item_00"},"SurfaceClothSlots":["Clothing2"]}
 view.configure("female",recipe,parts);view.model.set_process(false)
 view.model.play("idle","front",true);view.model._from_rotations.clear();view.model.pose_at(.2)
 var folder:String=Art.review_path("character_3d/runtime_cloth_ik_01" if twohand else "character_3d/runtime_cloth_lifecycle_02");DirAccess.make_dir_recursive_absolute(folder)
 view.viewport.size=Vector2i(640,800);view.camera.size=2.2;view.camera.position=Vector3(0,1,4);view.camera.look_at(Vector3(0,1,0))
 var body=view.model.axis_rig.body;var cloth=view.model.axis_rig.cloth
 var actor_id:int=body.get_instance_id();var max_error:=0.0
 for frame in 5:await process_frame
 for frame in 65:
  var points:PackedVector3Array=body.posed_points.duplicate()
  var hair_transform:Transform3D=view.model.axis_rig.hair.transform
  cloth.advance(1.0/60.0)
  for i in points.size():max_error=maxf(max_error,points[i].distance_to(body.posed_points[i]))
  assert(max_error<.00001 and hair_transform.is_equal_approx(view.model.axis_rig.hair.transform),"Preparation escaped into visible wearer/head")
  var garment=view.model.axis_rig.wardrobe.garments.Clothing2
  assert(bool(garment.mesh_instance.mesh.surface_get_material(0).get_shader_parameter("candidate_simulate"))==(frame==64))
  await process_frame;await RenderingServer.frame_post_draw
  if frame in [0,32,64]:assert(view.viewport.get_texture().get_image().save_png(folder+"/prepare_%02d.png"%frame)==OK)
  if frame%20==0:print("Prepared frame ",frame)
 assert(cloth.is_ready())
 var adapter=cloth.entries.Clothing2.adapter;var adapter_id:int=adapter.get_instance_id()
 view.model.set_equipment(parts);assert(cloth.entries.Clothing2.adapter.get_instance_id()==adapter_id)
 # Exercise the actual Model tick: animation and blending precede cloth.
 if twohand:
  parts.WeaponMain=1;parts.WeaponMainItem="great_club";parts.WeaponStyle="heavy"
  view.model.set_equipment(parts)
 view.model.play("walk","front",true);view.model._process(1.0/60.0)
 await process_frame;await RenderingServer.frame_post_draw
 assert(cloth.error.is_empty() and body.pose_sync_error.is_empty())
 var submitted:PackedFloat32Array=adapter.solver._external_targets.to_float32_array()
 var expected:PackedVector3Array=adapter.garment.evaluate(body.posed_points)
 var packet_error:=0.0
 for i in expected.size():
  var index:int=adapter.control_to_particle[i]*4
  packet_error=maxf(packet_error,(expected[i]+body.root_offset).distance_to(Vector3(submitted[index],submitted[index+1],submitted[index+2])))
 assert(packet_error<.00001,"Cloth received pre-blend body targets")
 if twohand:
  assert(view.model.axis_rig.twohand.bridge.completed_revision==view.model.axis_rig.twohand.bridge.revision)
  assert(view.model.axis_rig.cloth_ik_revision==view.model.axis_rig.twohand.bridge.revision,"Cloth missed final IK phase")
  assert(view.viewport.get_texture().get_image().save_png(folder+"/final_ik.png")==OK)
 recipe.body_shapes={"height":.2};view.configure("female",recipe,parts)
 assert(body.get_instance_id()==actor_id and not is_instance_valid(adapter))
 assert(cloth.entries.Clothing2.prepared_frames==0 and not cloth.is_ready())
 var renewed=cloth.entries.Clothing2.adapter
 view.model.set_equipment({"SurfaceEquipment":{"UnderwearTop":"underlayer_lace/item_00"},"SurfaceClothSlots":[]})
 assert(cloth.entries.is_empty() and not is_instance_valid(renewed))
 var report={"wearer_error_m":max_error,"prepared_frames":65,"same_recipe_reused":true,"shape_invalidated":true,"unequip_freed":true,"animation_tick_submitted":true,"final_blend_packet_error_m":packet_error,"visual_acceptance":"Not all poses/garments; existing side/back flare remains"}
 var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 view.free()
 for frame in 4:await process_frame
 print("PASS runtime cloth lifecycle ",report)
 quit()
