extends "res://tools/test_world3d_mcp.gd"
## Candidate only. Default is an in-memory native dry run.
## --expected-sha=<current map.gltf SHA256> is required in both modes.
## Add --apply only after the parent has pinned the completed 21-house candidate.
## No screenshots, interior tests, source-asset changes or formal-map writes.
const City=preload("res://scripts/world3d/city_layout.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Props=preload("res://tools/axel_house_reference_props.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
const CANDIDATE="D:/code/rmmo_runtime/cache/world3d/axel_town_houses_20261014/map.gltf"
const FORMAL="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const ASSETS="D:/code/rmmo_runtime/packs/default/assets"
const SOURCES={"guild":"7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd","alarm":"af248d5044ebad82c27a48d1f4b9be903cf884ea518d5f939b60699199db638e"}
const ROAD_END="axel_n_2d9829cb7c32"
var report:Dictionary={"phase":"starting","saved":false,"visual":"pending outdoor macro review","operations":[]}
var inputs:Dictionary={}
var before:Dictionary
var baseline_build:Dictionary
var recipe:Dictionary
var live_document
var expected_sha:String
var apply_requested:=false
func data(path:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path))
func atomic_json(path:String,value:Dictionary)->bool:
 var temporary:=path+".landmark.pending";var f:=FileAccess.open(temporary,FileAccess.WRITE)
 if f==null:return false
 f.store_string(JSON.stringify(value,"\t"));f.close()
 return Atomic.publish(temporary,path)==OK
func persist()->void:
 report.failures=failed
 if not atomic_json(OUT+"/guild_landmarks_apply.json",report):push_error("Unable to write landmark receipt")
func stopped()->bool:
 if failed==0:return false
 report.phase="failed_after_candidate_save" if report.saved else "failed_without_candidate_save";persist()
 if is_instance_valid(editor) and editor._mcp!=null:editor._mcp.stop()
 quit(1);return true
func contents(snapshot:Dictionary)->Dictionary:return {"records":snapshot.records,"map_meta":snapshot.map_meta}
func pin(path:String)->void:
 check(FileAccess.file_exists(path),"input exists "+path)
 if FileAccess.file_exists(path):inputs[path]=FileAccess.get_sha256(path)
func inputs_unchanged()->void:
 for path:String in inputs:check(FileAccess.get_sha256(path)==inputs[path],"input SHA unchanged "+path.get_file())
 check(FileAccess.get_sha256(FORMAL)==report.formal_before_sha256,"formal map unchanged")
func operation(name_:String,args:Dictionary)->Dictionary:
 report.phase=name_;persist()
 var result:=await call_tool(name_,args)
 report.operations.append({"tool":name_,"arguments":args,"result":result});persist();return result
func wait_ready()->void:
 var deadline:=Time.get_ticks_msec()+300000
 while Time.get_ticks_msec()<deadline:
  await process_frame
  if editor._load_job!=null and editor._load_job.active:continue
  if editor._ground_batches.stats().get("pending_groups",0)>0:continue
  await settle();return
 check(false,"native candidate load ready")
func shape(low:Vector3,high:Vector3)->Dictionary:
 var bounds:=AABB(low,high-low);var vertices:Array[Vector3]=[]
 for i in 8:vertices.append(bounds.get_endpoint(i))
 return Foot.from_points(vertices)
func core_for_footprint(rect:Rect2)->Dictionary:
 # Include the complete terrain triangles beneath the foundation: flattening
 # only an unsnapped 5.1 m box leaves interpolated edge vertices unsupported.
 var core:=Rect2();var found:=false;var seed:="";var cells:=0
 for r:Dictionary in editor._doc.records:
  if not r.has("terrain_mesh"):continue
  var pose:=Terrain.transform(r);var bounds:AABB=pose*Terrain.bounds(r)
  if not rect.intersects(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z)):continue
  check(absf(float(r.rotation[0]))+absf(float(r.rotation[1]))+absf(float(r.rotation[2]))<.0001,"known axis-aligned foundation terrain grid")
  if failed:return {}
  for z in int(r.terrain_mesh.rows):
   for x in int(r.terrain_mesh.columns):
    var world:Array=Terrain.cell(r,x,z).map(func(p):return pose*p)
    var cell:=Rect2(Vector2(world[0].x,world[0].z),Vector2.ZERO)
    for p:Vector3 in world:cell=cell.expand(Vector2(p.x,p.z))
    if not rect.intersects(cell):continue
    check(Terrain.solid(r.terrain_mesh,x,z),"foundation footprint has no open terrain cell")
    if failed:return {}
    core=core.merge(cell) if found else cell;found=true;cells+=1
  var center:=rect.get_center();var local:=pose.affine_inverse()*Vector3(center.x,0,center.y)
  if is_finite(Terrain.sample(r,local)):seed=r.uuid
 check(found and not seed.is_empty(),"complete native foundation terrain found")
 return {"rect":core,"seed":seed,"cells":cells}
func stroke(core:Dictionary,height:float)->Dictionary:
 var rect:Rect2=core.rect;var center:=rect.get_center()
 return {"id":core.seed,"mode":"flatten","shape":"rectangle","cross_tiles":true,"points":[[center.x,center.y]],"plot_width":rect.size.x,"plot_depth":rect.size.y,"plot_yaw":0.,"plot_grade":[0.,0.],"blend_margin":2.,"strength":1.,"target_height":height}
func verify_bearing(rect:Rect2,height:float)->void:
 var core:=core_for_footprint(rect)
 if failed:return
 var minimum:=INF;var maximum:=-INF
 for r:Dictionary in editor._doc.records:
  if not r.has("terrain_mesh"):continue
  var pose:=Terrain.transform(r);var bounds:AABB=pose*Terrain.bounds(r)
  if not rect.intersects(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z)):continue
  for z in int(r.terrain_mesh.rows):
   for x in int(r.terrain_mesh.columns):
    var points:Array=Terrain.cell(r,x,z).map(func(p):return pose*p)
    var cell:=Rect2(Vector2(points[0].x,points[0].z),Vector2.ZERO)
    for p:Vector3 in points:cell=cell.expand(Vector2(p.x,p.z))
    if not rect.intersects(cell):continue
    for p:Vector3 in points:minimum=minf(minimum,p.y);maximum=maxf(maximum,p.y)
 check(is_finite(minimum) and absf(minimum-height)<.002 and absf(maximum-height)<.002,"entire foundation cell support is planar at "+str(height))
 report.get_or_add("bearing",[]).append({"target":height,"min":minimum,"max":maximum,"footprint":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
func catalog_entry(key:String)->Dictionary:
 for row:Dictionary in Props.catalog():
  if row.get("asset_path","")==ASSETS+"/"+SOURCES[key]+".glb":return row
 return {}
func piece_shapes(key:String,position:Vector3)->Array:
 var inventory:=data(OUT+"/"+key+"_macro_source_geometry.json")
 check(inventory.sha256==SOURCES[key],"source mesh inventory matches exact formal asset "+key)
 var pieces:Array=[]
 for mesh:Dictionary in inventory.meshes:
  if mesh.extras.get("rmmo_collision","")=="none":continue
  pieces.append(shape(City.vec(mesh.min)+position,City.vec(mesh.max)+position))
 return pieces
func verify_object_space(placements:Array)->void:
 var new_ids:Array=placements.map(func(p):return p.id)
 var parts:Dictionary={}
 for row:Dictionary in placements:
  var key:String="guild" if row.key=="landmark/guild" else "alarm"
  var actual:Dictionary=editor._doc._find(row.id);var full:=Foot.record_shape(actual)
  var pieces:=piece_shapes(key,City.vec(actual.position));parts[row.id]=pieces
  for existing:Dictionary in editor._doc.records:
   if existing.uuid in new_ids or existing.has("terrain_mesh") or existing.has("road_mesh"):continue
   if not Foot.overlaps(full,Foot.record_shape(existing)):continue
   check(not Foot.batches_overlap(pieces,Foot.record_shapes(existing)),"landmark source collision envelopes clear existing object "+str(existing.uuid))
   if failed:return
  for zone:Dictionary in City.resolve(editor._doc.map_meta).zones:
   var polygon:PackedVector2Array=[]
   for p:Array in zone.polygon:polygon.append(Vector2(p[0],p[1]))
   check(Geometry2D.intersect_polygons(full.polygon,polygon).is_empty(),"landmark avoids preserved zone "+zone.id)
  check(editor._doc.validate_save_record(actual)==OK,"native landmark record is saveable "+key)
 check(not Foot.batches_overlap(parts[placements[0].id],parts[placements[1].id]),"guild and alarm source envelopes remain separate")
func verify_preserved()->void:
 check(City.token(before.map_meta.get("building_instances",{}))==City.token(editor._doc.map_meta.get("building_instances",{})),"21 native house instances unchanged")
 check(editor._doc.map_meta.get("building_instances",{}).size()==21,"candidate still has exactly 21 native houses")
 check(City.token(before.map_meta.get("terrain_rivers",[]))==City.token(editor._doc.map_meta.get("terrain_rivers",[])),"complete river ownership and request metadata unchanged")
 check(City.token(City.resolve(before.map_meta).zones)==City.token(City.resolve(editor._doc.map_meta).zones),"R1-R5 unchanged")
 var expected_meta:Dictionary=before.map_meta.duplicate(true)
 expected_meta.editor_layout.roads=editor._doc.map_meta.editor_layout.roads.duplicate(true)
 expected_meta.editor_layout.road_surface=editor._doc.map_meta.editor_layout.road_surface.duplicate(true)
 expected_meta.town_reference.landmarks=editor._doc.map_meta.town_reference.landmarks.duplicate(true)
 expected_meta.town_reference.house_layout.cameras=editor._doc.map_meta.town_reference.house_layout.cameras.duplicate(true)
 check(City.token(expected_meta)==City.token(editor._doc.map_meta),"all other source, environment, water and house metadata unchanged")
 var expected_graph:Dictionary=City.resolve(before.map_meta).roads.duplicate(true)
 for n:Dictionary in expected_graph.nodes:
  if n.id==ROAD_END:n.position=[156.,7.5,203.75]
 check(City.token(expected_graph)==City.token(City.resolve(editor._doc.map_meta).roads),"only the existing guild endpoint changes; topology and widths unchanged")
 for old:Dictionary in before.records:
  if old.has("terrain_mesh") or old.has("road_mesh"):continue
  check(City.token(old)==City.token(editor._doc._find(old.uuid)),"original object and water record unchanged "+str(old.uuid))
 for p:Dictionary in baseline_build.props.placements:
  check(not editor._doc._find(p.id).is_empty(),"original reference prop retained "+str(p.id))
 check(baseline_build.props.placements.size()==77,"77 reference props retained separately from new landmarks")
 check(editor._doc.validate_save()==OK,"complete native landmark candidate validates for save")
func run()->void:
 create_timer(1800).timeout.connect(func():check(false,"landmark helper timeout");persist();quit(2))
 rpc_timeout_ms=300000
 for arg:String in OS.get_cmdline_user_args():
  if arg=="--apply":apply_requested=true
  elif arg.begins_with("--expected-sha="):expected_sha=arg.trim_prefix("--expected-sha=")
 check(expected_sha.length()==64 and expected_sha==FileAccess.get_sha256(CANDIDATE),"exact current --expected-sha is mandatory")
 report.merge({"apply":apply_requested,"candidate":CANDIDATE,"candidate_before_sha256":FileAccess.get_sha256(CANDIDATE),"formal_before_sha256":FileAccess.get_sha256(FORMAL)})
 if stopped():return
 for name_:String in ["build.json","housing_recipe.json","guild_macro_source_geometry.json","alarm_macro_source_geometry.json"]:pin(OUT.path_join(name_))
 pin(ASSETS+"/library.json")
 pin("res://tools/place_axel_guild_landmarks.gd")
 for key:String in SOURCES:
  pin(ASSETS+"/"+SOURCES[key]+".glb")
  check(FileAccess.get_sha256(ASSETS+"/"+SOURCES[key]+".glb")==SOURCES[key],"unchanged formally reviewed source "+key)
 baseline_build=data(OUT+"/build.json");recipe=data(OUT+"/housing_recipe.json");report.inputs=inputs
 check(baseline_build.get("candidate_sha256","")==expected_sha and baseline_build.get("failures",1)==0,"completed current build receipt pinned")
 check(baseline_build.get("houses",[]).size()==21 and recipe.get("houses",[]).size()==21,"watercourse/source refresh/seven-house stage already complete")
 check(baseline_build.get("props",{}).get("placements",[]).size()==77,"expected unchanged 77-prop stage")
 check(recipe.get("landmarks",[]).is_empty(),"landmarks not already added")
 if stopped():return
 var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=CANDIDATE;session.world3d_editor_doc=null
 editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false
 editor._draft_directory=OUT+"/landmark_drafts";root.add_child(editor);await settle();await wait_ready()
 if stopped():return
 before=editor._doc.recovery_snapshot();live_document=editor._doc
 var staged=Doc.new();staged.apply_recovery(before);editor._doc=staged
 check(staged.map_meta.get("town_reference",{}).get("landmarks",{}).is_empty(),"no native duplicate landmark registry")
 var listener:=TCPServer.new();port=31940
 while listener.listen(port,"127.0.0.1")!=OK:port+=1
 listener.stop();check(editor.start_mcp(port).ok,"current 3D MCP starts on loopback")
 if stopped():return
 var guild_foot:=Rect2(140,184,32,14);var tower_foot:=Rect2(138.45,141.45,5.1,5.1)
 var guild_core:=core_for_footprint(guild_foot);var tower_core:=core_for_footprint(tower_foot)
 if stopped():return
 var graph:Dictionary=City.resolve(staged.map_meta).roads;var ends:Array=graph.nodes.filter(func(n):return n.id==ROAD_END)
 check(ends.size()==1 and equivalent(ends[0].position,[156,7.5,198]),"only original guild entrance node is retreated")
 if stopped():return
 var args:={"strokes":[stroke(guild_core,7.5),stroke(tower_core,8.)],"road_nodes":[{"id":ROAD_END,"position":[156.,7.5,203.75]}],"expected_road_token":City.token(graph)}
 report.layout_request=args
 await operation("apply_terrain_layout",args)
 if stopped():return
 verify_bearing(guild_foot,7.5);verify_bearing(tower_foot,8.)
 if stopped():return
 var requests:Array=[Props.request("landmark/guild",catalog_entry("guild"),Vector3(140,7.8,198),0.,Vector3.ONE,false),Props.request("landmark/alarm",catalog_entry("alarm"),Vector3(141,8,144),0.,Vector3.ONE,false)]
 check(requests.all(func(r):return not r.entry.is_empty()),"both complete formal catalog assets found")
 if stopped():return
 var placed:=Props.apply_requests(staged,{"ok":true,"requests":requests})
 check(placed.ok and placed.ids.size()==2,"exactly two independent native assets imported through shared Props/Library")
 if stopped():return
 report.landmarks=placed.placements
 verify_object_space(placed.placements)
 if stopped():return
 # Final production road guard sees both full native assets. The tower's
 # high horns require its existing actual-geometry narrow phase, not a skip.
 var roads:Dictionary=editor._roads.prepare({})
 check(roads.ok,"full final native road/bridge/clearance protection with landmarks")
 report.final_road_validation={"ok":roads.ok,"error":roads.get("error",""),"conflicts":roads.get("conflicts",[]),"diff":roads.get("diff",{})}
 if stopped():return
 check(roads.diff.added==0 and roads.diff.updated==0 and roads.diff.removed==0,"final road guard does not require an uncommitted regeneration")
 if stopped():return
 var cameras:Array=[{"id":"macro_guild_forecourt","shot":"GUILD_MACRO","position":[156,9.2,231],"target":[156,13.2,191],"fov":65},{"id":"macro_guild_alarm_context","shot":"GUILD_ALARM_MACRO","position":[111,28,216],"target":[151,16,169],"fov":62}]
 staged.map_meta.town_reference.landmarks={"phase":"native_candidate_outdoor_visual_pending","project_supplementary_design":true,"placements":placed.placements,"cameras":cameras,"forecourt_empty_xz":[144,202,24,14],"central_clear_passage_xz":[153,201,6,34],"alarm_interior_traversal":false}
 staged.map_meta.town_reference.house_layout.cameras.append_array(cameras)
 verify_preserved()
 if stopped():return
 var after:Dictionary=staged.recovery_snapshot()
 editor._doc=live_document;live_document.apply_recovery(after);live_document.commit_recovery_change(before)
 check(live_document.undo() and City.token(contents(live_document.recovery_snapshot()))==City.token(contents(before)),"one native undo restores all prior terrain/roads/objects/metadata")
 check(live_document.redo() and City.token(contents(live_document.recovery_snapshot()))==City.token(contents(after)),"one native redo restores both landmarks and approaches")
 inputs_unchanged();check(FileAccess.get_sha256(CANDIDATE)==expected_sha,"candidate unchanged throughout private dry-run stage")
 if stopped():return
 report.phase="native_preflight_complete_visual_pending";report.native_reopen="pending apply";report.house_count=21;report.reference_prop_count=77;report.landmark_count=2;report.cameras=cameras;persist()
 if not apply_requested:editor._mcp.stop();quit(0);return
 recipe.landmarks=placed.placements;recipe.cameras.append_array(cameras)
 recipe.road_graph=City.resolve(after.map_meta).roads.duplicate(true);recipe.road_settings=City.resolve(after.map_meta).road_surface.settings.duplicate(true)
 var updated_build:=baseline_build.duplicate(true)
 updated_build.landmarks={"placements":placed.placements,"count":2,"visual":"pending outdoor macro review","native_receipt":OUT+"/guild_landmarks_apply.json","cameras":cameras,"tool_path":"res://tools/place_axel_guild_landmarks.gd","tool_sha256":inputs["res://tools/place_axel_guild_landmarks.gd"]}
 updated_build.phase="candidate_landmarks_saved_visual_pending"
 check(City.token(updated_build.houses)==City.token(baseline_build.houses) and City.token(updated_build.props)==City.token(baseline_build.props),"build retains exact 21-house and 77-prop receipts")
 check(City.token(updated_build.get("watercourse",{}))==City.token(baseline_build.get("watercourse",{})),"build watercourse receipt unchanged")
 report.pending_recipe=recipe;report.pending_build=updated_build;report.phase="ready_to_save";persist()
 inputs_unchanged();check(FileAccess.get_sha256(CANDIDATE)==expected_sha,"exact candidate SHA before atomic native save")
 if stopped():return
 check(live_document.save(CANDIDATE)==OK,"native atomic candidate save with conflict detection")
 if stopped():return
 report.saved=true;report.candidate_sha256=FileAccess.get_sha256(CANDIDATE);persist()
 var reopened=Doc.open_file(CANDIDATE)
 check(reopened!=null and reopened.validate_save()==OK,"native candidate save/reopen validation")
 if reopened!=null:check(City.token(reopened.records)==City.token(live_document.records) and City.token(reopened.map_meta)==City.token(live_document.map_meta),"exact native save/reopen identity")
 inputs_unchanged()
 if stopped():return
 report.native_reopen="passed"
 check(atomic_json(OUT+"/housing_recipe.json",recipe),"atomic recipe receipt")
 if stopped():return
 updated_build.candidate_sha256=report.candidate_sha256
 updated_build.authoring_inputs["housing_recipe.json"]=FileAccess.get_sha256(OUT+"/housing_recipe.json")
 check(atomic_json(OUT+"/build.json",updated_build),"atomic build receipt")
 if stopped():return
 report.erase("pending_recipe");report.erase("pending_build");report.phase="candidate_landmarks_complete_visual_pending";persist()
 editor._mcp.stop();quit(0)
