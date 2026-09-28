extends SceneTree
var failed:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 print(("PASS: " if ok else "FAIL: ")+label)
 if not ok:failed+=1
func run()->void:
 create_timer(240).timeout.connect(func():push_error("Ground lifecycle timeout");quit(2))
 var session=root.get_node("GameSession");var server=root.get_node("MockServer")
 session.selected_character={"id":-101,"name":"新身体坐地生命周期","gender":"female","customization":{"body_model":"female_base_v2","part_ids":{"FrontHair1":202}}}
 session.spawn_data={}
 var folder:String=preload("res://scripts/world3d/map_paths.gd").cache_directory("ground_lifecycle_%d"%Time.get_ticks_usec())
 var document=preload("res://scripts/world3d/world_document.gd").new()
 document.add_box("floor",Vector3(0,-.1,0),Vector3(12,.2,12))
 var path:String=folder.path_join("map.gltf")
 assert(document.save(path)==OK)
 session.world3d_map_path=path;session.world3d_spawn=Vector3(0,.9,0)
 var world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
 while not world.is_world_ready():await process_frame
 var model=world._player._model
 check(model.axis_rig!=null,"lifecycle uses accepted native body")
 world.request_sit(true)
 check(world._sit_preparing,"initial sit is asynchronously preparing")
 var old_map:String=world._map_path
 check(not await world.transfer_map(folder.path_join("missing.gltf"),Vector3(0,.9,0)),"missing transfer is rejected")
 while world._sit_preparing:await process_frame
 check(world._map_path==old_map and not server.sitting and model.action=="idle","failed transfer cancels pending sit without late action")
 await world.request_sit(true)
 check(server.sitting and model.action=="sit_down_ground","prepared action remains reusable after cancellation")
 var identity:int=model.get_instance_id()
 check(await world.transfer_map(path,Vector3(2,.9,0)),"valid transfer commits")
 check(not server.sitting and model.get_instance_id()==identity,"transfer clears sit and preserves native actor")
 while model.action=="stand_up_ground":await process_frame
 check(model.action=="idle","transfer recovery reaches idle")
 await world.request_sit(true)
 check(server.sitting,"sit again before leaving world")
 world.free()
 await process_frame
 check(not server.sitting,"world exit clears authoritative sitting")
 for child in root.get_children():check(child.name not in ["GroundPosePreparation","GroundActionPreparation"],"no ground preparation workspace remains")
 preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(folder)
 print("test_ground_world_lifecycle: ","PASS" if failed==0 else "FAIL")
 quit(0 if failed==0 else 1)
