extends "res://tools/probe_axel_vegetation_tree_capacity.gd"
## Exact current production precheck, RNG and whole-crown mutual exclusion only.
## No native mutation, map loading, save, model rendering, or one-metre grid scan.
func final_seed_simulation()->Dictionary:
 rng.seed=20261016
 var result:Dictionary={"seed":20261016,"attempt_limit_per_region":350,"regions":[],"total_requested":0,"total_precheck_accepted":0,"root_max_delta_m":0.,"root_max_range_m":0.,"all_new_north_east_accepted":true,"accepted":[]}
 obstacles=base_obstacles.duplicate()
 for region:Dictionary in plan.tree_regions:
  var poly:=PackedVector2Array();var bounds:=Rect2(Vector2(region.polygon[0][0],region.polygon[0][1]),Vector2.ZERO)
  for q:Array in region.polygon:poly.append(Vector2(q[0],q[1]));bounds=bounds.expand(poly[-1])
  var label:String=plan.tree_palette.orchard if region.id=="orchard" else plan.tree_palette.woodland
  var row:Dictionary={"id":region.id,"requested":region.trees,"count":0,"attempts":0,"rejections":{},"accepted":[]}
  result.total_requested+=int(region.trees)
  for attempt in 350:
   if row.count>=int(region.trees):break
   row.attempts+=1
   var p:=bounds.position+Vector2(rng.randf(),rng.randf())*bounds.size
   if not Geometry2D.is_point_in_polygon(p,poly):continue
   var proof:=precheck(label,p,"tree")
   if not proof.ok:append_count(row.rejections,proof.reason);continue
   row.count+=1
   var support:Dictionary=proof.root_support
   var delta:=maxf(absf(support.ground_min-support.center_y),absf(support.ground_max-support.center_y));var span:float=support.ground_max-support.ground_min
   var entry:Dictionary={"region":region.id,"label":label,"center":proof.center,"root_support":support,"max_root_height_delta":delta,"root_height_range":span,"full_crown_bounds":{"min":[proof.bounds.position.x,proof.bounds.position.y,proof.bounds.position.z],"max":[proof.bounds.end.x,proof.bounds.end.y,proof.bounds.end.z]}}
   row.accepted.append(entry);result.accepted.append(entry);result.root_max_delta_m=maxf(result.root_max_delta_m,delta);result.root_max_range_m=maxf(result.root_max_range_m,span)
   obstacles.append({"id":"seed_tree_%s_%d"%[region.id,row.count],"bounds":proof.bounds,"house":false})
  result.total_precheck_accepted+=row.count
  if str(region.id).begins_with("north_dry_bank_") or str(region.id).begins_with("east_road_grove_"):
   if row.count!=int(region.trees):result.all_new_north_east_accepted=false
  result.regions.append(row);print("FINAL SEED %s %d/%d"%[row.id,row.count,row.requested])
 result.pair_checks=[];result.all_full_crowns_separated=true
 for i in result.accepted.size():
  for j in range(i+1,result.accepted.size()):
   var a:Dictionary=result.accepted[i];var b:Dictionary=result.accepted[j];var aa:Dictionary=a.full_crown_bounds;var bb:Dictionary=b.full_crown_bounds
   var dx:=maxf(aa.min[0]-bb.max[0],bb.min[0]-aa.max[0]);var dz:=maxf(aa.min[2]-bb.max[2],bb.min[2]-aa.max[2]);var gap:=maxf(dx,dz);var okay:=gap>.39999
   result.pair_checks.append({"a":i,"b":j,"region_a":a.region,"region_b":b.region,"axis_gap_m":gap,"passed":okay})
   if not okay:result.all_full_crowns_separated=false
 return result
func run():
 var snapshot_path:=OUT+"/market_candidate_records.json"
 var input_sha:=FileAccess.get_sha256(snapshot_path)
 var snap:Dictionary=read(snapshot_path)
 if snap.map_sha256!="c1ee7f095eac5bd937d92f7653697e961d942b674814e9e2cab66301b61e2f73":push_error("Unexpected market snapshot");quit(1);return
 if FileAccess.get_sha256(OUT+"/functional_vegetation_plan.json")!="401d9ee345ad948089be664d137293a2b9be744307dfa3388df331271afe499c" or FileAccess.get_sha256("res://tools/apply_axel_functional_vegetation.gd")!="89cd8b5518473fc23c6cd5ae28ced91cd6412bcbb8d705c9bd43d5645d9c71c1":push_error("Pinned plan or helper changed");quit(1);return
 plan=read(OUT+"/functional_vegetation_plan.json")
 future_sites=read(OUT+"/functional_building_sites.json").new_vegetation_exclusions
 var holder:=ProbeEditor.new();holder._doc=Doc.new();holder._doc.records=snap.records;holder._doc.map_meta=snap.map_meta;editor=holder;root.add_child(holder)
 for a:Dictionary in plan.assets:
  if a.label not in [plan.tree_palette.woodland,plan.tree_palette.orchard]:continue
  if FileAccess.get_sha256(a.asset_id)!=a.sha256:push_error("Asset changed");quit(1);return
  var low:Array=[-a.bounds_size[0]/2,0,-a.bounds_size[2]/2]
  if a.kind=="prefab_path":
   var asset:Dictionary=read(a.asset_id);var box:AABB=Foot.record_shape(asset.records[0]).bounds;low=[box.position.x,box.position.y,box.position.z]
  else:low=a.entry.bounds_position
  palette[a.label]={"asset_id":a.asset_id,"low":low,"size":a.bounds_size,"prefab":a.kind=="prefab_path"}
 var settings:Dictionary={}
 for f:Dictionary in City.resolve(snap.map_meta).fortifications:
  if f.settings.id=="axel_city_fortification":settings=f.settings
 var resolved:=preload("res://scripts/world3d/fortification_spline.gd").resolve(settings)
 if not resolved.ok:push_error(resolved.error);quit(1);return
 wall=resolved.settings.points.duplicate(true);wall_half_depth=float(resolved.settings.thickness)*.5
 if resolved.settings.get("closed",false) and wall.front()!=wall.back():wall.append(wall.front().duplicate())
 for r:Dictionary in snap.records:
  records_by_id[r.uuid]=r
  if r.has("terrain_mesh"):terrain.append(r);continue
  if r.has("channel_mesh"):continue
  for s:Dictionary in Foot.record_shapes(r):
   var item:Dictionary={"id":r.uuid,"bounds":s.bounds,"house":r.has("building")};base_obstacles.append(item)
   if r.has("fortification") and r.has("house_prefab") and not r.has("fixture"):frozen_obstacles.append(item)
   else:ordinary_obstacles.append(item)
 for layer:Dictionary in snap.map_meta.terrain_rivers:rivers.append({"request":layer.request,"profile":Profile.prepare(layer.request)})
 var answer:=final_seed_simulation()
 answer.merge({"mode":"read_only_exact_production_seed_precheck","native_placement_tested":false,"snapshot_path":snapshot_path,"map_sha256":snap.map_sha256,"snapshot_sha256":input_sha,"plan_sha256":FileAccess.get_sha256(OUT+"/functional_vegetation_plan.json"),"helper_sha256":FileAccess.get_sha256("res://tools/apply_axel_functional_vegetation.gd"),"future_sites_sha256":FileAccess.get_sha256(OUT+"/functional_building_sites.json"),"basal_geometry_sha256":FileAccess.get_sha256(OUT+"/tree_basal_geometry_probe.json"),"script_sha256":FileAccess.get_sha256(get_script().resource_path),"model_inputs_verified":tree_support_error.is_empty() and tree_support_loaded,"basal_source":report.get("basal_support_evidence",{}),"map_or_plan_written":false})
 answer.inputs_stable=answer.plan_sha256=="401d9ee345ad948089be664d137293a2b9be744307dfa3388df331271afe499c" and answer.helper_sha256=="89cd8b5518473fc23c6cd5ae28ced91cd6412bcbb8d705c9bd43d5645d9c71c1" and FileAccess.get_sha256(snapshot_path)==input_sha
 var f:=FileAccess.open(OUT+"/vegetation_final_seed_precheck.json",FileAccess.WRITE);f.store_string(JSON.stringify(answer,"\t"));f.close()
 print("FINAL SEED TOTAL %d/%d; new10=%s; mutual=%s; rootmax=%s"%[answer.total_precheck_accepted,answer.total_requested,answer.all_new_north_east_accepted,answer.all_full_crowns_separated,answer.root_max_delta_m]);quit(0 if answer.inputs_stable and answer.model_inputs_verified and answer.all_full_crowns_separated else 1)
