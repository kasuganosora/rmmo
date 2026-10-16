extends "res://tools/test_world3d_mcp.gd"
const Narrow=preload("res://scripts/world3d/asset_road_contact.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Follow=preload("res://scripts/world_editor/terrain_follow_tools.gd")
const SOURCE="D:/code/rmmo_runtime/packs/default/assets/11feb4a7d18c9fd25cef5ca588e55f1e518141b78acc5baaf3b1a048920f43be.glb"
func write_solid(path:String)->void:
 var scene:=Node3D.new();var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(12,12,12);mesh.mesh=box;mesh.position.y=3;scene.add_child(mesh);mesh.owner=scene
 var gltf:=GLTFDocument.new();var state:=GLTFState.new()
 check(gltf.append_from_scene(scene,state)==OK and gltf.write_to_filesystem(state,path)==OK,"native test solid export")
 scene.free()
func run()->void:
 create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=120000
 var directory:=Paths.cache_directory("asset_road_contact_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
 var path:=directory.path_join("map.gltf");var doc:=Doc.new()
 var heights:Array=[];heights.resize(289);heights.fill(0.);var holes:Array=[];holes.resize(256);holes.fill(false)
 doc.records=[{"uuid":"ground","kind":"box","surface_id":"ground","position":[16.,0.,16.],"rotation":[0,0,0],"size":[32.,1.,32.],"color":[.3,.4,.2],"collision":"walk","terrain_mesh":{"version":1,"columns":16,"rows":16,"floor":-8.,"heights":heights,"holes":holes}}]
 doc.map_meta.editor_layout=City.defaults();doc.map_meta.editor_layout.roads={"nodes":[{"id":"a","position":[6.,0.,16.]},{"id":"b","position":[26.,0.,16.]}],"edges":[{"id":"lane","from":"a","to":"b","width_start":1.5,"width_end":1.5,"kind":"ground"}]}
 var asset:Dictionary={"uuid":"arch","kind":"asset","asset_path":SOURCE,"position":[16.,0.,16.],"rotation":[0.,90.,0.],"size":[1.,1.,1.],"bounds_position":[-1.91,0.,-.26],"bounds_size":[3.82,5.32,2.02]}
 doc.records.append(asset);check(doc.save(path)==OK,"isolated actual arch fixture saved")
 var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
 editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
 while editor._load_job!=null and editor._load_job.active:await process_frame
 var probe:=TCPServer.new();port=31970
 while probe.listen(port,"127.0.0.1")!=OK:port+=1
 probe.stop();check(editor.start_mcp(port).ok,"real HTTP loopback server")
 var tools:=await rpc("tools/list");check(tools.result.tools.any(func(t):return t.name=="preview_road_surface"),"3D road discovery unchanged")
 var args:={"follow_terrain":true,"material_id":"pack:default:paving/outdoor_flagstone/material"}
 var before:Dictionary=editor._doc.recovery_snapshot()
 var preview:=await call_tool("preview_road_surface",args)
 check(preview.get("ok",false) and equivalent(preview,editor._roads.summary(args)),"HTTP and UI shared road prepare passes actual arch void")
 check(equivalent(before,editor._doc.recovery_snapshot()),"preview atomic no side effects")
 await call_tool("generate_road_surface",args)
 var generated:Dictionary=editor._doc.recovery_snapshot()
 var roads:Array=editor._doc.records.filter(func(r):return r.has("road_mesh"))
 check(not roads.is_empty(),"road generated through arch")
 var cache:Dictionary={};var broad_count:=0
 var uneven:Dictionary=asset.duplicate(true);uneven.size=[1.7,.8,.6]
 var actual_node=editor._doc._asset(uneven)
 var actual_geometry:Dictionary={"known":true,"faces":[],"solids":[]}
 Narrow.collect(actual_node,Transform3D.IDENTITY,actual_geometry);actual_node.free()
 var predicted:=Narrow.geometry(uneven,{})
 check(actual_geometry.known and predicted.known and actual_geometry.faces.size()==predicted.faces.size(),"nonuniform rotated native asset and narrow phase have same source faces")
 var max_error:=0.
 for i in mini(actual_geometry.faces.size(),predicted.faces.size()):
  for j in 3:max_error=maxf(max_error,actual_geometry.faces[i].points[j].distance_to(predicted.faces[i].points[j]))
 check(max_error<.00001,"nonuniform scale plus 90deg yaw matches native mesh every vertex: "+str(max_error))
 var wrong:=Basis.from_euler(City.vec(uneven.rotation)*PI/180).scaled(City.vec(uneven.size))
 var native_basis:=Basis.from_euler(City.vec(uneven.rotation)*PI/180)*Basis.from_scale(City.vec(uneven.size))
 check((wrong*Vector3(1,0,0)).distance_to(native_basis*Vector3(1,0,0))>.5,"regression fixture distinguishes global and local scale")
 for road:Dictionary in roads:
  if not Foot.batches_overlap(Foot.record_shapes(road),Foot.record_shapes(asset)):continue
  broad_count+=1
  check(not Narrow.intersects(road,asset,Foot.record_shapes(road),Foot.record_shape(asset),cache),"actual triangles leave rotated arch opening clear")
  var solid:Dictionary=asset.duplicate(true);solid.position[2]+=1.5
  check(Narrow.intersects(road,solid,Foot.record_shapes(road),Foot.record_shape(solid),cache),"pillar blocks road after pose change with same cache")
  var short:Dictionary=asset.duplicate(true);short.size=[1.,.5,1.]
  check(Narrow.intersects(road,short,Foot.record_shapes(road),Foot.record_shape(short),cache),"low scaled arch blocks required headroom")
  var dynamic:Dictionary=asset.duplicate(true);dynamic.wind_response={"enabled":true}
  check(Narrow.intersects(road,dynamic,Foot.record_shapes(road),Foot.record_shape(dynamic),cache),"dynamic asset conservatively blocked")
  var unknown:Dictionary=asset.duplicate(true);unknown.asset_path="missing.glb"
  check(Narrow.intersects(road,unknown,Foot.record_shapes(road),Foot.record_shape(unknown),cache),"unknown asset conservatively blocked")
 if broad_count>0:
  var road:Dictionary=roads.filter(func(r):return Foot.batches_overlap(Foot.record_shapes(r),Foot.record_shapes(asset)))[0]
  var mutable:=directory.path_join("mutable.glb");DirAccess.copy_absolute(SOURCE,mutable)
  var changed:Dictionary=asset.duplicate(true);changed.asset_path=mutable;var scoped:Dictionary={}
  check(not Narrow.intersects(road,changed,Foot.record_shapes(road),Foot.record_shape(changed),scoped),"mutable source initial arch is clear")
  write_solid(mutable)
  check(Narrow.intersects(road,changed,Foot.record_shapes(road),Foot.record_shape(changed),scoped),"same-path source replacement invalidates cached geometry and enclosed solid blocks")
 check(broad_count>0,"test actually intersects broad asset bounds")
 var follow_before:Dictionary=editor._doc.recovery_snapshot()
 var followed:=Follow.prepare(editor,[{"record":editor._doc._find("ground").duplicate(true)}])
 check(followed.get("ok",false),"terrain-follow uses same exact arch clearance")
 check(equivalent(follow_before,editor._doc.recovery_snapshot()),"terrain-follow prepare does not mutate")
 await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"native undo road transaction")
 await call_tool("redo");check(equivalent(generated,editor._doc.recovery_snapshot()),"native redo road transaction")
 await call_tool("save_world");await call_tool("open_world",{"path":path})
 check(equivalent(generated.records,editor._doc.records) and equivalent(generated.map_meta,editor._doc.map_meta),"native save reopen preserves arch and clear road")
 # Move the asset only after removing roads, then ask normal HTTP road preview.
 editor._doc.apply_recovery(before)
 await call_tool("set_object_transform",{"id":"arch","position":[16.,0.,17.5]})
 var blocked:Dictionary=editor._doc.recovery_snapshot();var refused:=await call_tool("preview_road_surface",args,false)
 check(not refused.get("ok",false) and equivalent(blocked,editor._doc.recovery_snapshot()),"actual pillar rejects HTTP road preview atomically")
 editor._mcp.stop();editor.queue_free();await settle();print("ASSET_ROAD_CONTACT failures=",failed);quit(1 if failed else 0)
