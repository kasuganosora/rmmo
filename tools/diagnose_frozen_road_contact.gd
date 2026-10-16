extends SceneTree
const Contact=preload("res://scripts/world3d/asset_road_contact.gd")
const Frozen=preload("res://scripts/world3d/frozen_road_contact.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Clip=preload("res://scripts/world3d/road_bridge_approach.gd")
const EPS=.005
func _initialize()->void:call_deferred("run")
func run()->void:
 var d=Doc.open_file("D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf")
 var wall=d._find("fort_82e4c659dc0331e8_baked_29")
 var geometry=Frozen.geometry(wall,{})
 print("GEOMETRY ",geometry.get("known")," faces ",geometry.get("faces",[]).size())
 for solid in geometry.solids:print("POINT_INSIDE ",geometry.solids.find(solid)," ",Contact.inside(Vector3(328.2339,10.14069,50.46783),solid))
 for r in d.records:
  if not r.has("road_mesh"):continue
  var occ=Foot.record_shapes(r);var shape=Foot.record_shape(wall)
  if Foot.batches_overlap(occ,[shape]):diagnose(r,geometry,occ,shape)
 quit()
func diagnose(road:Dictionary,data:Dictionary,occupancy:Array,shape:Dictionary)->bool:
 if not data.get("known",false):return true
 var pose:=Transform3D(Basis.from_euler(City.vec(road.rotation)*PI/180),City.vec(road.position))
 var polygons:=Road.local_polygons(road)
 for index in polygons.size():
  if not Foot.overlaps(occupancy[index],shape):continue
  var top:Array=Array(polygons[index]).map(func(p):return pose*p)
  var planes:Array=[];var center:=Vector3.ZERO
  for i in top.size():
   var a:Vector3=top[i];var b:Vector3=top[(i+1)%top.size()];center+=a
   var normal:=Vector3(-(b.z-a.z),0,b.x-a.x).normalized()
   planes.append([normal,-normal.dot(a)-EPS])
  var plane:=Plane(top[0],top[1],top[2]);var normal:=plane.normal;var distance:=plane.d
  if normal.y<0:normal=-normal;distance=-distance
  if normal.y<.0001:return true
  planes.append([normal,-distance+(road.size[1]-EPS)*normal.y])
  planes.append([-normal,distance+(road.get("road_clearance",3.)-EPS)*normal.y])
  for face:Dictionary in data.faces:
   if not face.bounds.intersects(occupancy[index].bounds):continue
   var cut:Array=face.points
   for item:Array in planes:
    cut=Clip.clip(cut,item[0],item[1])
    if cut.size()<3:break
   if cut.size()<3:continue
   var area:=0.
   for i in range(1,cut.size()-1):area+=(cut[i]-cut[0]).cross(cut[i+1]-cut[0]).length()*.5
   if area>.0000001:
    print("FACE ",JSON.stringify({"road":road.uuid,"triangle":face.points,"cut":cut,"area":area,"top":top}));return true
  center/=top.size()
  for solid:Array in data.solids:
   if Contact.inside(center+Vector3.UP*.05,solid):
    print("INSIDE ",road.uuid," ",center," solid ",data.solids.find(solid));trace(center+Vector3.UP*.05,solid);quit();return true
 return false


func trace(point:Vector3,faces:Array)->void:
 var direction=Vector3(.193,1,.431).normalized();var hits=[]
 for f in faces:
  var p=f.points;var hit=Geometry3D.ray_intersects_triangle(point,direction,p[0],p[1],p[2])
  if hit!=null:hits.append({"distance":point.distance_to(hit),"hit":hit,"normal":(p[1]-p[0]).cross(p[2]-p[0]).normalized()})
 hits.sort_custom(func(a,b):return a.distance<b.distance)
 print(JSON.stringify(hits))
