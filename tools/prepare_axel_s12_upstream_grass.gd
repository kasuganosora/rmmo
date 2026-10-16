extends SceneTree
## Candidate-only preparation. Outputs existing 3D MCP place_asset requests;
## never writes a map. Root reviews actual water-bank imagery before execution.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Library=preload("res://scripts/world_editor/prefab_library.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Profile=preload("res://scripts/world3d/terrain_river_profile.gd")
const Zones=preload("res://scripts/world3d/planning_zones.gd")
const Support=preload("res://scripts/world3d/terrain_plant_support.gd")
const Keys=preload("res://scripts/world_editor/asset_thumbnails.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
const MAP="D:/code/rmmo_runtime/cache/world3d/axel_town_houses_20261014/map.gltf"
const PUB="D:/code/rmmo_runtime/review_artifacts/reference_grass_clumps/published.json"
func _initialize():call_deferred("run")
func read_json(path:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path))
func fail(message:String):push_error(message);quit(1)
func run():
 if "--apply" in OS.get_cmdline_user_args():fail("This preparation tool cannot save. Root must explicitly execute reviewed requests through the existing 3D MCP transaction after visual approval.");return
 var expected:=""
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--expected-sha="):expected=arg.trim_prefix("--expected-sha=")
 var sha:=FileAccess.get_sha256(MAP)
 if expected.is_empty() or expected!=sha:fail("Provide the exact post-watercourse candidate --expected-sha; refusing stale or unpinned preview.");return
 var doc=Doc.open_file(MAP)
 if doc==null:fail("Cannot open candidate");return
 var river:Dictionary={}
 for layer:Dictionary in doc.map_meta.get("terrain_rivers",[]):
  if layer.id=="axel_s12_stream":river=layer
 # Saved native layer settings, not an uncommitted requested river recipe.
 var settings:Dictionary=river.get("settings",{})
 if settings.is_empty():settings=river.get("request",{})
 if not settings.has("water_levels") or settings.get("points",[]).size()<10:fail("Continuous profiled S12 watercourse must already be saved before preview.");return
 var curve:=Profile.prepare(settings)
 if not curve.ok:fail(str(curve));return
 var support:=Support.new();support.setup(doc.records.filter(func(r):return r.has("terrain_mesh") and r.get("collision")!="none"))
 var obstacles:Array=Zones.obstacles(doc.map_meta,"vegetation")
 for r:Dictionary in doc.records:
  if r.has("terrain_mesh"):continue
  obstacles.append_array(Foot.record_shapes(r))
 var rows:Array=read_json(PUB).entries;var sources:Array=[]
 for row:Dictionary in rows:
  var loaded:=Library.read(row.entry)
  if not loaded.ok or loaded.records.size()!=1:fail("Expected reviewed one-record complete grass prefab");return
  var model:String=loaded.records[0].asset_path
  if FileAccess.get_sha256(model)!=row.library_model_sha256:fail("Published grass model SHA drift");return
  sources.append({"entry":row.entry,"record":loaded.records[0],"model_sha256":row.library_model_sha256,"prefab_sha256":FileAccess.get_sha256(row.entry.prefab_path)})
 var requests:Array=[];var skipped:={"terrain":0,"wet":0,"obstacle":0};var patches:Array=[]
 for patch in 8:
  var z:=10.+patch*11.;var closest:=0;var error:=INF
  for i in curve.path.size():
   var delta:=absf(float(curve.path[i][1])-z)
   if delta<error:error=delta;closest=i
  var p:=Vector2(curve.path[closest][0],curve.path[closest][1])
  var a:=Vector2(curve.path[maxi(0,closest-1)][0],curve.path[maxi(0,closest-1)][1]);var b:=Vector2(curve.path[mini(curve.path.size()-1,closest+1)][0],curve.path[mini(curve.path.size()-1,closest+1)][1])
  var tangent:=(b-a).normalized();var normal:=Vector2(-tangent.y,tangent.x)*(1. if patch%2==0 else -1.)
  var count_before:=requests.size()
  for slot in 6:
   var source:Dictionary=sources[(patch+slot)%sources.size()]
   var point:=p+tangent*((slot%3)-1)*1.25+normal*(3.5+float(int(slot/3))*1.1)
   if point.y<5 or point.y>95:continue
   var height:float=support.sample(Vector3(point.x,0,point.y))
   if not is_finite(height):skipped.terrain+=1;continue
   var r:Dictionary=source.record.duplicate(true)
   # Prefab pivot is ground-centred; keep the complete native authored record.
   var position:=Vector3(point.x,height,point.y)
   r.position=[float(r.position[0])+position.x,float(r.position[1])+position.y,float(r.position[2])+position.z]
   var shape:=Foot.record_shape(r);var safe:=true
   for corner:Vector2 in shape.polygon:
    var h:float=support.sample(Vector3(corner.x,0,corner.y));var station:=Profile.sample(corner,curve.path,curve.levels)
    if not is_finite(h) or absf(h-height)>.08:safe=false;skipped.terrain+=1;break
    if h<=float(station.level)+.12 or float(station.distance)<=float(settings.width)*.5+.15:safe=false;skipped.wet+=1;break
   if not safe:continue
   if Foot.batches_overlap([shape],obstacles):skipped.obstacle+=1;continue
   requests.append({"tool":"place_asset","arguments":{"asset_id":Keys.key_for(source.entry),"position":[point.x,height,point.y]},"patch":patch,"model_sha256":source.model_sha256,"prefab_sha256":source.prefab_sha256,"full_bounds":{"position":[shape.bounds.position.x,shape.bounds.position.y,shape.bounds.position.z],"size":[shape.bounds.size.x,shape.bounds.size.y,shape.bounds.size.z]}})
   obstacles.append(shape)
  patches.append({"patch":patch,"count":requests.size()-count_before})
 var report:={"status":"prepared_not_applied_not_visual_accepted","candidate_sha256":sha,"source_manifest_sha256":FileAccess.get_sha256(PUB),"maximum":48,"count":requests.size(),"patches":patches,"skipped":skipped,"requests":requests,"execution_contract":["Root first reviews actual water-bank images and these placements.","Use existing place_asset via current 3D MCP on staged native document; recheck candidate and each source SHA.","Failure rolls back whole batch. Preserve all existing records and metadata. Collapse to one native undo/redo transaction.","Validate save and native reopen before updating build.candidate_sha256 and addition receipt; never publish formal map from this helper.","Do not raise target count to compensate rejected slots. This is fixed placement, not prefab scatter support."],"unverified":["Actual HTTP placement and undo/save/reopen","GPU roots, wet-edge composition, native wind/LOD and actual automatic batch counts"]}
 FileAccess.open(OUT+"/s12_upstream_grass_native_plan.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("Prepared ",requests.size()," complete prefab requests; map unchanged.");quit()
