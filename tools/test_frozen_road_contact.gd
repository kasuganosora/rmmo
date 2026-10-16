extends "res://tools/test_world3d_mcp.gd"
const Narrow=preload("res://scripts/world3d/asset_road_contact.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Follow=preload("res://scripts/world_editor/terrain_follow_tools.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const FrozenContact=preload("res://scripts/world3d/frozen_road_contact.gd")
func run()->void:
 var touching={"known":true,"faces":[],"solids":[]}
 var row=Node3D.new()
 for x in [10.,12.]:
  var part=MeshInstance3D.new();var box=BoxMesh.new();box.size=Vector3(2,30,30);part.mesh=box;part.position.x=x;row.add_child(part)
 Narrow.collect(row,Transform3D.IDENTITY,touching);row.free()
 check(not Narrow.inside(Vector3.ZERO,touching.faces),"coincident exit and entry of touching blocks do not enclose distant point")
 check(Narrow.inside(Vector3(10,0,0),touching.faces),"actual interior of touching blocks remains occupied")
 var open_shell=[{"points":[Vector3(10,-15,-15),Vector3(10,15,-15),Vector3(10,15,15)]},{"points":[Vector3(10,-15,-15),Vector3(10,15,15),Vector3(10,-15,15)]}]
 check(not Narrow.inside(Vector3.ZERO,open_shell),"open decorative shell ray crossing does not define an enclosed solid")
 create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=120000
 var directory:=Paths.cache_directory("frozen_road_contact_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
 var path:=directory.path_join("map.gltf");var doc:=Doc.new()
 var heights:Array=[];heights.resize(289);heights.fill(0.);var holes:Array=[];holes.resize(256);holes.fill(false)
 doc.records=[{"uuid":"ground","kind":"box","surface_id":"ground","position":[16.,0.,16.],"rotation":[0,0,0],"size":[32.,1.,32.],"color":[.3,.4,.2],"collision":"walk","terrain_mesh":{"version":1,"columns":16,"rows":16,"floor":-8.,"heights":heights,"holes":holes}}]
 doc.map_meta.editor_layout=City.defaults();doc.map_meta.editor_layout.roads={"nodes":[{"id":"a","position":[6.,0.,16.]},{"id":"b","position":[26.,0.,16.]}],"edges":[{"id":"lane","from":"a","to":"b","width_start":1.5,"width_end":1.5,"kind":"ground"}]}
 var raw:Array=[]
 for item:Array in [[[16.,2.5,13.],[2.,5.,2.]],[[16.,2.5,19.],[2.,5.,2.]],[[16.,5.,16.],[2.,1.,8.]]]:
  raw.append({"uuid":"part_"+str(raw.size()),"kind":"box","position":item[0],"rotation":[0.,0.,0.],"size":item[1],"surface_id":"block","color":[.5,.5,.5],"collision":"block","building":{"id":"fixture","part":"main/wall"+str(raw.size()),"floor":0,"floor_y":0.,"role":"wall"}})
 var baked=Frozen.bake(raw);check(baked.ok and baked.records.size()==1,"native bake combines arch into one immutable prefab")
 if not baked.ok:quit(1);return
 var arch:Dictionary=baked.records[0];arch.erase("building");arch.uuid="arch";arch.fortification={"id":"test_arch","part":"baked","role":"prefab"}
 doc.records.append(arch);check(doc.save(path)==OK,"native frozen arch fixture saved")
 var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
 editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
 while editor._load_job!=null and editor._load_job.active:await process_frame
 var probe:=TCPServer.new();port=31980
 while probe.listen(port,"127.0.0.1")!=OK:port+=1
 probe.stop();check(editor.start_mcp(port).ok,"real HTTP loopback")
 var tools=await rpc("tools/list");check(tools.result.tools.any(func(t):return t.name=="preview_road_surface"),"current 3D discovery")
 var args={"follow_terrain":true,"material_id":"pack:default:paving/outdoor_flagstone/material"}
 var before=editor._doc.recovery_snapshot()
 var preview=await call_tool("preview_road_surface",args)
 check(preview.get("ok",false) and equivalent(preview,editor._roads.summary(args)),"UI HTTP frozen opening shared prepare")
 check(equivalent(before,editor._doc.recovery_snapshot()),"preview no effects")
 await call_tool("generate_road_surface",args)
 var generated=editor._doc.recovery_snapshot()
 var roads=editor._doc.records.filter(func(r):return r.has("road_mesh"))
 check(not roads.is_empty(),"road generated")
 var contacts=0;var cache={}
 for road:Dictionary in roads:
  if not Foot.batches_overlap(Foot.record_shapes(road),Foot.record_shapes(arch)):continue
  contacts+=1
  check(not FrozenContact.intersects(road,arch,Foot.record_shapes(road),Foot.record_shape(arch),cache),"frozen opening clear")
  var pillar=arch.duplicate(true);pillar.position[2]-=3.
  check(FrozenContact.intersects(road,pillar,Foot.record_shapes(road),Foot.record_shape(pillar),cache),"actual frozen pillar blocks")
  var low=arch.duplicate(true);low.position[1]-=2.
  check(FrozenContact.intersects(road,low,Foot.record_shapes(road),Foot.record_shape(low),cache),"lowered arch blocks headroom")
  var invalid=arch.duplicate(true);invalid.house_prefab.sha256="invalid"
  check(FrozenContact.intersects(road,invalid,Foot.record_shapes(road),Foot.record_shape(invalid),cache),"invalid checksum remains conservative and invalidates cache")
  var dynamic=arch.duplicate(true);dynamic.fixture={}
  check(not FrozenContact.geometry(dynamic,{}).get("known",true),"articulated fixture retains sweep protection")
 check(contacts>0,"broad-phase actually overlaps")
 var changed=arch.duplicate(true);changed.rotation=[0.,90.,0.]
 var original_geometry=FrozenContact.geometry(arch,{})
 var rotated_geometry=FrozenContact.geometry(changed,{})
 var rot=Basis.from_euler(Vector3(0,PI/2,0));var center=City.vec(arch.position);var error=0.
 for i in original_geometry.faces.size():
  for j in 3:error=maxf(error,(rot*(original_geometry.faces[i].points[j]-center)+center).distance_to(rotated_geometry.faces[i].points[j]))
 check(error<.00001,"box-prefab rotation matches native transform without applying bounds as scale")
 changed.kind="asset";changed.size=[1.7,.8,.6]
 var scaled=FrozenContact.geometry(changed,{})
 error=0.
 for i in original_geometry.faces.size():
  for j in 3:error=maxf(error,(rot*((original_geometry.faces[i].points[j]-center)*Vector3(1.7,.8,.6))+center).distance_to(scaled.faces[i].points[j]))
 check(error<.00001,"asset-prefab local nonuniform scale plus yaw")
 var followed=Follow.prepare(editor,[{"record":editor._doc._find("ground").duplicate(true)}]);check(followed.get("ok",false),"native terrain-follow preserves opening")
 await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"undo exact")
 await call_tool("redo");check(equivalent(generated,editor._doc.recovery_snapshot()),"redo exact")
 await call_tool("save_world");await call_tool("open_world",{"path":path})
 check(equivalent(generated.records,editor._doc.records) and equivalent(generated.map_meta,editor._doc.map_meta),"save reopen frozen opening exact")
 editor._doc.apply_recovery(before)
 await call_tool("set_object_transform",{"id":"arch","position":[arch.position[0],arch.position[1],arch.position[2]-3.]},false)
 check(equivalent(before,editor._doc.recovery_snapshot()),"frozen component lock unchanged")
 var graph=City.resolve(editor._doc.map_meta).roads
 await call_tool("update_road_graph",{"expected_token":City.token(graph),"nodes":[{"id":"a","position":[6.,0.,13.]},{"id":"b","position":[26.,0.,13.]}],"edges":graph.edges})
 var blocked=editor._doc.recovery_snapshot();var rejected=await call_tool("preview_road_surface",args,false)
 check(not rejected.get("ok",false) and equivalent(blocked,editor._doc.recovery_snapshot()),"HTTP actual frozen wall blocked without side effect")
 editor._mcp.stop();editor.queue_free();await settle();print("FROZEN_ROAD_CONTACT failures=",failed);quit(1 if failed else 0)
