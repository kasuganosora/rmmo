extends "res://tools/test_world3d_mcp.gd"
## Candidate-only current 3D MCP authoring. Default dry-run never saves a map.
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const Formal="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const Profile=preload("res://scripts/world3d/terrain_river_profile.gd")
var plan:Dictionary
var report:Dictionary={"saved":false,"operations":[],"placements":[],"rejections":{},"crop_regions":[]}
var obstacles:Array=[]
var terrain:Array=[]
var rivers:Array=[]
var wall:Array=[]
var rng:=RandomNumberGenerator.new()
var palette:Dictionary={}
var error_counts:Dictionary={}
var probe_only:=false
var apply_requested:=false
var wall_half_depth:=0.0
var future_sites:Dictionary={}
var tree_support:Dictionary={}
var tree_support_loaded:=false
var tree_support_error:=""
func read(path:String):return JSON.parse_string(FileAccess.get_file_as_string(path))
func persist():
 var file:=OUT+("/functional_vegetation_build.json" if apply_requested else ("/functional_vegetation_fixture_probe.json" if probe_only else "/functional_vegetation_dryrun.json"))
 var pending:=file+".pending";var f:=FileAccess.open(pending,FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close();Atomic.publish(pending,file)
func reject(reason:String):report.rejections[reason]=int(report.rejections.get(reason,0))+1
func v(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
func ground(p:Vector2)->float:
 for r:Dictionary in terrain:
  var pose:=Terrain.transform(r);var local:=pose.affine_inverse()*Vector3(p.x,0,p.y);var h:=Terrain.sample(r,local)
  if is_finite(h):return (pose*Vector3(local.x,h,local.z)).y
 return NAN
func rect_poly(a:Array)->PackedVector2Array:return PackedVector2Array([Vector2(a[0],a[1]),Vector2(a[0]+a[2],a[1]),Vector2(a[0]+a[2],a[1]+a[3]),Vector2(a[0],a[1]+a[3])])
func overlaps(a:PackedVector2Array,b:PackedVector2Array)->bool:return not Geometry2D.intersect_polygons(a,b).is_empty()
func asset_info(label:String)->Dictionary:return palette[label]
func load_tree_support()->bool:
 if tree_support_loaded:return tree_support_error.is_empty()
 tree_support_loaded=true
 var path:=OUT+"/tree_basal_geometry_probe.json"
 if not FileAccess.file_exists(path):tree_support_error="missing basal geometry evidence";return false
 var proof:Dictionary=read(path)
 for label:String in [plan.tree_palette.woodland,plan.tree_palette.orchard]:
  var asset:Dictionary={};var measured:Dictionary={}
  for item:Dictionary in plan.assets:
   if item.label==label:asset=item;break
  for item:Dictionary in proof.get("assets",[]):
   if item.label==label:measured=item;break
  if asset.is_empty() or measured.is_empty() or asset.get("models",[]).is_empty():tree_support_error="missing measured tree "+label;return false
  var model:Dictionary=asset.models[0]
  if str(model.path).replace("\\","/")!=str(measured.path).replace("\\","/") or model.sha256!=measured.sha256 or FileAccess.get_sha256(model.path)!=model.sha256:
   tree_support_error="basal geometry source changed "+label;return false
  var size_:Vector3=v(palette[label].size);var low:Vector3=v(palette[label].low)
  var shift:=Vector3(-low.x-size_.x*.5,-low.y,-low.z-size_.z*.5)
  # Prefab Foot bounds already include its stored native root offset. The
  # measured GLB hull includes that offset too; don't subtract it twice.
  if asset.kind=="prefab_path":
   var prefab:Dictionary=read(asset.asset_id)
   if prefab.records.size()!=1 or v(prefab.records[0].rotation)!=Vector3.ZERO or v(prefab.records[0].size)!=Vector3.ONE:
    tree_support_error="unsupported basal prefab transform "+label;return false
   shift+=v(prefab.records[0].position)
  if shift.distance_to(v(measured.native_centered_origin_shift))>.00001 or size_.distance_to(v(measured.full_crown_size))>.00001:
   tree_support_error="basal geometry pivot changed "+label;return false
  var hull:=PackedVector2Array()
  for band:Dictionary in measured.bands:
   if absf(float(band.height_above_actual_min_m)-.35)<.000001:
    for point:Array in band.hull_xz:hull.append(Vector2(point[0],point[1]))
  if hull.size()<3:tree_support_error="missing actual 0.35m basal hull "+label;return false
  tree_support[label]={"hull":hull,"source_sha256":measured.sha256}
 report.basal_support_evidence={"path":path,"sha256":FileAccess.get_sha256(path),"sampling":"actual indexed collision trunk 0.35m basal hull; 0.15m edge/interior sampling; original 0.35m height threshold retained","full_crown_clearance_unchanged":true}
 return true
func root_support(label:String,p:Vector2,y:float,kind:String,full_poly:PackedVector2Array)->Dictionary:
 var points:=full_poly
 if kind=="tree":
  if not load_tree_support():return {"ok":false,"reason":"root_geometry_evidence", "error":tree_support_error}
  var hull:PackedVector2Array=tree_support[label].hull
  points=PackedVector2Array([p]);var bounds:=Rect2(hull[0],Vector2.ZERO)
  for i in hull.size():
   bounds=bounds.expand(hull[i])
   var end:=hull[(i+1)%hull.size()];var steps:=maxi(1,int(ceil(hull[i].distance_to(end)/.15)))
   for j in steps+1:points.append(p+hull[i].lerp(end,float(j)/steps))
  for ix in range(int(floor(bounds.position.x/.15)),int(ceil(bounds.end.x/.15))+1):
   for iz in range(int(floor(bounds.position.y/.15)),int(ceil(bounds.end.y/.15))+1):
    var q:=Vector2(ix*.15,iz*.15)
    if Geometry2D.is_point_in_polygon(q,hull):points.append(p+q)
 var low:=y;var high:=y
 for q:Vector2 in points:
  var h:=ground(q)
  if not is_finite(h):return {"ok":false,"reason":"root_slope"}
  low=minf(low,h);high=maxf(high,h)
  if absf(h-y)>(.35 if kind=="tree" else .12):return {"ok":false,"reason":"root_slope","ground_min":low,"ground_max":high,"center_y":y}
 return {"ok":true,"ground_min":low,"ground_max":high,"center_y":y,"samples":points.size(),"domain":"actual_basal_hull" if kind=="tree" else "full_bounds"}
func precheck(label:String,p:Vector2,kind:String)->Dictionary:
 var a:=asset_info(label);var low:=v(a.low);var size_:=v(a.size);var y:=ground(p)
 if not is_finite(y):return {"ok":false,"reason":"no_ground"}
 var radius:=Vector2(size_.x,size_.z).length()*.5
 var wall_distance:=INF
 for i in wall.size()-1:wall_distance=minf(wall_distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,Vector2(wall[i][0],wall[i][1]),Vector2(wall[i+1][0],wall[i+1][1]))))
 if wall_distance-radius-wall_half_depth<15:return {"ok":false,"reason":"wall_15m"}
 var poly:=rect_poly([p.x-size_.x/2,p.y-size_.z/2,size_.x,size_.z])
 for z:Dictionary in plan.exclusions.zones:
  var zp:=PackedVector2Array();for q:Array in z.polygon:zp.append(Vector2(q[0],q[1]))
  if overlaps(poly,zp):return {"ok":false,"reason":"reserved_"+str(z.id)}
 for z:Dictionary in plan.exclusions.special_building_plots:
  if overlaps(poly,rect_poly(z.rect)):return {"ok":false,"reason":"landmark_"+str(z.id)}
 for key:String in future_sites:
  if key.ends_with("_polygon"):
   var reserve:=PackedVector2Array();for q:Array in future_sites[key]:reserve.append(Vector2(q[0],q[1]))
   for grown in Geometry2D.offset_polygon(reserve,float(future_sites.get("margin_m",.6))):
    if overlaps(poly,grown):return {"ok":false,"reason":"future_"+key}
  elif key.ends_with("_access_points_xz"):
   var line:Array=future_sites[key];var width:=float(future_sites.get(key.trim_suffix("_points_xz")+"_width",2.6))
   for i in line.size()-1:
    if p.distance_to(Geometry2D.get_closest_point_to_segment(p,Vector2(line[i][0],line[i][1]),Vector2(line[i+1][0],line[i+1][1])))<radius+width*.5+float(future_sites.get("margin_m",.6)):return {"ok":false,"reason":"future_"+key}
 for key in ["guild_forecourt_rect","market_rect"]:
  if overlaps(poly,rect_poly(plan.exclusions[key])):return {"ok":false,"reason":key}
 for camera:Dictionary in editor._doc.map_meta.get("town_reference",{}).get("house_layout",{}).get("cameras",[]):
  if not camera.has("position") or not camera.has("target"):continue
  var eye:=v(camera.position);var aim:=v(camera.target)
  if p.distance_to(Geometry2D.get_closest_point_to_segment(p,Vector2(eye.x,eye.z),Vector2(aim.x,aim.z)))<radius+1.:return {"ok":false,"reason":"camera_corridor"}
 for field:Dictionary in plan.fields:
  var fp:=PackedVector2Array();for q:Array in field.polygon:fp.append(Vector2(q[0],q[1]))
  if overlaps(poly,fp):return {"ok":false,"reason":"field"}
 var support:=root_support(label,p,y,kind,poly)
 if not support.ok:return support
 for river:Dictionary in rivers:
  var sample:=Profile.sample(p,river.profile.path,river.profile.levels)
  if sample.distance<float(river.request.width)*.5+radius+.45 or (sample.distance<float(river.request.width)*.5+radius+5. and y<sample.level+.12):return {"ok":false,"reason":"wet_bank"}
 var box:=AABB(Vector3(p.x-size_.x/2,y,p.y-size_.z/2),size_)
 for item:Dictionary in obstacles:
  var b:AABB=item.bounds
  var clearance:=1. if item.house else .4
  var expanded:=Rect2(Vector2(b.position.x,b.position.z),Vector2(b.size.x,b.size.z)).grow(clearance)
  if not expanded.intersects(Rect2(poly[0],Vector2(size_.x,size_.z)),true):continue
  # Roads/full crowns remain conservatively clear even if their Y differs.
  return {"ok":false,"reason":"occupied_"+str(item.id)}
 return {"ok":true,"center":[p.x,y,p.y],"origin":[p.x-(low.x+size_.x/2),y-low.y,p.y-(low.z+size_.z/2)],"bounds":box,"root_support":support}
func inland_full_bounds_inside_city(label:String,p:Vector2)->bool:
 if wall.size()<4:return false
 var boundary:=PackedVector2Array()
 for q:Array in wall:boundary.append(Vector2(q[0],q[1]))
 if boundary[0]==boundary[-1]:boundary.remove_at(boundary.size()-1)
 var size_:Vector3=v(palette[label].size)
 var footprint:=rect_poly([p.x-size_.x*.5,p.y-size_.z*.5,size_.x,size_.z])
 return Geometry2D.clip_polygons(footprint,boundary).is_empty()
func place_inland_foliage(placement:Callable=Callable())->Dictionary:
 var result:Dictionary={"grass":0,"shrubs":0,"regions":[],"attempts":0,"rejections":{},"accepted":[]}
 var config:Dictionary=plan.get("inland_foliage",{})
 if not config.get("enabled",false):return result
 var local_rng:=RandomNumberGenerator.new();local_rng.seed=int(config.seed)
 var operation_:Callable=placement if placement.is_valid() else Callable(self,"place")
 var regions:Array=[]
 for region:Dictionary in plan.tree_regions:
  var polygon:=PackedVector2Array()
  for q:Array in region.polygon:polygon.append(Vector2(q[0],q[1]))
  var expanded:Array=Geometry2D.offset_polygon(polygon,float(config.expand_m),Geometry2D.JOIN_ROUND)
  if expanded.is_empty():continue
  var bounds:=Rect2(expanded[0][0],Vector2.ZERO)
  for shape:PackedVector2Array in expanded:
   for q:Vector2 in shape:bounds=bounds.expand(q)
  regions.append({"id":region.id,"polygons":expanded,"bounds":bounds,"grass":0,"shrubs":0})
 # Local shuffle leaves the tree and river RandomNumberGenerator unchanged.
 for i in range(regions.size()-1,0,-1):
  var j:=local_rng.randi_range(0,i);var saved:Dictionary=regions[i];regions[i]=regions[j];regions[j]=saved
 for kind:String in ["shrub","grass"]:
  var key:String="shrubs" if kind=="shrub" else "grass"
  var budget:int=int(plan.counts.shrubs_requested if kind=="shrub" else plan.counts.grass_requested)
  var target:=mini(int(config.shrub_target if kind=="shrub" else config.grass_target),budget)
  var per_region:int=int(config.max_shrubs_per_region if kind=="shrub" else config.max_grass_per_region)
  var labels:Array=config.shrub_labels if kind=="shrub" else config.grass_labels
  for round_ in per_region:
   if result[key]>=target:break
   for region:Dictionary in regions:
    if result[key]>=target:break
    if region[key]>=per_region:continue
    for attempt in int(config.attempts_per_region_round):
     result.attempts+=1
     var bounds:Rect2=region.bounds
     var p:=bounds.position+Vector2(local_rng.randf(),local_rng.randf())*bounds.size
     var included:=false
     for shape:PackedVector2Array in region.polygons:
      if Geometry2D.is_point_in_polygon(p,shape):included=true;break
     if not included:continue
     var label:String=labels[(round_+attempt+regions.find(region))%labels.size()]
     if not inland_full_bounds_inside_city(label,p):
      result.rejections["outside_city"]=int(result.rejections.get("outside_city",0))+1;continue
     var proof:=precheck(label,p,kind)
     if not proof.ok:
      result.rejections[proof.reason]=int(result.rejections.get(proof.reason,0))+1;continue
     if not await operation_.call(label,p,kind):continue
     result[key]+=1;region[key]+=1
     result.accepted.append({"region":region.id,"kind":kind,"label":label,"center":proof.center,"root_support":proof.root_support,"full_bounds_inside_city":true})
     break
 for region:Dictionary in regions:result.regions.append({"id":region.id,"grass":region.grass,"shrubs":region.shrubs})
 result.seed=config.seed;result.final_rng_state=str(local_rng.state)
 return result
func operation(name_:String,args:Dictionary)->Dictionary:
 var response:=await rpc("tools/call",{"name":name_,"arguments":args});var result:Dictionary=response.get("result",{});var payload:Dictionary={}
 for c in result.get("content",[]):
  if c.type=="text":payload=JSON.parse_string(c.text)
 report.operations.append({"tool":name_,"arguments":args,"result":payload});return payload
func place(label:String,p:Vector2,kind:String)->bool:
 var proof:=precheck(label,p,kind)
 if not proof.ok:reject(proof.reason);return false
 var entry:Dictionary=palette[label]
 var origin:Array=proof.origin.duplicate()
 # Raw asset API takes ground-Y; prefab API takes its native translated pivot.
 if not entry.prefab:origin[1]=proof.center[1]
 var placed:=await operation("place_asset",{"asset_id":entry.asset_id,"position":origin})
 if not placed.get("ok",false):
  var error:=str(placed.get("error","unknown"));reject("native_place: "+error)
  error_counts[error]=int(error_counts.get(error,0))+1
  persist()
  if error_counts[error]>=3:report.error="Repeated native rejection: "+error;persist();quit(1)
  return false
 while editor._gravity.falling:await process_frame
 var ids:Array=placed.get("ids",[])
 if ids.is_empty():reject("missing_native_ids");return false
 var support:Array=[]
 for id:String in ids:
  var record:Dictionary=editor._doc._find(id);var bounds:AABB=Foot.record_shape(record).bounds
  var center:=Vector2(bounds.get_center().x,bounds.get_center().z);var surface:=ground(center);var gap:=bounds.position.y-surface
  support.append({"id":id,"bbox_bottom_y":bounds.position.y,"ground_y":surface,"gap":gap})
  if not is_finite(gap) or absf(gap)>.002:
   editor._doc.undo();editor._commit_records(ids);reject("root_gap");report.operations.append({"support_rejected":support});return false
 for id:String in ids:
  var r:Dictionary=editor._doc._find(id);var b:AABB=Foot.record_shape(r).bounds
  obstacles.append({"id":id,"bounds":b,"house":false})
 report.placements.append({"kind":kind,"label":label,"ids":ids,"requested_center":proof.center,"basal_support":proof.root_support,"support":support,"actual_records":ids.map(func(id):return editor._doc._find(id).duplicate(true))})
 return true
func anchor_roots(placements:Array):
 for placement:Dictionary in placements:
  for id:String in placement.ids:
   var rec:Dictionary=editor._doc._find(id);var box:AABB=Foot.record_shape(rec).bounds
   var h:=ground(Vector2(box.get_center().x,box.get_center().z));var delta:=h-box.position.y
   var at:Array=rec.position.duplicate();at[1]+=delta
   var corrected:=await operation("set_object_transform",{"id":id,"position":at})
   check(corrected.get("ok",false),"native root anchor "+id)
   var final_box:AABB=Foot.record_shape(editor._doc._find(id)).bounds
   placement["root_anchor_correction"]={"id":id,"delta_y":delta,"ground_y":h,"final_gap":final_box.position.y-h}
   if absf(final_box.position.y-h)>.002:check(false,"root remains unsupported "+id)
  placement.actual_records=placement.ids.map(func(id):return editor._doc._find(id).duplicate(true))
func include_building_door_sweeps(doc)->bool:
 var placed:Array=doc.map_meta.get("town_reference",{}).get("functional_buildings",{}).get("placements",[])
 var included:Array=[]
 for placement:Dictionary in placed:
  var actual:Dictionary=doc._find(str(placement.uuid))
  if actual.is_empty() or not actual.has("model_building") or actual.position!=placement.position or actual.rotation!=placement.rotation or actual.size!=placement.scale or City.token(actual.model_building)!=placement.model_building_token:
   report.error="Functional building moved or changed after its native full door-sweep survey: "+str(placement.uuid);return false
  if not placement.has("hinge_sweep_envelopes"):
   report.error="Functional building lacks actual continuous door-sweep bounds: "+str(placement.uuid);return false
  for sweep:Dictionary in placement.hinge_sweep_envelopes:
   var lower:=v(sweep.world_min);var upper:=v(sweep.world_max)
   if not lower.is_finite() or not upper.is_finite() or upper.x<=lower.x or upper.y<=lower.y or upper.z<=lower.z:
    report.error="Invalid native building door-sweep bounds: "+str(sweep.id);return false
   obstacles.append({"id":str(placement.uuid)+":"+str(sweep.id),"bounds":AABB(lower,upper-lower),"house":true})
   included.append({"building":placement.uuid,"hinge":sweep.id,"world_min":sweep.world_min,"world_max":sweep.world_max})
 report.building_door_sweep_exclusions=included
 return true
func run():
 create_timer(2400).timeout.connect(func():report.error="timeout";persist();quit(2));rpc_timeout_ms=180000
 var map_path:="";var expected:="";var apply:=false
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--map="):map_path=arg.trim_prefix("--map=")
  elif arg.begins_with("--expected-sha="):expected=arg.trim_prefix("--expected-sha=")
  elif arg=="--apply":apply=true;apply_requested=true
  elif arg=="--probe-only":probe_only=true
 if map_path.is_empty() or expected.length()!=64 or FileAccess.get_sha256(map_path)!=expected:push_error("Exact --map and --expected-sha required");quit(1);return
 if apply and (map_path.replace("\\","/").to_lower()==Formal.to_lower() or not map_path.replace("\\","/").contains("/cache/world3d/")):push_error("Only root-owned cache candidate may be saved");quit(1);return
 plan=read(OUT+"/functional_vegetation_plan.json");rng.seed=20261016
 if FileAccess.file_exists(OUT+"/functional_building_sites.json"):
  future_sites=read(OUT+"/functional_building_sites.json").get("new_vegetation_exclusions",{})
  report.future_sites_sha256=FileAccess.get_sha256(OUT+"/functional_building_sites.json")

 for a:Dictionary in plan.assets:
  if FileAccess.get_sha256(a.asset_id)!=a.sha256:push_error("Asset changed "+a.label);quit(1);return
  var low:Array=[-a.bounds_size[0]/2,0,-a.bounds_size[2]/2]
  if a.kind=="prefab_path":
   var loaded=read(a.asset_id)
   if loaded.records.size()!=1:continue
   var rec:Dictionary=loaded.records[0]
   var box:AABB=Foot.record_shape(rec).bounds
   low=[box.position.x,box.position.y,box.position.z]
  else:low=a.entry.bounds_position
  palette[a.label]={"asset_id":a.asset_id,"low":low,"size":a.bounds_size,"prefab":a.kind=="prefab_path"}
 if not load_tree_support():report.error=tree_support_error;persist();quit(1);return
 var temporary:=OUT+"/vegetation_apply_fixture/map.gltf";DirAccess.make_dir_recursive_absolute(temporary.get_base_dir())
 var empty:=Doc.new();check(empty.save(temporary)==OK,"native empty vegetation fixture saved")
 var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=temporary;session.world3d_editor_doc=empty
 editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=OUT+"/vegetation_drafts";root.add_child(editor);await settle()
 while editor._load_job!=null and editor._load_job.active:await process_frame
 while editor._ground_batches.stats().get("pending_groups",0)>0:await process_frame
 var original=Doc.open_file(map_path)
 if original==null:report.error="Native candidate could not open";persist();quit(1);return
 var before:Dictionary=original.recovery_snapshot();var staged=Doc.new();staged.apply_recovery(before);editor._doc=staged;editor._city.refresh();editor._authoring.refresh()
 var wall_settings:Dictionary={}
 for region:Dictionary in City.resolve(staged.map_meta).get("fortifications",[]):
  if region.settings.get("id","")=="axel_city_fortification":wall_settings=region.settings.duplicate(true);break
 if wall_settings.is_empty():
  wall_settings=read(OUT+"/fortification_content_recipe.json").fortification_request
  report.wall_source={"path":OUT+"/fortification_content_recipe.json","sha256":FileAccess.get_sha256(OUT+"/fortification_content_recipe.json")}
 else:report.wall_source={"source":"candidate.editor_layout.fortifications","id":wall_settings.id,"input_sha256":expected}
 var resolved:=preload("res://scripts/world3d/fortification_spline.gd").resolve(wall_settings)
 if not resolved.ok:report.error=resolved.error;persist();quit(1);return
 wall=resolved.settings.points.duplicate(true);wall_half_depth=float(resolved.settings.thickness)*.5
 if resolved.settings.get("closed",false) and wall.front()!=wall.back():wall.append(wall.front().duplicate())
 report.wall_points=wall;report.wall_half_depth=wall_half_depth
 report.initialization="empty native viewport fixture; full candidate data attached without scene build"
 # Resolve the exact current library key (Windows separators are significant to HTTP).
 for field:Dictionary in plan.fields:
  if field.has("scatter"):
   for i in field.scatter.asset_ids.size():field.scatter.asset_ids[i]=str(field.scatter.asset_ids[i]).replace("\\","/")
 for label in palette:
  var found:=false
  for entry:Dictionary in editor.asset_items(""):
   var key:=str(entry.get("prefab_path",entry.get("asset_path","")))
   if key.replace("\\","/")==str(palette[label].asset_id).replace("\\","/"):
    palette[label].asset_id=key;found=true;break
  if not found:report.error="Missing current library entry: "+str(label);persist();quit(1);return
 report.merge({"map_path":map_path,"input_sha256":expected,"dry_run":not apply,"script_sha256":FileAccess.get_sha256("res://tools/apply_axel_functional_vegetation.gd"),"plan_sha256":FileAccess.get_sha256(OUT+"/functional_vegetation_plan.json")})
 for r:Dictionary in staged.records:
  if r.has("terrain_mesh"):terrain.append(r);continue
  if r.has("channel_mesh"):continue
  for shape:Dictionary in Foot.record_shapes(r):obstacles.append({"id":r.uuid,"bounds":shape.bounds,"house":r.has("building")})
 if not include_building_door_sweeps(staged):persist();quit(1);return
 for layer:Dictionary in staged.map_meta.terrain_rivers:rivers.append({"request":layer.request,"profile":Profile.prepare(layer.request)})
 var probe:=TCPServer.new();port=32240
 while probe.listen(port,"127.0.0.1")!=OK:port+=1
 probe.stop();check(editor.start_mcp(port).ok,"vegetation current3D HTTP starts")
 await operation("configure_transform",{"gravity_placement":false})
 for region:Dictionary in plan.tree_regions:
  var poly:=PackedVector2Array();var bounds:=Rect2(Vector2(region.polygon[0][0],region.polygon[0][1]),Vector2.ZERO)
  for q:Array in region.polygon:poly.append(Vector2(q[0],q[1]));bounds=bounds.expand(poly[-1])
  var count:=0
  for attempt in 350:
   if count>=int(region.trees):break
   var p:=bounds.position+Vector2(rng.randf(),rng.randf())*bounds.size
   if not Geometry2D.is_point_in_polygon(p,poly):continue
   var label:String=plan.tree_palette.orchard if region.id=="orchard" else plan.tree_palette.woodland
   if await place(label,p,"tree"):
    count+=1
    if probe_only:
     await operation("configure_transform",{"gravity_placement":false})
     await anchor_roots(report.placements)
     report.probe_passed=failed==0;report.input_unchanged=FileAccess.get_sha256(map_path)==expected;persist();editor._mcp.stop();quit(0 if failed==0 else 1);return
  report[region.id]={"count":count,"requested":region.trees};persist()
 var inland:=await place_inland_foliage()
 report.inland_foliage=inland;persist()
 rivers.reverse() # Prioritize the newly continuous S12 tributary, then main-river gaps.
 var grass:int=inland.grass;var shrub:int=inland.shrubs
 for river:Dictionary in rivers:
  var path:Array=river.profile.path
  for i in range(3,path.size()-3,3):
   if grass>=186 and shrub>=24:break
   var p:=Vector2(path[i][0],path[i][1]);var tangent:Vector2=(Vector2(path[i+1][0],path[i+1][1])-Vector2(path[i-1][0],path[i-1][1])).normalized();var normal:=Vector2(-tangent.y,tangent.x)
   for side in [-1,1]:
    var center:Vector2=p+normal*side*(float(river.request.width)*.5+2.2)
    for j in 5:
     var at:=center+tangent*rng.randf_range(-2.,2.)+normal*rng.randf_range(-.8,1.)
     if grass<186 and await place(["宽弧桥头草堆·A","宽弧桥头草堆·B","宽弧桥头草堆·C","写实矮草·A"][j%4],at,"grass"):grass+=1
    if shrub<24 and i%9==3 and await place("写实黄杨灌木",center+normal*side*2.,"shrub"):shrub+=1
  persist()
 await operation("configure_transform",{"gravity_placement":false})
 await anchor_roots(report.placements)
 persist()
 for field:Dictionary in plan.fields:
  if field.material_id!=null:
   var painted:=await operation("paint_terrain_region",{"id":field.id,"terrain_ids":field.terrain_ids,"polygon":field.polygon,"material_id":field.material_id,"feather":1.})
   if not painted.get("ok",false):check(false,"field material "+field.id);break
  if field.has("scatter"):
   var preview:=await operation("preview_vegetation_scatter",field.scatter)
   if not preview.get("ok",false):check(false,"crop preview "+field.id);break
   var grown:=await operation("generate_vegetation_scatter",field.scatter.merged({"plan_token":preview.plan_token}))
   report.crop_regions.append(grown);check(grown.get("ok",false),"crop native generation "+field.id)
 report.grass=grass;report.shrubs=shrub;report.failures=failed;report.input_unchanged=FileAccess.get_sha256(map_path)==expected
 check(City.token(before.map_meta.get("terrain_rivers",[]))==City.token(staged.map_meta.get("terrain_rivers",[])),"river layer ownership unchanged")
 check(City.token(City.resolve(before.map_meta).zones)==City.token(City.resolve(staged.map_meta).zones),"R1-R5 unchanged")
 for old:Dictionary in before.records:
  var now:Dictionary=staged._find(old.uuid)
  if old.has("terrain_mesh"):
   check(City.token(old.terrain_mesh)==City.token(now.get("terrain_mesh",{})),"terrain geometry unchanged "+str(old.uuid))
  elif City.token(old)!=City.token(now):check(false,"pre-existing content changed "+str(old.uuid))
 var valid:Error=staged.validate_save();report.native_save_validation=valid
 if valid!=OK:failed+=1
 if failed==0 and report.input_unchanged:
  var after:=staged.recovery_snapshot();original.apply_recovery(after);original.commit_recovery_change(before);editor._doc=original
  check(original.undo() and equivalent(original.recovery_snapshot().records,before.records) and equivalent(original.map_meta,before.map_meta),"vegetation one undo")
  check(original.redo() and equivalent(original.recovery_snapshot().records,after.records) and equivalent(original.map_meta,after.map_meta),"vegetation one redo")
  if apply and failed==0:
   check(original.save(map_path)==OK,"native atomic vegetation save");report.saved=failed==0;report.output_sha256=FileAccess.get_sha256(map_path)
   if report.saved:
    var reopened=Doc.open_file(map_path)
    report.native_reopen_passed=reopened!=null and reopened.validate_save()==OK and equivalent(reopened.records,original.records) and equivalent(reopened.map_meta,original.map_meta)
    check(report.native_reopen_passed,"Native saved vegetation candidate reopens identically")
 report.failures=failed;persist();editor._mcp.stop();quit(0 if failed==0 else 1)
