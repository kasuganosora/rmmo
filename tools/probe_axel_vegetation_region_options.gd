extends "res://tools/probe_axel_vegetation_root_support.gd"
## Read-only candidate regions with all existing full-crown exclusions retained.
func result_path()->String:return OUT+"/vegetation_region_options_probe.json"
func scan_options(key:String,box:Rect2,aim:Vector2,maximum:int)->Dictionary:
 var possibilities:Array=[];var reasons:Dictionary={}
 for ix in range(int(box.position.x),int(box.end.x)+1,2):
  for iz in range(int(box.position.y),int(box.end.y)+1,2):
   var p:=Vector2(ix,iz);obstacles=base_obstacles;var checked:=precheck(plan.tree_palette.woodland,p,"tree")
   if checked.ok:possibilities.append({"p":p,"distance":p.distance_squared_to(aim)})
   else:append_count(reasons,checked.reason)
 possibilities.sort_custom(func(a,b):return a.distance<b.distance)
 var chosen:Array=[];var proposed_obstacles:Array=[]
 for option:Dictionary in possibilities:
  obstacles=base_obstacles.duplicate();obstacles.append_array(proposed_obstacles)
  var checked:=precheck(plan.tree_palette.woodland,option.p,"tree")
  if not checked.ok:continue
  var detail:=terrain_comparison(plan.tree_palette.woodland,option.p)
  var size_:Vector3=v(palette[plan.tree_palette.woodland].size);var radius:=Vector2(size_.x,size_.z).length()*.5;var distance:=INF
  for i in wall.size()-1:distance=minf(distance,option.p.distance_to(Geometry2D.get_closest_point_to_segment(option.p,Vector2(wall[i][0],wall[i][1]),Vector2(wall[i+1][0],wall[i+1][1]))))
  detail.full_crown_to_wall_clearance_m=distance-radius-wall_half_depth;detail.rivers=[]
  for river:Dictionary in rivers:
   var sample:=Profile.sample(option.p,river.profile.path,river.profile.levels)
   detail.rivers.append({"id":river.request.id,"distance_to_centerline":sample.distance,"full_crown_to_wet_width_m":sample.distance-float(river.request.width)*.5-radius,"water_level":sample.level})
  detail.all_other_protections_preserved=true;chosen.append(detail)
  proposed_obstacles.append({"id":"proposal_%s_%d"%[key,chosen.size()],"bounds":checked.bounds,"house":false})
  if chosen.size()>=maximum:break
 return {"id":key,"search_rect_xz":[box.position.x,box.position.y,box.size.x,box.size.y],"preferred_center":[aim.x,aim.y],"spacing_m":2,"individually_clear_candidates":possibilities.size(),"rejections":reasons,"selected_separated_centers":chosen,"requested":maximum,"no_map_or_plan_edit":true}
func append_additional_probe():
 probe_result.slope_measurement="Read-only alternative region assessment using actual basal 0.35m hull; no shared helper/model/map change. Native support acceptance pending."
 probe_result.basal_geometry_sha256=FileAccess.get_sha256(OUT+"/tree_basal_geometry_probe.json")
 probe_result.region_options=[scan_options("north_dry_bank",Rect2(212,46,76,64),Vector2(258,58),5),scan_options("east_west_shift",Rect2(334,180,42,52),Vector2(345,204),5)]
