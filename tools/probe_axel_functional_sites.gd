extends SceneTree
## Read-only native geometry/terrain design probe. Never opens an editor or saves a map.
const T=preload("res://scripts/world3d/terrain_surface.gd")
const P=preload("res://scripts/world3d/terrain_river_profile.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
var records:Array=[]
var meta:Dictionary={}
var terrain:Array=[]
var obstacles:Array=[]
var river:Dictionary={}
var curve:Dictionary={}
func _init()->void:call_deferred("run")
func ground(p:Vector2)->float:
	for tile:Dictionary in terrain:
		if not tile.rect.has_point(p):continue
		var local:Vector3=tile.inverse*Vector3(p.x,0,p.y);var h:=T.sample(tile.record,local)
		if is_finite(h):return (tile.pose*Vector3(local.x,h,local.z)).y
	return NAN
func pose(origin:Vector2,yaw:float)->Transform3D:
	return Transform3D(Basis(Vector3.UP,deg_to_rad(yaw)),Vector3(origin.x,0,origin.y))
func polygon(origin:Vector2,yaw:float,box:Array)->PackedVector2Array:
	var transform:=pose(origin,yaw);var result:=PackedVector2Array()
	for p:Vector3 in [Vector3(box[0],0,box[1]),Vector3(box[2],0,box[1]),Vector3(box[2],0,box[3]),Vector3(box[0],0,box[3])]:
		var q:=transform*p;result.append(Vector2(q.x,q.z))
	return result
func samples(origin:Vector2,yaw:float,box:Array,step:float=1.0)->Dictionary:
	var transform:=pose(origin,yaw);var low:=INF;var high:=-INF;var worst:Array=[];var result:Array=[]
	var nx:=ceili((float(box[2])-float(box[0]))/step);var nz:=ceili((float(box[3])-float(box[1]))/step)
	for xi in nx+1:
		for zi in nz+1:
			var q:Vector3=transform*Vector3(lerpf(box[0],box[2],float(xi)/nx),0,lerpf(box[1],box[3],float(zi)/nz));var h:=ground(Vector2(q.x,q.z))
			low=minf(low,h);high=maxf(high,h);result.append([q.x,h,q.z])
			if h==low:worst=[q.x,h,q.z]
	return {"min":low,"max":high,"range":high-low,"minimum_at":worst,"samples":result}
func conflicts(poly:PackedVector2Array)->Array:
	var out:Array=[];var rect:=Rect2(poly[0],Vector2.ZERO)
	for p:Vector2 in poly:rect=rect.expand(p)
	for item:Dictionary in obstacles:
		if not rect.intersects(item.rect):continue
		var intersects:=false
		for shape:Dictionary in item.shapes:
			if not Geometry2D.intersect_polygons(poly,shape.polygon).is_empty():intersects=true;break
		if intersects:out.append({"id":item.id,"kind":item.kind,"name":item.name})
	for zone:Dictionary in meta.editor_layout.zones:
		var shape:=PackedVector2Array()
		for p:Array in zone.polygon:shape.append(Vector2(p[0],p[1]))
		if not Geometry2D.intersect_polygons(poly,shape).is_empty():out.append({"id":zone.id,"kind":"no_build"})
	return out
func describe(origin:Vector2,yaw:float,box:Array,door:Vector3)->Dictionary:
	var geometry:=polygon(origin,yaw,box);var local:=pose(origin,yaw)*door;var height:=samples(origin,yaw,box)
	return {"position_xz":[origin.x,origin.y],"yaw":yaw,"envelope_xz":Array(geometry).map(func(p):return [p.x,p.y]),"terrain":height,"door_xz":[local.x,local.z],"door_original_ground":ground(Vector2(local.x,local.z)),"xz_envelope_conflicts":conflicts(geometry)}
func exact_terrain_range(poly:PackedVector2Array)->Dictionary:
	var lo:=INF;var hi:=-INF;var low_point:Array=[];var high_point:Array=[];var count:=0;var rect:=Rect2(poly[0],Vector2.ZERO)
	for p:Vector2 in poly:rect=rect.expand(p)
	for tile:Dictionary in terrain:
		if not rect.intersects(tile.rect):continue
		var r:Dictionary=tile.record
		for z in int(r.terrain_mesh.rows):
			for x in int(r.terrain_mesh.columns):
				if not T.solid(r.terrain_mesh,x,z):continue
				var world_points:Array[Vector3]=[]
				for p:Vector3 in T.cell(r,x,z):world_points.append(tile.pose*p)
				var cell_rect:=Rect2(Vector2(world_points[0].x,world_points[0].z),Vector2(world_points[2].x-world_points[0].x,world_points[2].z-world_points[0].z))
				if not cell_rect.intersects(rect):continue
				for indices:Array in [[0,1,2],[0,2,3]]:
					var triangle:=PackedVector2Array()
					for i:int in indices:triangle.append(Vector2(world_points[i].x,world_points[i].z))
					for patch:PackedVector2Array in Geometry2D.intersect_polygons(poly,triangle):
						for p:Vector2 in patch:
							var height:=ground(p);count+=1
							if height<lo:lo=height;low_point=[p.x,height,p.y]
							if height>hi:hi=height;high_point=[p.x,height,p.y]
	return {"min":lo,"max":hi,"range":hi-lo,"minimum_at":low_point,"maximum_at":high_point,"triangle_intersection_vertices":count}
func route_probe(path:Array,width:float)->Dictionary:
	var graph:={"nodes":[],"edges":[]};var samples_:Array=[];var max_grade:=0.
	for i in path.size():graph.nodes.append({"id":"site_n_%d"%i,"position":[path[i][0],ground(Vector2(path[i][0],path[i][1])),path[i][1]]})
	for i in path.size()-1:
		graph.edges.append({"id":"site_e_%d"%i,"from":"site_n_%d"%i,"to":"site_n_%d"%(i+1),"kind":"ground","width_start":width,"width_end":width})
		var a:=Vector2(path[i][0],path[i][1]);var b:=Vector2(path[i+1][0],path[i+1][1]);var count:=ceili(a.distance_to(b)/.5);var last:=ground(a)
		for j in count+1:
			var p:=a.lerp(b,float(j)/count);var h:=ground(p)
			if j>0:max_grade=maxf(max_grade,absf(h-last)/(a.distance_to(b)/count))
			last=h;samples_.append([p.x,h,p.y])
	var built:Dictionary=preload("res://scripts/world3d/road_plan.gd").build(graph,meta.editor_layout.road_surface.settings)
	return {"points_xz":path,"width":width,"centerline_original_max_grade":max_grade,"samples":samples_,"native_local_plan_ok":built.get("ok",false),"error":built.get("error",""),"local_records":built.get("records",[])}
func mill(origin:Vector2,yaw:float)->Dictionary:
	var transform:=pose(origin,yaw);var wheel:=samples(origin,yaw,[5.75,-3.1,7.95,3.1],.5);var max_distance:=0.;var min_distance:=INF
	for p:Array in wheel.samples:
		var wet:=P.sample(Vector2(p[0],p[2]),curve.path,curve.levels);max_distance=maxf(max_distance,wet.distance);min_distance=minf(min_distance,wet.distance)
	var body:=samples(origin,yaw,[-5.4,-5.4,5.4,5.4],1.8);var wheel_center:Vector3=transform*Vector3(6.85,1.1,0)
	var touches:=conflicts(polygon(origin,yaw,[-6.1,-6.1,9.0,7.6]));var hard:Array=touches.filter(func(r):return r.kind not in ["vegetation"])
	var row:={"position":[origin.x,4.0,origin.y],"yaw":yaw,"wheel_axis":[wheel_center.x,5.1,wheel_center.z],"wheel_corridor_ground_min":wheel.min,"wheel_corridor_ground_max":wheel.max,"wheel_water_distance_max":max_distance,"wheel_water_distance_min":min_distance,"wheel_corridor_all_wet":max_distance<=6.95,"wheel_bed_clear":wheel.max<=2.55,"body_ground_min":body.min,"body_ground_max":body.max,"body_low_point":body.minimum_at,"conflicts":touches,"hard_conflicts":hard,"foundation_needed_max_m":maxf(0.,4.-body.min)}
	row.score=hard.size()*100.+maxf(0.,wheel.max-2.55)*300.+maxf(0.,max_distance-6.95)*100.+maxf(0.,4.-body.min)*3.+maxf(0.,body.max-4.)*5.+absf(origin.y-195.)*.015
	return row
func run()->void:
	records=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/source_records.json"));meta=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/source_metadata.json"))
	for record:Dictionary in records:
		if record.has("terrain_mesh"):
			var transform:=T.transform(record);var bounds: AABB=transform*T.bounds(record)
			terrain.append({"record":record,"pose":transform,"inverse":transform.affine_inverse(),"rect":Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(.00001)});continue
		if record.has("channel_mesh"):continue
		var shapes:=Foot.record_shapes(record)
		if shapes.is_empty():continue
		var bounds:AABB=shapes[0].bounds
		for shape:Dictionary in shapes:bounds=bounds.merge(shape.bounds)
		var kind:="road" if record.has("road_mesh") else ("vegetation" if record.get("collision","")=="none" else "structure")
		obstacles.append({"id":record.uuid,"shapes":shapes,"kind":kind,"name":record.get("name",record.get("editor_name","")),"rect":Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))})
	for layer:Dictionary in meta.terrain_rivers:
		if layer.id=="axel_main_river":river=layer;curve=P.prepare(layer.request)
	var output:={"source_records_sha256":FileAccess.get_sha256(OUT+"/source_records.json"),"source_metadata_sha256":FileAccess.get_sha256(OUT+"/source_metadata.json"),"handoff_sha256":FileAccess.get_sha256(OUT+"/blender_building_handoff.json"),"guard":describe(Vector2(158.5,172),0,[-7.085,-5.62,7.085,6.675],Vector3(0,.3,5)),"church":describe(Vector2(304,86),-90,[-11.05,-11.5,5.5,13.2],Vector3(0,.3,11.28)),"old_mill":mill(Vector2(291,191),0),"cross_sections":[],"mill_candidates":[]}
	for z:float in [180,190,200,210,220,230]:
		var row:Array=[]
		for x in range(285,341):row.append([x,ground(Vector2(x,z)),z,P.sample(Vector2(x,z),curve.path,curve.levels).distance])
		output.cross_sections.append(row)
	var candidates:Array=[]
	for z in range(174,233,2):
		var nearest:Vector2=Vector2.INF;var distance:=INF;var tangent:=Vector2.ZERO
		for i in curve.path.size()-1:
			var a:=Vector2(curve.path[i][0],curve.path[i][1]);var b:=Vector2(curve.path[i+1][0],curve.path[i+1][1])
			if minf(a.y,b.y)<=z and maxf(a.y,b.y)>=z:
				nearest=a.lerp(b,(z-a.y)/(b.y-a.y));tangent=(b-a).normalized();break
		if not nearest.is_finite():continue
		# West-bank wheel points toward the river. Straight paddles can reverse
		# rotation; its authored flow arrow requires modeller confirmation.
		var east:=Vector2(tangent.y,-tangent.x);var yaw:=rad_to_deg(atan2(-east.y,east.x))
		for bank_distance:float in [3.8,4.0,4.2,4.4,4.6]:
			var wheel_center:=nearest-east*bank_distance;var origin:=wheel_center-east*6.85
			candidates.append(mill(origin,yaw))
	candidates.sort_custom(func(a,b):return a.score<b.score)
	output.mill_candidates=candidates.slice(0,20)
	output.mill_valid_candidates=candidates.filter(func(r):return r.wheel_bed_clear and r.wheel_corridor_all_wet and r.hard_conflicts.is_empty()).slice(0,20)
	if not output.mill_valid_candidates.is_empty():
		var best:Dictionary=output.mill_valid_candidates[0];var origin:=Vector2(best.position[0],best.position[2]);var transform:=pose(origin,best.yaw)
		var supports:Array=[]
		for item:Array in [[-5.4,-5.4],[5.4,-5.4],[5.4,5.4],[-5.4,5.4],[5.4,0.],[4.78,0.],[8.3,0.],[8.65,-.44],[8.65,.44]]:
			var at:=transform*Vector3(item[0],0,item[1]);supports.append({"local_xz":item,"world_xz":[at.x,at.z],"original_ground_y":ground(Vector2(at.x,at.z))})
		output.mill_selected=best.duplicate(true);output.mill_selected.support_points=supports
		output.mill_selected.body_exact=exact_terrain_range(polygon(origin,best.yaw,[-5.4,-5.4,5.4,5.4]))
		output.mill_selected.wheel_corridor_exact=exact_terrain_range(polygon(origin,best.yaw,[5.75,-3.1,7.95,3.1]))
		var front:=transform*Vector3(-1.5,0,9.5)
		output.mill_access=route_probe([[290,214],[298,214],[front.x,front.z]],2.6)
	output.guard_access=route_probe([[158.5,155],[158.5,163.5],[169,163.5],[169,180.5],[158.5,180.5]],2.6)
	output.church_access=route_probe([[284,85],[288,85],[288.9,86]],2.6)
	for name:String in ["guard_access","church_access","mill_access"]:
		var occupied:Array=[]
		for r:Dictionary in output[name].local_records:
			for shape:Dictionary in Foot.record_shapes(r):
				for hit:Dictionary in conflicts(shape.polygon):
					if hit.kind!="road" and not occupied.has(hit):occupied.append(hit)
		output[name].existing_nonroad_conflicts=occupied;output[name].erase("local_records")
	var file:=FileAccess.open(OUT+"/functional_sites_native_probe.json",FileAccess.WRITE);file.store_string(JSON.stringify(output,"  "));file.close()
	print("FUNCTIONAL_SITES_PROBE ",JSON.stringify({"guard_conflicts":output.guard.xz_envelope_conflicts,"church_conflicts":output.church.xz_envelope_conflicts,"best_mill":output.mill_candidates.slice(0,3)}));quit(0)
