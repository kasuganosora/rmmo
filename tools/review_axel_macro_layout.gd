extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Library=preload("res://scripts/world_editor/prefab_library.gd")
const Support=preload("res://tools/axel_house_placement_support.gd")
const Props=preload("res://tools/axel_house_reference_props.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
const MAP="D:/code/rmmo_runtime/cache/world3d/axel_town_houses_20261014/map.gltf"
func _initialize():call_deferred("run")
func read_json(path:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path))
func oriented(loaded:Dictionary,yaw:float)->Dictionary:
 var copy:=loaded.duplicate(true);var basis:=Basis(Vector3.UP,deg_to_rad(yaw))
 for r:Dictionary in copy.records:
  r.position=B.arr(basis*B.vec(r.position));r.rotation=B.arr((basis*Basis.from_euler(B.vec(r.rotation)*PI/180)).get_euler()*180/PI)
 for v:Dictionary in copy.building_instances.values():v.position=[0,0,0];v.yaw=yaw
 return copy
func run():
 var plan:=read_json(OUT+"/macro_layout_next_batch.json");var sha:=FileAccess.get_sha256(MAP)
 if sha!=plan.candidate_sha256:push_error("Candidate changed; repin after reviewing input");quit(1);return
 var doc=Doc.open_file(MAP);var templates:Dictionary={}
 for t:Dictionary in read_json(OUT+"/house_templates.json").templates:templates[t.id]=t
 var report:={"candidate_sha256":sha,"plan_sha256":FileAccess.get_sha256(OUT+"/macro_layout_next_batch.json"),"saved":false,"houses":[]}
 for h:Dictionary in plan.next_batch:
  var t:Dictionary=templates[h.template_id];var loaded:=read_json(t.loaded_path)
  if FileAccess.get_sha256(t.loaded_path)!=h.template_sha256:push_error("Template changed");quit(1);return
  var origin:=Vector3(h.position_xz[0],-1000,h.position_xz[1]);var basis:=Basis(Vector3.UP,deg_to_rad(h.yaw))
  var sampled:=Support.sample(doc,loaded.records,origin,basis,t.parameters)
  var row:={"id":h.id,"planned_number":h.planning_home_1based,"support":sampled}
  if sampled.ok:
   origin=sampled.position;sampled.position=B.arr(origin)
   var door:=Vector3(h.door_threshold_xz[0],0,h.door_threshold_xz[1]);var ground:float=Props.ground(doc,door)
   row.threshold_above_local_ground=origin.y+float(t.parameters.base_height)-ground
   var result:=Library.place_buildings(doc,oriented(loaded,h.yaw),origin,h.id)
   row.native_placement=result;row.ok=result.ok and row.threshold_above_local_ground<=.18
  else:row.ok=false
  report.houses.append(row);print(JSON.stringify(row))
 report.all_passed=report.houses.all(func(r):return r.ok);report.candidate_unchanged=sha==FileAccess.get_sha256(MAP)
 FileAccess.open(OUT+"/macro_layout_native_preflight.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));quit()
