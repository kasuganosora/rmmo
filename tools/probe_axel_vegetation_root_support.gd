extends "res://tools/probe_axel_vegetation_tree_capacity.gd"
## Diagnostic only: identical filters, except slope samples actual root hull.
## This is NOT authoring approval or a change to editor collision checks.
var basal:Dictionary={}
func result_path()->String:return OUT+"/vegetation_root_support_probe.json"
func basal_for(label:String)->Dictionary:
 if basal.is_empty():basal=read(OUT+"/tree_basal_geometry_probe.json")
 for a:Dictionary in basal.assets:
  if a.label==label:return a
 return {}
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
 var support_points:Array=[]
 if kind=="tree":
  for q:Array in basal_for(label).bands[4].hull_xz:support_points.append(p+Vector2(q[0],q[1]))
 else:
  for q:Vector2 in poly:support_points.append(q)
 for q:Vector2 in support_points:
  var h:=ground(q)
  if not is_finite(h) or absf(h-y)>(.35 if kind=="tree" else .12):return {"ok":false,"reason":"root_slope"}
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
 return {"ok":true,"center":[p.x,y,p.y],"origin":[p.x-(low.x+size_.x/2),y-low.y,p.y-(low.z+size_.z/2)],"bounds":box}
func terrain_comparison(label:String,p:Vector2)->Dictionary:
 var a:=basal_for(label);var y:=ground(p);var size_:Vector3=v(palette[label].size)
 var full:=rect_poly([p.x-size_.x/2,p.y-size_.z/2,size_.x,size_.z]);var full_samples:Array=[];var full_max:=0.
 for q:Vector2 in full:
  var h:=ground(q);full_samples.append([q.x,h,q.y]);full_max=maxf(full_max,absf(h-y))
 var roots:Array=[];var root_max:=0.;var root_min_h:=INF;var root_max_h:=-INF
 for q:Array in a.bands[4].hull_xz:
  var xz:=p+Vector2(q[0],q[1]);var h:=ground(xz);roots.append([xz.x,h,xz.y]);root_max=maxf(root_max,absf(h-y));root_min_h=minf(root_min_h,h);root_max_h=maxf(root_max_h,h)
 var gaps:Array=[];var min_gap:=INF;var max_gap:=-INF
 for vertex:Array in a.actual_bottom_vertices_below_035:
  if float(vertex[1])>float(a.basal_min_y)+.05:continue
  var xz:=p+Vector2(vertex[0],vertex[2]);var h:=ground(xz);var gap:=y+float(vertex[1])-h
  gaps.append({"native_centered_vertex":vertex,"terrain_y":h,"gap_at_current_bbox_bottom_anchor":gap});min_gap=minf(min_gap,gap);max_gap=maxf(max_gap,gap)
 return {"center":[p.x,y,p.y],"full_crown_samples":full_samples,"crown_corner_max_delta_m":full_max,"actual_root_hull_samples":roots,"root_max_delta_from_anchor_m":root_max,"root_hull_terrain_range_m":root_max_h-root_min_h,"actual_bottom_005_vertices_gaps":gaps,"bottom_005_gap_min":min_gap,"bottom_005_gap_max":max_gap}
func append_additional_probe():
 probe_result.slope_measurement="DIAGNOSTIC only: actual indexed GLB basal 0.35m hull replaces full-crown slope sample; unchanged .35m threshold. Final native support/anchoring remains untested."
 probe_result.basal_geometry_sha256=FileAccess.get_sha256(OUT+"/tree_basal_geometry_probe.json")
 probe_result.comparisons=[]
 for p:Vector2 in [Vector2(240,77),Vector2(228,75),Vector2(254,78),Vector2(365,199),Vector2(355.5,205.5)]:
  var detail:=terrain_comparison(plan.tree_palette.woodland,p);obstacles=base_obstacles;var check_=precheck(plan.tree_palette.woodland,p,"tree");detail.all_rule_result={"ok":check_.ok,"reason":check_.get("reason","")};probe_result.comparisons.append(detail)
 # East-only alternative envelope. No accepted centers or existing inputs move.
 var candidate_points:Array=[];var reasons:Dictionary={}
 for ix in range(334,377,2):
  for iz in range(180,233,2):
   var p:=Vector2(ix,iz);obstacles=base_obstacles;var check_:=precheck(plan.tree_palette.woodland,p,"tree")
   if check_.ok:candidate_points.append({"p":p,"bounds":check_.bounds,"distance":p.distance_squared_to(Vector2(364,199)),"center":check_.center})
   else:append_count(reasons,check_.reason)
 candidate_points.sort_custom(func(a,b):return a.distance<b.distance)
 var selected:Array=[];var new_obstacles:Array=[]
 for c:Dictionary in candidate_points:
  obstacles=base_obstacles.duplicate();obstacles.append_array(new_obstacles)
  var check_:=precheck(plan.tree_palette.woodland,c.p,"tree")
  if not check_.ok:continue
  selected.append(terrain_comparison(plan.tree_palette.woodland,c.p));new_obstacles.append({"id":"proposed_east_tree_%d"%selected.size(),"bounds":check_.bounds,"house":false})
  if selected.size()>=5:break
 probe_result.east_alternative={"search_rect_xz":[334,180,42,52],"spacing_m":2,"individually_clear_candidates":candidate_points.size(),"rejections":reasons,"nearest_separated_five_or_fewer":selected,"no_source_edit":true}
