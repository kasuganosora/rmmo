extends "res://tools/probe_axel_vegetation_root_support.gd"
## Read-only final small-region proposals. Parent alone may edit the layout plan.
func conservative_small_regions(key:String,scan:Rect2,preferred:Vector2,limit:int)->Dictionary:
 var label:String=plan.tree_palette.woodland;var original_size:Array=palette[label].size.duplicate();var candidates:Array=[];var rejected:Dictionary={}
 # 1.10m inflated crown reserves the complete +/-0.5m placement square plus
 # rounding allowance. Exact current .4m spacing and all other filters remain.
 palette[label].size=[original_size[0]+1.10,original_size[1],original_size[2]+1.10]
 for x in range(int(scan.position.x),int(scan.end.x)+1,2):
  for z in range(int(scan.position.y),int(scan.end.y)+1,2):
   var at:=Vector2(x,z);obstacles=base_obstacles;var checked:=precheck(label,at,"tree")
   if not checked.ok:append_count(rejected,checked.reason);continue
   var max_delta:=0.;var span_min:=INF;var span_max:=-INF;var cy:=ground(at)
   for q:Array in basal_for(label).bands[4].hull_xz:
    var h:=ground(at+Vector2(q[0],q[1]));max_delta=maxf(max_delta,absf(h-cy));span_min=minf(span_min,h);span_max=maxf(span_max,h)
   # A siting preference, not an editor permission: prefer the shallower roots.
   if max_delta>.15:append_count(rejected,"proposal_prefers_root_delta_under_015");continue
   candidates.append({"p":at,"score":at.distance_to(preferred)+max_delta*100.,"delta":max_delta,"range":span_max-span_min})
 candidates.sort_custom(func(a,b):return a.score<b.score)
 var result:Array=[];var occupied:Array=[]
 for c:Dictionary in candidates:
  obstacles=base_obstacles.duplicate();obstacles.append_array(occupied)
  var checked:=precheck(label,c.p,"tree")
  if not checked.ok:continue
  palette[label].size=original_size
  var proofs:Array=[];var passed:=true
  for dx in [-.5,-.25,0.,.25,.5]:
   for dz in [-.5,-.25,0.,.25,.5]:
    var at:Vector2=c.p+Vector2(dx,dz);var point_check:=precheck(label,at,"tree")
    if not point_check.ok:passed=false
    proofs.append({"xz":[at.x,at.y],"ok":point_check.ok,"reason":point_check.get("reason","")})
  var terrain_detail:=terrain_comparison(label,c.p)
  palette[label].size=[original_size[0]+1.10,original_size[1],original_size[2]+1.10]
  if not passed:continue
  var id_:String=key+"_%02d"%[result.size()+1]
  result.append({"id":id_,"trees":1,"center_xz":[c.p.x,c.p.y],"polygon":[[c.p.x-.5,c.p.y-.5],[c.p.x+.5,c.p.y-.5],[c.p.x+.5,c.p.y+.5],[c.p.x-.5,c.p.y+.5]],"maximum_center_jitter_m":.5,"all_25_samples_passed":passed,"sample_checks":proofs,"inflated_crown_clear":true,"terrain":terrain_detail,"inflated_crown_bounds":{"min":[checked.bounds.position.x,checked.bounds.position.z],"max":[checked.bounds.end.x,checked.bounds.end.z]}})
  occupied.append({"id":id_,"bounds":checked.bounds,"house":false})
  if result.size()>=limit:break
 palette[label].size=original_size
 var pair_checks:Array=[]
 for i in result.size():
  for j in range(i+1,result.size()):
   var a:Dictionary=result[i].inflated_crown_bounds;var b:Dictionary=result[j].inflated_crown_bounds
   var dx:=maxf(a.min[0]-b.max[0],b.min[0]-a.max[0]);var dz:=maxf(a.min[1]-b.max[1],b.min[1]-a.max[1])
   pair_checks.append({"a":result[i].id,"b":result[j].id,"min_axis_gap_m":maxf(dx,dz),"passed":maxf(dx,dz)>.4})
 return {"id":key,"regions":result,"requested":limit,"provided":result.size(),"individual_safe_expanded_centers":candidates.size(),"pair_checks":pair_checks,"search_rejections":rejected}
func run():
 var snapshot_path:=OUT+"/market_candidate_records.json"
 var input_sha:=FileAccess.get_sha256(snapshot_path)
 var snap:Dictionary=read(snapshot_path)
 if snap.map_sha256!="c1ee7f095eac5bd937d92f7653697e961d942b674814e9e2cab66301b61e2f73":push_error("Unexpected market snapshot");quit(1);return
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
 probe_result={"mode":"read_only_small_region_proposal","map_sha256":snap.map_sha256,"snapshot_sha256":input_sha,"plan_sha256":FileAccess.get_sha256(OUT+"/functional_vegetation_plan.json"),"future_sites_sha256":FileAccess.get_sha256(OUT+"/functional_building_sites.json"),"basal_geometry_sha256":FileAccess.get_sha256(OUT+"/tree_basal_geometry_probe.json"),"script_sha256":FileAccess.get_sha256(get_script().resource_path),"native_placement_tested":false,"map_or_plan_changed":false,"groups":[]}
 probe_result.groups.append(conservative_small_regions("north_dry_bank",Rect2(212,46,76,64),Vector2(260,62),5))
 probe_result.groups.append(conservative_small_regions("east_road_grove",Rect2(334,180,42,52),Vector2(348,204),5))
 probe_result.limitations=["Small region guarantees concern current full-crown spatial prefilters, not native placement approval.","Root slope uses actual geometry basal hull with unchanged threshold; native root contact/anchoring still must be verified by owner.","The inflated canopy conservatively reserves +/-0.5m jitter, including pairwise spacing; 25 samples verify root terrain at each small region."]
 var f:=FileAccess.open(OUT+"/vegetation_small_region_proposal.json",FileAccess.WRITE);f.store_string(JSON.stringify(probe_result,"\t"));f.close()
 for group:Dictionary in probe_result.groups:print("FINAL PROPOSAL %s %d/%d"%[group.id,group.provided,group.requested])
 print("READONLY SMALL REGIONS COMPLETE");quit(0)
