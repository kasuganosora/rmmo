extends "res://tools/review_axel_macro_layout.gd"
## Seven existing complete native house templates. Candidate-only, default dry run.
## No terrain, road, prop, source template, or formal-map mutation.
const Token=preload("res://scripts/world3d/city_layout.gd")
var report:Dictionary={"phase":"starting","saved":false,"failures":[]}
func require(ok:bool,message:String)->bool:
 if not ok:report.failures.append(message);report.phase="failed";receipt();push_error(message)
 return ok
func atomic_json(path:String,value:Dictionary)->bool:
 var temporary:=path+".macro.tmp";var file:=FileAccess.open(temporary,FileAccess.WRITE)
 if file==null:return false
 file.store_string(JSON.stringify(value,"\t"));file.close()
 return DirAccess.rename_absolute(temporary,path)==OK
func receipt():atomic_json(OUT+"/macro_layout_extension.json",report)
func content(snapshot:Dictionary)->Dictionary:return {"records":snapshot.records,"map_meta":snapshot.map_meta}
func run():
 var apply:bool="--apply" in OS.get_cmdline_user_args();var expected:=""
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--expected-sha="):expected=arg.trim_prefix("--expected-sha=")
 var sha:=FileAccess.get_sha256(MAP)
 if not require(not expected.is_empty() and expected==sha,"Exact current candidate --expected-sha is required"):quit(1);return
 var inputs:Dictionary={}
 for name_:String in ["build.json","housing_recipe.json","house_templates.json","macro_layout_next_batch.json"]:inputs[name_]=FileAccess.get_sha256(OUT.path_join(name_))
 var build:=read_json(OUT+"/build.json");var recipe:=read_json(OUT+"/housing_recipe.json");var plan:=read_json(OUT+"/macro_layout_next_batch.json")
 report.merge({"apply":apply,"candidate_before_sha256":sha,"inputs":inputs,"houses":[],"source_plan_candidate_sha256":plan.candidate_sha256})
 if not require(build.get("candidate_sha256","")==sha and build.get("failures",1)==0,"Current build receipt matches candidate"):quit(1);return
 if not require(build.houses.size()==14 and recipe.houses.size()==14,"Only the original 14-house stage may receive this seven-house batch"):quit(1);return
 var live=Doc.open_file(MAP)
 if not require(live!=null,"Open current native candidate"):quit(1);return
 var before:Dictionary=live.recovery_snapshot();var staged=Doc.new();staged.apply_recovery(before)
 var old_meta:Dictionary=before.map_meta.duplicate(true);var old_records:Dictionary={}
 for r:Dictionary in before.records:old_records[r.uuid]=Token.token(r)
 var templates:Dictionary={}
 for t:Dictionary in read_json(OUT+"/house_templates.json").templates:templates[t.id]=t
 var selected:Array=plan.next_batch.filter(func(h):return int(h.planning_home_1based)!=24)
 if not require(selected.size()==7,"Exactly seven approved macro proposals, excluding #24"):quit(1);return
 for h:Dictionary in selected:
  if not require(not recipe.houses.any(func(r):return r.id==h.id),"No duplicate macro house id "+h.id):quit(1);return
  var t:Dictionary=templates[h.template_id]
  if not require(FileAccess.get_sha256(t.loaded_path)==h.template_sha256,"Exact reviewed complete template "+h.id):quit(1);return
  var loaded:=read_json(t.loaded_path);var basis:=Basis(Vector3.UP,deg_to_rad(h.yaw))
  var support:=Support.sample(staged,loaded.records,Vector3(h.position_xz[0],-1000,h.position_xz[1]),basis,t.parameters)
  if not require(support.ok,"Real ground-floor support "+h.id):quit(1);return
  var pos:Vector3=support.position;var door:=Vector3(h.door_threshold_xz[0],0,h.door_threshold_xz[1]);var ground:float=Props.ground(staged,door)
  var rise:float=pos.y+float(t.parameters.base_height)-ground
  if not require(is_finite(ground) and rise>=-.02 and rise<=.18,"Door threshold within existing terrain limit "+h.id):quit(1);return
  var result:=Library.place_buildings(staged,oriented(loaded,h.yaw),pos,"扩街住宅 "+str(h.planning_home_1based))
  if not require(result.ok,"Native complete prefab placement "+h.id+": "+str(result.get("error",""))):report.placement_error=result;receipt();quit(1);return
  var id:String=staged._find(result.ids[0]).building.id
  var entrance:Vector3=pos+basis*B.vec(t.entrance)
  var row:={"id":h.id,"shot":"MACRO_WEST" if h.planning_home_1based<20 else "MACRO_GUILD","label":"扩街住宅 "+str(h.planning_home_1based),"building_id":id,"template_id":h.template_id,"position":B.arr(pos),"yaw":h.yaw,"parameters":staged.map_meta.building_instances[id].parameters,"entrance":B.arr(entrance),"terrain_range":[support.lowest,support.highest],"component_ids":result.ids,"template_sha256":h.template_sha256,"threshold_above_local_ground":rise}
  report.houses.append(row)
  # Preserve actual access graph. Resolve the existing tip and its sole road neighbor.
  var tip_node:Dictionary={};var best:=INF
  for node:Dictionary in recipe.road_graph.nodes:
   var distance:=Vector2(node.position[0],node.position[2]).distance_to(Vector2(h.existing_access_tip_xz[0],h.existing_access_tip_xz[1]))
   if distance<best:best=distance;tip_node=node
  if not require(best<.001,"Existing access endpoint unchanged "+h.id):quit(1);return
  var edges:Array=recipe.road_graph.edges.filter(func(e):return e.from==tip_node.id or e.to==tip_node.id)
  if not require(edges.size()==1,"Existing entrance spur has one connection "+h.id):quit(1);return
  var neighbor_id:String=edges[0].to if edges[0].from==tip_node.id else edges[0].from
  var neighbor:Dictionary=recipe.road_graph.nodes.filter(func(n):return n.id==neighbor_id)[0]
  recipe.houses.append({"id":h.id,"shot":row.shot,"label":row.label,"template_id":h.template_id,"position":h.position_xz,"ground_y":pos.y,"yaw":h.yaw,"entrance":row.entrance,"entrance_xz":[entrance.x,entrance.z],"door_threshold":[door.x,pos.y+float(t.parameters.base_height),door.z],"access_points":[h.existing_access_tip_xz,[neighbor.position[0],neighbor.position[2]]],"grade":{"required":false},"notes":"Existing native entry road unchanged. Short unpaved ground/step transition retained; outdoor visual review pending."})
 var cameras:Array=[{"id":"macro_west_gate_overview","shot":"MACRO_WEST","position":[43,27,183],"target":[85,8,204],"fov":58},{"id":"macro_guild_outer_overview","shot":"MACRO_GUILD","position":[119,19,146],"target":[143,9,175],"fov":55}]
 recipe.cameras.append_array(cameras)
 var layout:Dictionary=staged.map_meta.get("town_reference",{}).get("house_layout",{})
 if not require(layout.get("placements",[]).size()==14,"Existing 14 native house-layout placements present"):quit(1);return
 layout.placements.append_array(report.houses);layout.cameras=recipe.cameras.duplicate(true)
 for id:String in old_records:
  if not require(Token.token(staged._find(id))==old_records[id],"Original record unchanged "+id):quit(1);return
 var preserved:Dictionary=staged.map_meta.duplicate(true)
 for h:Dictionary in report.houses:preserved.building_instances.erase(h.building_id)
 preserved.town_reference.house_layout=old_meta.town_reference.house_layout.duplicate(true)
 if not require(Token.token(preserved)==Token.token(old_meta),"All original metadata outside appended house registry/layout preserved"):quit(1);return
 if not require(staged.validate_save()==OK,"Staged native save validation"):quit(1);return
 var after:Dictionary=staged.recovery_snapshot();live.apply_recovery(after);live.commit_recovery_change(before)
 if not require(live.undo() and Token.token(content(live.recovery_snapshot()))==Token.token(content(before)),"Single native undo restores original document"):quit(1);return
 if not require(live.redo() and Token.token(content(live.recovery_snapshot()))==Token.token(content(after)),"Single native redo restores seven-house extension"):quit(1);return
 report.phase="native_preflight_complete";report.house_count=21;report.visual="pending";report.native_reopen="pending";receipt()
 if not apply:quit();return
 for name_:String in inputs:
  if not require(FileAccess.get_sha256(OUT.path_join(name_))==inputs[name_],"Concurrent receipt input unchanged "+name_):quit(1);return
 if not require(FileAccess.get_sha256(MAP)==sha,"Candidate unchanged before atomic native save"):quit(1);return
 # Save a recovery receipt before committing. It contains exact pending receipts,
 # so a later receipt write failure is recoverable without reapplying houses.
 build.houses.append_array(report.houses);build.phase="macro_houses_saved";build.macro_extension={"count":7,"visual":"pending","source_candidate_sha256":sha}
 report.pending_recipe=recipe;report.pending_build=build;report.phase="ready_to_save";receipt()
 if not require(live.save(MAP)==OK,"Native atomic candidate save"):quit(1);return
 report.saved=true;report.candidate_sha256=FileAccess.get_sha256(MAP);receipt()
 var reopened=Doc.open_file(MAP)
 if not require(reopened!=null and reopened.validate_save()==OK,"Native saved candidate reopens"):quit(1);return
 if not require(Token.token(reopened.records)==Token.token(live.records) and Token.token(reopened.map_meta)==Token.token(live.map_meta),"Native reopen identity"):quit(1);return
 report.native_reopen="passed"
 if not require(atomic_json(OUT+"/housing_recipe.json",recipe),"Atomic recipe receipt"):quit(1);return
 build.candidate_sha256=report.candidate_sha256;build.authoring_inputs["housing_recipe.json"]=FileAccess.get_sha256(OUT+"/housing_recipe.json");build.authoring_inputs["macro_layout_next_batch.json"]=inputs["macro_layout_next_batch.json"]
 build.macro_extension.native_receipt=OUT+"/macro_layout_extension.json"
 if not require(atomic_json(OUT+"/build.json",build),"Atomic build receipt"):quit(1);return
 report.erase("pending_recipe");report.erase("pending_build");report.phase="candidate_macro_extension_complete";receipt();quit()
