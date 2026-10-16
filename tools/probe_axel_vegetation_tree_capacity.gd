extends "res://tools/apply_axel_functional_vegetation.gd"
## Read-only CPU probe. Never invokes authoring, HTTP, map save, or GPU setup.
const FrozenContact=preload("res://scripts/world3d/frozen_road_contact.gd")
class ProbeEditor extends Node3D:
 var _doc
var probe_result:Dictionary={"mode":"read_only_cpu_precheck","native_placement_tested":false,"regions":[],"frozen_geometry":[]}
var base_obstacles:Array=[]
var ordinary_obstacles:Array=[]
var frozen_obstacles:Array=[]
var geometry_rects:Dictionary={}
var records_by_id:Dictionary={}
func rect_of(b:AABB)->Rect2:return Rect2(Vector2(b.position.x,b.position.z),Vector2(b.size.x,b.size.z))
func frozen_ids_for(box:AABB)->Array:
 var ids:Array=[];var r:=rect_of(box)
 for item:Dictionary in frozen_obstacles:
  if rect_of(item.bounds).grow(.4).intersects(r,true) and not ids.has(item.id):ids.append(item.id)
 return ids
func narrow_clear(box:AABB)->Dictionary:
 var r:=rect_of(box).grow(.4);var broad:=frozen_ids_for(box);var exact_blockers:Array=[]
 for id:String in broad:
  if not geometry_rects.has(id):exact_blockers.append(id+":unknown");continue
  for face:Rect2 in geometry_rects[id]:
   # A triangle's projected AABB is conservative. A clear result proves every
   # real triangle clear; a hit may still be a false positive, never an exemption.
   if face.intersects(r,true):exact_blockers.append(id);break
 return {"clear":exact_blockers.is_empty(),"broad_ids":broad,"conservative_triangle_blockers":exact_blockers}
func append_count(dict:Dictionary,key:String):dict[key]=int(dict.get(key,0))+1
func sample_grid(region:Dictionary)->Dictionary:
 var poly:=PackedVector2Array();var b:=Rect2(Vector2(region.polygon[0][0],region.polygon[0][1]),Vector2.ZERO)
 for q:Array in region.polygon:poly.append(Vector2(q[0],q[1]));b=b.expand(poly[-1])
 var result:Dictionary={"id":region.id,"requested":region.trees,"grid_spacing_m":1.,"samples_inside":0,"current_clear":0,"all_non_frozen_rules_clear":0,"geometry_refined_clear":0,"current_rejections":{},"without_frozen_rejections":{},"false_frozen_examples":[],"grid_candidates":[]}
 var label:String=plan.tree_palette.orchard if region.id=="orchard" else plan.tree_palette.woodland
 for ix in range(int(floor(b.position.x)),int(ceil(b.end.x))+1):
  for iz in range(int(floor(b.position.y)),int(ceil(b.end.y))+1):
   var p:=Vector2(ix+.5,iz+.5)
   if not Geometry2D.is_point_in_polygon(p,poly):continue
   result.samples_inside+=1
   obstacles=base_obstacles
   var current:=precheck(label,p,"tree")
   if current.ok:result.current_clear+=1
   else:append_count(result.current_rejections,current.reason)
   obstacles=ordinary_obstacles
   var otherwise:=precheck(label,p,"tree")
   if not otherwise.ok:append_count(result.without_frozen_rejections,otherwise.reason);continue
   result.all_non_frozen_rules_clear+=1
   var actual:=narrow_clear(otherwise.bounds)
   if not actual.clear:continue
   result.geometry_refined_clear+=1
   result.grid_candidates.append([p.x,p.y])
   if not current.ok and result.false_frozen_examples.size()<6:
    result.false_frozen_examples.append({"center":otherwise.center,"current_reason":current.reason,"broad_frozen_ids":actual.broad_ids,"every_projected_triangle_aabb_clear":true,"crown_world_min":[otherwise.bounds.position.x,otherwise.bounds.position.y,otherwise.bounds.position.z],"crown_world_max":[otherwise.bounds.end.x,otherwise.bounds.end.y,otherwise.bounds.end.z]})
 return result
func simulate(refined:bool)->Array:
 rng.seed=20261016
 var answer:Array=[];var placed_obstacles:Array=[]
 for region:Dictionary in plan.tree_regions:
  var poly:=PackedVector2Array();var b:=Rect2(Vector2(region.polygon[0][0],region.polygon[0][1]),Vector2.ZERO)
  for q:Array in region.polygon:poly.append(Vector2(q[0],q[1]));b=b.expand(poly[-1])
  var row:Dictionary={"id":region.id,"requested":region.trees,"count":0,"centers":[],"rejections":{},"attempts":0}
  var label:String=plan.tree_palette.orchard if region.id=="orchard" else plan.tree_palette.woodland
  for attempt in 350:
   if row.count>=int(region.trees):break
   row.attempts+=1
   var p:=b.position+Vector2(rng.randf(),rng.randf())*b.size
   if not Geometry2D.is_point_in_polygon(p,poly):continue
   obstacles=(ordinary_obstacles if refined else base_obstacles).duplicate()
   obstacles.append_array(placed_obstacles)
   var checked:=precheck(label,p,"tree")
   if not checked.ok:append_count(row.rejections,checked.reason);continue
   if refined:
    var actual:=narrow_clear(checked.bounds)
    if not actual.clear:append_count(row.rejections,"actual_frozen_or_unknown");continue
   row.count+=1;row.centers.append(checked.center)
   placed_obstacles.append({"id":"probe_tree_%s_%d"%[region.id,row.count],"house":false,"bounds":checked.bounds})
  answer.append(row)
 return answer
func result_path()->String:return OUT+"/vegetation_tree_capacity_probe.json"
func append_additional_probe():pass
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
 # Decode only frozen batches that can reach a proposed tree region's crown.
 var wanted:Dictionary={}
 for region:Dictionary in plan.tree_regions:
  var size_:Array=palette[plan.tree_palette.orchard if region.id=="orchard" else plan.tree_palette.woodland].size
  var b:=Rect2(Vector2(region.polygon[0][0],region.polygon[0][1]),Vector2.ZERO)
  for q:Array in region.polygon:b=b.expand(Vector2(q[0],q[1]))
  b=b.grow(maxf(size_[0],size_[2])*.5+.4)
  for item:Dictionary in frozen_obstacles:
   if b.intersects(rect_of(item.bounds),true):wanted[item.id]=item
 print("AUDIT CPU input records=%d, frozen batches=%d, relevant=%d"%[snap.records.size(),frozen_obstacles.size(),wanted.size()])
 for id:String in wanted:
  var cache:Dictionary={};var geo:=FrozenContact.geometry(records_by_id[id],cache)
  var row:Dictionary={"id":id,"known":geo.known,"bbox_min":[wanted[id].bounds.position.x,wanted[id].bounds.position.y,wanted[id].bounds.position.z],"bbox_max":[wanted[id].bounds.end.x,wanted[id].bounds.end.y,wanted[id].bounds.end.z]}
  if geo.known:
   var rs:Array=[]
   for face:Dictionary in geo.faces:rs.append(rect_of(face.bounds))
   geometry_rects[id]=rs;row.triangles=rs.size()
  probe_result.frozen_geometry.append(row)
  print("Decoded %s: %s"%[id,row.get("triangles","unknown")])
 for region:Dictionary in plan.tree_regions:
  var row:=sample_grid(region);probe_result.regions.append(row)
  print("REGION %s: current=%d non_frozen=%d refined=%d inside=%d"%[row.id,row.current_clear,row.all_non_frozen_rules_clear,row.geometry_refined_clear,row.samples_inside])
 probe_result.current_seed_20261016=simulate(false)
 probe_result.refined_seed_20261016=simulate(true)
 probe_result.merge({"map_sha256":snap.map_sha256,"snapshot_path":snapshot_path,"snapshot_sha256":input_sha,"plan_sha256":FileAccess.get_sha256(OUT+"/functional_vegetation_plan.json"),"future_sites_sha256":FileAccess.get_sha256(OUT+"/functional_building_sites.json"),"authoring_helper_sha256":FileAccess.get_sha256("res://tools/apply_axel_functional_vegetation.gd"),"probe_sha256":FileAccess.get_sha256(get_script().resource_path),"wall_half_depth":wall_half_depth,"future_sites":future_sites,"palette":palette,"limitations":["1m sample grid estimates center-placement area, not a certified packing maximum.","Refined projection is triangle AABB conservative and never removes building/road/fixture/reservation/slope rules.","Greedy seed simulation assumes precheck-success native placement; no native placement or save is performed."],"input_unchanged":FileAccess.get_sha256(snapshot_path)==input_sha})
 append_additional_probe()
 var f:=FileAccess.open(result_path(),FileAccess.WRITE);f.store_string(JSON.stringify(probe_result,"\t"));f.close()
 print("READONLY TREE CAPACITY COMPLETE");quit(0)
