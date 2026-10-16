extends "res://tools/probe_axel_vegetation_tree_capacity.gd"
## Read-only production grass/shrub candidate simulation after exact accepted 30 trees.
var foliage:Dictionary={"grass":0,"shrubs":0,"attempts":{"grass":0,"shrub":0},"rejections":{"grass":{},"shrub":{}},"accepted":[],"per_river":[]}
func simulate_foliage_place(label:String,p:Vector2,kind:String)->bool:
 foliage.attempts[kind]+=1
 var checked:=precheck(label,p,kind)
 if not checked.ok:append_count(foliage.rejections[kind],checked.reason);return false
 var id_:String="sim_%s_%d"%[kind,foliage.accepted.size()]
 obstacles.append({"id":id_,"bounds":checked.bounds,"house":false})
 foliage.accepted.append({"kind":kind,"label":label,"center":checked.center,"root_support":checked.root_support,"full_bounds":{"min":[checked.bounds.position.x,checked.bounds.position.y,checked.bounds.position.z],"max":[checked.bounds.end.x,checked.bounds.end.y,checked.bounds.end.z]}})
 return true
func run():
 var snapshot_path:=OUT+"/market_candidate_records.json"
 var input_sha:=FileAccess.get_sha256(snapshot_path)
 var snap:Dictionary=read(snapshot_path)
 if snap.map_sha256!="c1ee7f095eac5bd937d92f7653697e961d942b674814e9e2cab66301b61e2f73":push_error("Unexpected market snapshot");quit(1);return
 if FileAccess.get_sha256(OUT+"/functional_vegetation_plan.json")!="451a80f779197729bfe75f73966dc8f8499415d48f50eb624dd90597e1f3acdc" or FileAccess.get_sha256("res://tools/apply_axel_functional_vegetation.gd")!="8b39de7f865e5f9ec0720bfc9c706f694ae47ea6b60c5e1979dbffe19c9e7d75":push_error("Pinned plan or helper changed");quit(1);return
 plan=read(OUT+"/functional_vegetation_plan.json")
 future_sites=read(OUT+"/functional_building_sites.json").new_vegetation_exclusions
 var holder:=ProbeEditor.new();holder._doc=Doc.new();holder._doc.records=snap.records;holder._doc.map_meta=snap.map_meta;editor=holder;root.add_child(holder)
 for a:Dictionary in plan.assets:
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
 var tree_path:=OUT+"/vegetation_final_seed_precheck.json"
 if FileAccess.get_sha256(tree_path)!="45e5ee5250075692992ef3a526b04d6bdaf78031216e5b1530c64630b948fb47":push_error("Tree simulation receipt changed");quit(1);return
 var trees:Dictionary=read(tree_path);var attempts:=0
 obstacles=base_obstacles.duplicate()
 for row:Dictionary in trees.regions:attempts+=int(row.attempts)
 rng.seed=20261016
 # Each original tree attempt consumes exactly two randf() calls, even when
 # outside the region. No other random calls occur during tree precheck/place.
 for i in attempts*2:rng.randf()
 var tree_end_rng_state:=str(rng.state)
 for tree:Dictionary in trees.accepted:
  var b:Dictionary=tree.full_crown_bounds;var lower:=v(b.min);var upper:=v(b.max)
  obstacles.append({"id":"sim_tree_"+str(obstacles.size()),"bounds":AABB(lower,upper-lower),"house":false})
 var rng_before:=str(rng.state)
 var inland:=await place_inland_foliage(Callable(self,"simulate_foliage_place"))
 foliage.inland=inland;foliage.grass=inland.grass;foliage.shrubs=inland.shrubs
 foliage.inland_did_not_change_tree_river_rng=rng_before==str(rng.state)
 print("INLAND grass=%d shrubs=%d rng_unchanged=%s"%[inland.grass,inland.shrubs,foliage.inland_did_not_change_tree_river_rng])
 rivers.reverse()
 for river:Dictionary in rivers:
  var g_before:int=foliage.grass;var s_before:int=foliage.shrubs;var path:Array=river.profile.path
  for i in range(3,path.size()-3,3):
   if foliage.grass>=186 and foliage.shrubs>=24:break
   var p:=Vector2(path[i][0],path[i][1]);var tangent:Vector2=(Vector2(path[i+1][0],path[i+1][1])-Vector2(path[i-1][0],path[i-1][1])).normalized();var normal:=Vector2(-tangent.y,tangent.x)
   for side in [-1,1]:
    var center:Vector2=p+normal*side*(float(river.request.width)*.5+2.2)
    for j in 5:
     var at:=center+tangent*rng.randf_range(-2.,2.)+normal*rng.randf_range(-.8,1.)
     if foliage.grass<186 and simulate_foliage_place(["宽弧桥头草堆·A","宽弧桥头草堆·B","宽弧桥头草堆·C","写实矮草·A"][j%4],at,"grass"):foliage.grass+=1
    if foliage.shrubs<24 and i%9==3 and simulate_foliage_place("写实黄杨灌木",center+normal*side*2.,"shrub"):foliage.shrubs+=1
  foliage.per_river.append({"id":river.request.id,"grass":foliage.grass-g_before,"shrubs":foliage.shrubs-s_before});print("FOLIAGE %s grass=%d shrub=%d"%[river.request.id,foliage.grass-g_before,foliage.shrubs-s_before])
 foliage.merge({"mode":"read_only_exact_production_grass_shrub_precheck","tree_receipt_sha256":FileAccess.get_sha256(tree_path),"tree_count":trees.accepted.size(),"tree_attempts":attempts,"replayed_randf_draws":attempts*2,"tree_end_rng_state":tree_end_rng_state,"final_rng_state":str(rng.state),"native_placement_tested":false,"map_sha256":snap.map_sha256,"snapshot_sha256":input_sha,"plan_sha256":FileAccess.get_sha256(OUT+"/functional_vegetation_plan.json"),"helper_sha256":FileAccess.get_sha256("res://tools/apply_axel_functional_vegetation.gd"),"future_sites_sha256":FileAccess.get_sha256(OUT+"/functional_building_sites.json"),"script_sha256":FileAccess.get_sha256(get_script().resource_path),"map_or_plan_written":false,"crop_scatter_tested":false})
 foliage.inputs_stable=foliage.plan_sha256=="451a80f779197729bfe75f73966dc8f8499415d48f50eb624dd90597e1f3acdc" and foliage.helper_sha256=="8b39de7f865e5f9ec0720bfc9c706f694ae47ea6b60c5e1979dbffe19c9e7d75" and FileAccess.get_sha256(snapshot_path)==input_sha
 foliage.inland_all_full_bounds_inside_city=true
 for entry:Dictionary in inland.accepted:
  if not inland_full_bounds_inside_city(entry.label,Vector2(entry.center[0],entry.center[2])):foliage.inland_all_full_bounds_inside_city=false
 foliage.maximums_respected=inland.grass<=36 and inland.shrubs<=14 and foliage.grass<=186 and foliage.shrubs<=24
 for r:Dictionary in inland.regions:
  if r.grass>3 or r.shrubs>2:foliage.maximums_respected=false
 var f:=FileAccess.open(OUT+"/vegetation_inland_seed_precheck.json",FileAccess.WRITE);f.store_string(JSON.stringify(foliage,"\t"));f.close()
 print("FOLIAGE TOTAL grass=%d/186 shrubs=%d/24"%[foliage.grass,foliage.shrubs]);quit(0 if foliage.inputs_stable else 1)
