extends "res://tools/test_world3d_mcp.gd"
## Small real GLB/physics/HTTP fixture; run on the background GPU desktop only.
const Policy=preload("res://scripts/world_editor/picking_lod_policy.gd")
const Walk=preload("res://scripts/world_editor/walk_mode.gd")
const Surface=preload("res://scripts/world3d/surface_materials.gd")

func physics()->void:
	await settle()
	for index in 3:await physics_frame

func box(parent:Node,name_:String,size_:Vector3,position_:Vector3,role:String="")->MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=name_;node.position=position_
	var geometry:=BoxMesh.new();geometry.size=size_;node.mesh=geometry
	var extras:Dictionary={"rmmo_collision":"none" if not role.is_empty() else "block"}
	if not role.is_empty():
		extras.rmmo_editor_picking={"version":1,"group":"body","role":role}
		extras.rmmo_visibility_range={"begin":0 if role=="canonical" else 10,"end":10 if role=="canonical" else 0,"bounds":[-1,-1,-1,2,2,2]}
	node.set_meta("extras",extras);parent.add_child(node);return node

func bodies(uuid:String)->Array:return editor._bodies_by_uuid.get(uuid,[])

func named_body(uuid:String,label:String)->StaticBody3D:
	for body:StaticBody3D in bodies(uuid):
		if str(body.get_meta("visual").name)==label:return body
	return null

func ray(x:float,mask:int)->Dictionary:
	var query:=PhysicsRayQueryParameters3D.create(Vector3(x,5,0),Vector3(x,-3,0),mask)
	return editor.get_world_3d().direct_space_state.intersect_ray(query)

func top_face(rows:Array,mesh_name:String)->Dictionary:
	for row:Dictionary in rows:
		if str(row.target.mesh).ends_with(mesh_name) and float(row.normal[1])>.99:return row
	return {}

func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	Engine.max_fps=60;root.size=Vector2i(1400,900);root.content_scale_size=root.size
	var previous:=Policy.enabled;Policy.enabled=false
	var directory:=Paths.cache_directory("editor_lod_picking_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var model:=Node3D.new();model.name="ExplicitGeometry"
	box(model,"Authority",Vector3(2,2,2),Vector3.ZERO,"canonical")
	var alternate:=box(model,"Alternate",Vector3(1.6,1.6,1.6),Vector3.ZERO,"render_lod")
	box(alternate,"IndependentGround",Vector3(4,.2,4),Vector3(0,-1.2,0))
	var model_path:=directory.path_join("explicit.glb")
	check(Io.save_scene(model,model_path)==OK,"export temporary versioned geometry GLB");model.free()
	var source_sha:=FileAccess.get_sha256(model_path)
	var doc:=Doc.new()
	var a:String=doc.add_asset({"asset_path":model_path},Vector3(0,1,0))
	var b:String=doc.add_asset({"asset_path":model_path},Vector3(6,1,0))
	var blocking:String=doc.add_asset({"asset_path":model_path,"collision":"block"},Vector3(12,1,0))
	var no_walk:String=doc.add_asset({"asset_path":model_path,"collision":"none"},Vector3(18,1,0))
	var path:=directory.path_join("map.gltf");check(doc.save(path)==OK,"save temporary reference map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false
	editor._draft_directory=directory.path_join("drafts");editor._material_directory=directory.path_join("materials")
	root.add_child(editor);editor.set_process(false);editor._safety.enabled=false;await physics()
	check(bodies(a).size()==3 and bodies(b).size()==3 and bodies(blocking).size()==3 and bodies(no_walk).size()==3,"candidate off retains all original picking/physical bodies")
	var original_hit:=ray(0,1)
	var original_none_hit:=ray(18,1)
	check(not original_hit.is_empty(),"control exact mesh is ray-pickable")
	check(not original_none_hit.is_empty() and ray(18,Walk.WALK_MASK).is_empty(),"record none control remains precisely pickable without a walking obstacle")
	if original_hit.is_empty() or original_none_hit.is_empty():quit(1);return
	Policy.enabled=true;editor._rebuild();await physics()
	check(bodies(a).size()==2 and bodies(b).size()==2,"synchronous build removes only explicitly redundant LOD bodies")
	check(bodies(blocking).size()==3,"record block override retains every physical mesh")
	var canonical:=named_body(a,"Authority")
	var ground:=named_body(a,"IndependentGround")
	check(canonical!=null and ground!=null and named_body(a,"Alternate")==null,"skipping a LOD body keeps its unmarked physical child")
	if canonical==null or ground==null:quit(1);return
	check(canonical.collision_layer==1 and (ground.collision_layer&Walk.WALK_MASK)!=0,"none remains selectable without making canonical a walking obstacle")
	var hit:=ray(0,1);var walk_hit:=ray(0,Walk.WALK_MASK)
	check(not hit.is_empty() and hit.collider==canonical and hit.position.is_equal_approx(original_hit.position) and hit.face_index==original_hit.face_index,"canonical exact ray hit and triangle index equal ordinary control")
	check(not walk_hit.is_empty() and walk_hit.collider==ground and walk_hit.position.y<0,"walking ray passes through none geometry to its independent floor")
	check(canonical.get_child(0).shape==named_body(b,"Authority").get_child(0).shape,"separate UUID instances retain shared same-mesh shape cache")
	var none_canonical:=named_body(no_walk,"Authority")
	var none_child:=named_body(no_walk,"IndependentGround")
	check(bodies(no_walk).size()==2 and none_canonical!=null and none_child!=null and named_body(no_walk,"Alternate")==null,"record none removes alternate but retains canonical and independent child pickers")
	if none_canonical==null or none_child==null:quit(1);return
	check(none_canonical.collision_layer==1 and none_child.collision_layer==1 and none_child.get_meta("visual").get_meta("extras").rmmo_collision=="none","record none overrides source physical child too; every retained body has pick layer only")
	var none_hit:=ray(18,1)
	check(not none_hit.is_empty() and none_hit.collider==none_canonical and none_hit.position.is_equal_approx(original_none_hit.position) and none_hit.face_index==original_none_hit.face_index,"record none preserves control exact canonical hit and triangle index")
	check(ray(18,Walk.WALK_MASK).is_empty(),"record none suppression never introduces a walking body")
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start real HTTP fixture")
	var discovery:=await rpc("tools/list")
	var names:Array=discovery.get("result",{}).get("tools",[]).map(func(row):return row.name)
	check(names.has("pick_surface") and names.has("paint_surface") and names.has("open_world"),"current 3D tools expose unchanged shared operations")
	await call_tool("open_world",{"path":path})
	await physics()
	check(bodies(a).size()==2 and bodies(b).size()==2 and bodies(blocking).size()==3 and bodies(no_walk).size()==2,"HTTP sliced load uses same collision plan as synchronous build")
	check(editor._load_job.state().timings.build.units.get("picking_lod_skipped",{}).get("count",0)==3,"sliced load proves three meshes skipped before capture/cook/publication including record none")
	check(ray(18,Walk.WALK_MASK).is_empty() and ray(18,1).get("collider")==named_body(no_walk,"Authority"),"HTTP sliced record none retains only exact editor picking, no walking collision")
	var none_faces:=await call_tool("list_object_surfaces",{"id":no_walk,"limit":200})
	var none_face:=top_face(none_faces.faces,"Authority")
	check(not none_face.is_empty() and not top_face(none_faces.faces,"Alternate").is_empty(),"record none canonical and alternate explicit paint targets remain independently enumerated")
	if none_face.is_empty():quit(1);return
	editor._camera.projection=Camera3D.PROJECTION_PERSPECTIVE;editor._camera.position=Vector3(18,7,6);editor._camera.look_at(Vector3(18,1,0));await physics()
	var none_point:Vector2=editor._camera.unproject_position(Vector3(none_face.center[0],none_face.center[1],none_face.center[2]))
	check(editor._pick_object(none_point)==no_walk,"normal UI picks the record none canonical UUID")
	var none_picked:=await call_tool("pick_surface",{"screen":[none_point.x,none_point.y]})
	check(none_picked.get("id")==no_walk and equivalent(none_picked.get("target",{}),none_face.target),"HTTP record none surface pick retains exact canonical paint identity")
	var faces:=await call_tool("list_object_surfaces",{"id":a,"limit":200})
	var face:=top_face(faces.faces,"Authority")
	var alternate_face:=top_face(faces.faces,"Alternate")
	check(not face.is_empty() and not alternate_face.is_empty(),"all explicit canonical and alternate material targets remain available")
	if face.is_empty() or alternate_face.is_empty():quit(1);return
	editor._camera.projection=Camera3D.PROJECTION_PERSPECTIVE;editor._camera.position=Vector3(0,7,6);editor._camera.look_at(Vector3(0,1,0));await physics()
	var point:Vector2=editor._camera.unproject_position(Vector3(face.center[0],face.center[1],face.center[2]))
	check(editor._pick_object(point)==a,"normal UI picking resolves canonical UUID")
	var picked:=await call_tool("pick_surface",{"screen":[point.x,point.y]})
	check(picked.get("id")==a and equivalent(picked.get("target",{}),face.target),"HTTP mouse paint resolves exact canonical surface")
	var history:int=editor._doc._undo.size()
	var painted:Dictionary=editor._material_tool.paint(a,face.target,"builtin:white")
	check(painted.ok and editor._doc._undo.size()==history+1,"UI shared paint commits one transaction")
	check(editor._doc._find(a).surface_paint.size()==1 and not editor._doc._find(b).has("surface_paint"),"canonical paint does not broadcast to other LODs or UUID instances")
	await call_tool("undo");await call_tool("redo")
	await call_tool("paint_surface",{"id":a,"target":alternate_face.target,"material_id":"builtin:checker"})
	check(editor._doc._find(a).surface_paint.size()==2 and bodies(a).size()==2,"explicit alternate target remains paintable without duplicate picking bodies")
	var before:Array=editor._doc.records.duplicate(true)
	await call_tool("paint_surface",{"id":a,"target":{"mesh":"../../bad","surface":0,"face":0,"geometry":"bad"},"material_id":"builtin:white"},false)
	check(editor._doc.records==before,"invalid explicit target has no document side effects")
	await call_tool("set_object_properties",{"ids":[a],"locked":true})
	await call_tool("paint_surface",{"id":a,"target":face.target,"material_id":"builtin:checker"},false)
	await call_tool("set_object_transform",{"id":a,"position":[0,2,0]},false)
	await call_tool("set_object_properties",{"ids":[a],"locked":false})
	await call_tool("set_object_properties",{"ids":[a],"hidden":true});await physics()
	check(bodies(a).is_empty() and ray(0,1).is_empty(),"hidden record removes canonical and independent child bodies")
	await call_tool("undo");await physics();check(bodies(a).size()==2,"undo hide restores exact same policy")
	await call_tool("set_floor_view",{"isolation":true,"base_height":10,"floor_height":3,"outside":"dim"});await physics()
	check(bodies(a).is_empty() and bodies(b).is_empty(),"dim isolated records leave no selectable or walkable ghost geometry")
	await call_tool("undo");await physics();check(bodies(a).size()==2,"undo isolation restores canonical picking")
	await call_tool("set_object_transform",{"id":a,"position":[0,2,0]});await physics()
	check(ray(0,1).position.y>2.9 and ray(6,1).position.y<2.1,"transform moves only one UUID collider graph")
	await call_tool("undo");await call_tool("redo")
	await call_tool("save_world")
	check(FileAccess.get_sha256(model_path)==source_sha,"save and painting never rewrite source metadata/model")
	check(not FileAccess.get_file_as_string(path).contains("picking_lod_skip"),"derived picking decisions never enter saved map")
	await call_tool("open_world",{"path":path});await physics()
	check(bodies(a).size()==2 and bodies(b).size()==2 and editor._doc._find(a).surface_paint.size()==2,"save/reopen preserves independent surface targets and picking optimization")
	check(editor._doc._find(no_walk).collision=="none" and bodies(no_walk).size()==2 and named_body(no_walk,"Alternate")==null and ray(18,Walk.WALK_MASK).is_empty(),"save/reopen keeps authored record none, canonical picking and no walking obstacle")
	Policy.enabled=false;editor._rebuild();await physics()
	check(bodies(a).size()==3 and bodies(b).size()==3 and bodies(no_walk).size()==3 and ray(18,Walk.WALK_MASK).is_empty(),"control switch restores original synchronous path after edit/reload without changing record none physics")
	await call_tool("open_world",{"path":path});await physics()
	check(bodies(a).size()==3 and editor._load_job.state().timings.build.units.get("picking_lod_skipped",{}).get("count",0)==0,"control switch also restores original sliced load")
	editor.queue_free();await settle();Policy.enabled=previous
	print("EDITOR_PICKING_LOD_GPU_FAILED=",failed);quit(1 if failed else 0)
