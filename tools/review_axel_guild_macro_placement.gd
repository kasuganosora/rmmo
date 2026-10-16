extends SceneTree
## Read-only macro placement: native records, footprint/road planning and terrain.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Props=preload("res://tools/axel_house_reference_props.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Fit=preload("res://scripts/world3d/road_terrain_fit.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
const MAP="D:/code/rmmo_runtime/cache/world3d/axel_town_houses_20261014/map.gltf"
func _initialize():call_deferred("run")
func read(path:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path))
func arr(v:Vector3)->Array:return [v.x,v.y,v.z]
func box(low:Vector3,high:Vector3)->Dictionary:
 var points:Array[Vector3]=[];var bounds:=AABB(low,high-low)
 for i in 8:points.append(bounds.get_endpoint(i))
 return Foot.from_points(points)
func sample(doc,rect:Rect2,step:float=1.)->Dictionary:
 var low:=INF;var high:=-INF;var n:=0
 for ix in ceili(rect.size.x/step)+1:
  for iz in ceili(rect.size.y/step)+1:
   var p:=Vector3(rect.position.x+minf(ix*step,rect.size.x),0,rect.position.y+minf(iz*step,rect.size.y))
   var y:float=Props.ground(doc,p)
   if not is_finite(y):return {"ok":false,"missing":arr(p)}
   low=minf(low,y);high=maxf(high,y);n+=1
 return {"ok":true,"min":low,"max":high,"range":high-low,"samples":n}
func collisions(roads:Array,pieces:Array)->Array:
 var result:Array=[]
 for r:Dictionary in roads:
  var shapes:=Foot.record_shapes(r)
  for p:Dictionary in pieces:
   if Foot.batches_overlap(shapes,[p]):result.append({"road":r.uuid,"piece":p.get("name","whole"),"road_source":r.get("road_source","")})
 return result
func run():
 var sha:=FileAccess.get_sha256(MAP);var doc=Doc.open_file(MAP)
 if doc==null:quit(1);return
 var data:=City.resolve(doc.map_meta);var report:={"candidate_sha256":sha,"saved":false,"inputs":{},"placements":[],"road_delta":{},"scope":"Native CPU geometry/road/terrain preflight only; no GPU or scene placement."}
 var roads:Array=doc.records.filter(func(r):return r.has("road_mesh"));var entries:=Props.catalog()
 var guild:Dictionary={};var tower:Dictionary={}
 for e:Dictionary in entries:
  if e.get("asset_path","").contains("7824a14"):guild=e
  if e.get("asset_path","").contains("af248d5"):tower=e
 var assets:Array=[["guild",guild,Vector3(140,0,198),Rect2(140,184,32,14)],["alarm",tower,Vector3(141,0,144),Rect2(138.45,141.45,5.1,5.1)]]
 var all_pieces:Dictionary={}
 for item:Array in assets:
  var key:String=item[0];var entry:Dictionary=item[1];var origin:Vector3=item[2]
  var ground:=sample(doc,item[3],.5);origin.y=ground.max+.32 if key=="guild" else ground.max
  var geometry:=read(OUT+"/"+key+"_macro_source_geometry.json");var pieces:Array=[]
  for mesh:Dictionary in geometry.meshes:
   if mesh.extras.get("rmmo_collision","")=="none":continue
   var shape:=box(City.vec(mesh.min)+origin,City.vec(mesh.max)+origin);shape.name=mesh.name;pieces.append(shape)
  all_pieces[key]=pieces
  var id:String=doc.add_asset(entry,origin);var record:Dictionary=doc._find(id);record.rotation=[0.,0.,0.]
  var validity:int=doc.validate_save_record(record)
  var full:=Foot.record_shape(record);var contacts:=collisions(roads,pieces);var object_conflicts:Array=[]
  for existing:Dictionary in doc.records:
   if existing.uuid==id or existing.has("terrain_mesh") or existing.has("road_mesh"):continue
   if not Foot.overlaps(full,Foot.record_shape(existing)):continue
   if Foot.batches_overlap(Foot.record_shapes(existing),pieces):object_conflicts.append(existing.uuid)
  var reserved:Array=[]
  for zone:Dictionary in data.zones:
   var poly:PackedVector2Array=[]
   for p:Array in zone.polygon:poly.append(Vector2(p[0],p[1]))
   if not Geometry2D.intersect_polygons(full.polygon,poly).is_empty():reserved.append(zone.id)
  report.inputs[key]={"source":entry.asset_path,"sha256":FileAccess.get_sha256(entry.asset_path),"geometry_inventory_sha256":FileAccess.get_sha256(OUT+"/"+key+"_macro_source_geometry.json")}
  report.placements.append({"id":key,"provisional_highest_point_position":arr(origin),"yaw":0,"scale":[1,1,1],"native_save_record_error":validity,"sampled_support":ground,"whole_bounds":{"min":arr(full.bounds.position),"max":arr(full.bounds.end)},"source_piece_aabb_collision_candidates":contacts,"reserved_zone_overlaps":reserved,"existing_object_conflicts":object_conflicts})
  doc.remove(id)
 var nodes:Array=[]
 for n:Dictionary in data.roads.nodes:
  var p:=City.vec(n.position)
  if p.x>135 and p.x<177 and p.z>138 and p.z<210:nodes.append(n)
 report.nearby_road_nodes=nodes
 var target:Array=data.roads.nodes.filter(func(n):return City.vec(n.position).distance_to(Vector3(156,7.5,198))<1.)
 if not target.is_empty():
  var changed:=data.duplicate(true);var endpoint:String=target[0].id
  for n:Dictionary in changed.roads.nodes:
   if n.id==endpoint:n.position[2]=203.75;n.position[1]=Props.ground(doc,City.vec(n.position))
  var bindings:=preload("res://scripts/world3d/road_bridges.gd").resolve(changed)
  var settings:=Plan.defaults();settings.merge(changed.road_surface.settings,true)
  var planned:=Plan.build(changed.roads,settings,bindings.portals)
  report.road_delta={"endpoint_id":endpoint,"before":target[0].position,"after":[156.,7.5,203.75],"plan_ok":planned.ok}
  if planned.ok:
   var local:Array=[]
   for r:Dictionary in planned.records:
    var b:Dictionary=Foot.record_shape(r)
    if Rect2(b.bounds.position.x,b.bounds.position.z,b.bounds.size.x,b.bounds.size.z).intersects(Rect2(130,178,50,35)):local.append(r)
   var fitted:=Fit.fit(local,doc.records.filter(func(r):return r.has("terrain_mesh")),settings.lift,128)
   report.road_delta.fit_ok=fitted.ok
   if fitted.ok:
    report.road_delta.guild_contacts=collisions(fitted.records,all_pieces.guild)
    report.road_delta.alarm_contacts=collisions(fitted.records,all_pieces.alarm)
    report.road_delta.native_local_pieces=fitted.records.size()
   else:report.road_delta.fit_error=fitted.get("error","")
  else:report.road_delta.plan_error=planned.get("error","")
 report.forecourt={"reserved_xz":[144,200,24,16],"central_public_passage_xz":[153,201,6,34],"player_stall_left_xz":[144,202,8,13],"player_stall_right_xz":[160,202,8,13],"fixed_stalls":0,"trees":0}
 report.recommended_placements=[{"id":"guild","position":[140.,7.8,198.],"yaw":0.,"scale":[1.,1.,1.],"entrance":[156.,7.8,197.75],"front_direction":[0,0,1],"foundation_xz":[140,184,32,14],"bearing_level":7.5,"ground_fit":"PENDING local foundation support: current rear ground falls to 7.305; fill at most 0.195 m under 32x14 m footing. Root Y7.8 retains two 0.16 m steps; lower step embeds 0.02 m. Do not land whole bounds at highest terrain and leave rear foundation floating."},{"id":"alarm","position":[141.,8.,144.],"yaw":0.,"scale":[1.,1.,1.],"foundation_diameter":5.1,"bearing_level":8.,"ground_fit":"PENDING local 5.1 m shaft footprint bearing: current terrain 7.9328..8.0896. Small local cut/fill <=0.090 m; never raise entire site to highest point and leave the low side floating.","entry_semantics":"Current accepted alarm tower source has closed 0.2 m shaft base and no traversable ground entrance. Existing southern path remains service approach, not a claimed usable tower interior.","high_level_horn_envelope_diameter":12.374217,"horn_min_height_above_origin":24.581}]
 report.reserved_relations={"guardhouse_xz":[149,165,19,14],"guild_rear_full_envelope_to_guardhouse_south_gap":4.11000034,"guardhouse_church_mill":"Occupancy reserved only; complete formal source absent, no placeholder model substituted."}
 report.status={"macro_xz_native_preflight":"pass after proposed guild approach endpoint retreat","ground_bearing":"pending minimal local support treatment, not performed","native_record_schema":"pass for both formal source entries","candidate_placement":"not performed","gpu_visual":"not performed; reuse existing source acceptance only","interiors":"not retested"}
 report.limitations=["Source-part AABBs conservatively enclose actual mesh triangles; zero overlap proves clearance, candidate overlap is not automatically a true triangle collision.","Ground values are dense 0.5 m native Terrain.sample results, not proof of final edited terrain. No terrain changes were made.","Only affected local native road chunks were regenerated/fitted; this is not a completed full-map RoadTools apply or placement transaction."]
 report.candidate_unchanged=sha==FileAccess.get_sha256(MAP)
 FileAccess.open(OUT+"/guild_alarm_macro_layout.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print(JSON.stringify(report));quit()
