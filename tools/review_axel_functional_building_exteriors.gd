extends "res://tools/review_axel_market_exteriors.gd"
## Read-only outdoor checks for the three newly imported functional buildings.
## GPU execution belongs to run_godot_background.py on the private desktop.
const FB_OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const Imported=preload("res://scripts/world3d/imported_building.gd")
const Bounds=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Channel=preload("res://scripts/world3d/channel_surface.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const KEYS=["guardhouse","church","watermill"]
var handoff:Dictionary={}
var geometry:Dictionary={}
var active_root:=""
var active_threshold:=Vector3.ZERO
var active_outward:=Vector3.FORWARD
var tread_triangles:Dictionary={}
var review_cameras:Dictionary={}

func capture(label:String,eye:Vector3,target:Vector3)->void:
	if review_cameras.has(label):
		var camera:Dictionary=review_cameras[label]
		eye=vector(camera.eye);target=vector(camera.target);capture_fov=float(camera.fov)
	await super.capture(label,eye,target)

func source_data(path:String)->Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_32()!=0x46546c67 or file.get_32()!=2:return {}
	file.get_32();var length:=file.get_32()
	if file.get_32()!=0x4e4f534a or length>4*1024*1024:return {}
	var data:Variant=JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
	if not data is Dictionary:return {}
	var size:=file.get_32()
	if file.get_32()!=0x004e4942:return {}
	return {"json":data,"bin":file.get_buffer(size)}
func accessor(data:Dictionary,index:int)->Array:
	var a:Dictionary=data.json.accessors[index];var view:Dictionary=data.json.bufferViews[a.bufferView]
	var count:=int(a.count);var scalar:=int(a.componentType);var components:=3 if a.type=="VEC3" else 1
	if a.has("sparse") or not scalar in [5121,5123,5125,5126] or not a.type in ["VEC3","SCALAR"]:return []
	var bytes:=1 if scalar==5121 else (2 if scalar==5123 else 4)
	var stride:=int(view.get("byteStride",components*bytes));var offset:=int(view.get("byteOffset",0))+int(a.get("byteOffset",0));var values:Array=[]
	for i in count:
		var at:=offset+i*stride
		if at+components*bytes>data.bin.size():return []
		if components==3:
			if scalar!=5126:return []
			values.append(Vector3(data.bin.decode_float(at),data.bin.decode_float(at+4),data.bin.decode_float(at+8)))
		else:values.append(data.bin.decode_u8(at) if scalar==5121 else (data.bin.decode_u16(at) if scalar==5123 else data.bin.decode_u32(at)))
	return values
func source_geometry(record:Dictionary)->Dictionary:
	var bounds:=Bounds.read(record.asset_path);var data:=source_data(record.asset_path)
	if not bounds.get("known",false) or data.is_empty():return {"ok":false}
	var pose:=Imported.frame(record);var parts:Array=[]
	for mesh:Dictionary in bounds.mesh_nodes:
		var node:Dictionary=data.json.nodes[mesh.node_index];var extras:Dictionary=node.get("extras",{});var semantic:Dictionary=extras.get("rmmo_part",{})
		var source_id:=str(extras.get("rmmo_source_uuid",extras.get("uuid","")));var id:=str(record.uuid)+"__"+source_id
		var transform:Transform3D=pose*mesh.transform;var world_box:AABB=transform*mesh.mesh_bounds
		var part:={"id":id,"source_id":source_id,"semantic":semantic,"collision":str(extras.get("rmmo_collision","")),"group":str(extras.get("semantic_group","")),"world_box":world_box,"transform":transform,"triangles":[]}
		# Decode actual source faces only for foundation and exterior tread work.
		# A whole-building AABB is never treated as a bearing surface.
		# Imported walkable porches can retain role=body while explicitly
		# declaring walk collision. Judge their actual outside-door top faces.
		if int(semantic.get("floor",-1))==0 and (semantic.get("role","") in ["floor","stairs"] or part.collision=="walk" or str(semantic.get("part","")).begins_with("river_foundation_")):
			for primitive:Dictionary in data.json.meshes[mesh.mesh_index].primitives:
				if int(primitive.get("mode",4))!=4:return {"ok":false,"error":"Nontriangle foundation primitive"}
				var vertices:=accessor(data,int(primitive.attributes.POSITION));var indices:Array=accessor(data,int(primitive.indices)) if primitive.has("indices") else range(vertices.size())
				if vertices.is_empty() or indices.size()%3!=0:return {"ok":false,"error":"Invalid source foundation accessor"}
				for i in range(0,indices.size(),3):
					var tri:Array=[transform*vertices[int(indices[i])],transform*vertices[int(indices[i+1])],transform*vertices[int(indices[i+2])]]
					if (tri[1]-tri[0]).cross(tri[2]-tri[0]).length_squared()>.00000001:part.triangles.append(tri)
		parts.append(part)
	return {"ok":true,"parts":parts,"bounds":pose*bounds.local_bounds}
func terrain_range(polygon:PackedVector2Array)->Dictionary:
	var low:=INF;var high:=-INF;var area:=0.;var rect:=Rect2(polygon[0],Vector2.ZERO)
	for p:Vector2 in polygon:rect=rect.expand(p)
	for tile:Dictionary in terrain_records:
		var pose:=Terrain.transform(tile);var box:AABB=pose*Terrain.bounds(tile)
		if not rect.intersects(Rect2(box.position.x,box.position.z,box.size.x,box.size.z),true):continue
		for z in int(tile.terrain_mesh.rows):
			for x in int(tile.terrain_mesh.columns):
				if not Terrain.solid(tile.terrain_mesh,x,z):continue
				var points:Array=Terrain.cell(tile,x,z).map(func(p):return pose*p)
				var cell:=Rect2(Vector2(points[0].x,points[0].z),Vector2.ZERO)
				for p:Vector3 in points:cell=cell.expand(Vector2(p.x,p.z))
				if not rect.intersects(cell,true):continue
				for indices:Array in [[0,1,2],[0,2,3]]:
					var triangle:=PackedVector2Array();var a:Vector3=points[indices[0]];var normal:Vector3=(points[indices[1]]-a).cross(points[indices[2]]-a)
					for at:int in indices:triangle.append(Vector2(points[at].x,points[at].z))
					for patch:PackedVector2Array in Geometry2D.intersect_polygons(polygon,triangle):
						area+=absf(Poly.area(Array(patch)))
						for p:Vector2 in patch:
							var height:=a.y-(normal.x*(p.x-a.x)+normal.z*(p.y-a.z))/normal.y;low=minf(low,height);high=maxf(high,height)
	var expected:=absf(Poly.area(Array(polygon)))
	return {"min":low if is_finite(low) else null,"max":high if is_finite(high) else null,"covered_area":area,"expected_area":expected,"complete":is_finite(low) and absf(area-expected)<maxf(.001,expected*.00001)}
func flat_triangle(triangle:Array)->PackedVector2Array:
	var polygon:=PackedVector2Array()
	for point:Vector3 in triangle:polygon.append(Vector2(point.x,point.z))
	return polygon
func foundations(key:String,record:Dictionary,source:Dictionary)->Dictionary:
	var rows:Array=[];var modules:Dictionary={};var floor_y:float=record.position[1]+(0. if key=="watermill" else .3)
	for part:Dictionary in source.parts:
		var relevant:bool=str(part.semantic.get("part","")).begins_with("river_foundation_") if key=="watermill" else (int(part.semantic.get("floor",-1))==0 and part.semantic.get("role","")=="floor" and part.world_box.position.y<=float(record.position[1])+.005)
		if not relevant:continue
		var faces:=0
		for triangle:Array in part.triangles:
			if not triangle.all(func(p):return absf(p.y-part.world_box.position.y)<.005):continue
			var polygon:=flat_triangle(triangle)
			if absf(Poly.area(Array(polygon)))<.00001:continue
			var sampled:=terrain_range(polygon);var base:float=part.world_box.position.y
			var good:bool=sampled.complete and sampled.min>=base-.005 and sampled.max<=floor_y+.005
			rows.append({"source_component":part.source_id,"semantic_part":part.semantic.part,"bottom_triangle":triangle.map(func(p):return xyz(p)),"base_y":base,"terrain":sampled,"passed":good});faces+=1
		modules[part.semantic.part]=faces
	var good:bool=not rows.is_empty() and rows.all(func(row):return row.passed) and modules.values().all(func(count):return count>0)
	if key=="watermill":good=good and modules.size()==7
	check(good,"actual source foundation faces reach terrain "+key,{"modules":modules,"invalid":rows.filter(func(r):return not r.passed)})
	return {"passed":good,"source_bottom_faces":rows,"modules":modules,"method":"Actual GLB source component bottom triangles against every intersecting native terrain triangle; no whole-building AABB support assumption"}
func local_polygon(points:Array,pose:Transform3D)->PackedVector2Array:
	var polygon:=PackedVector2Array()
	for p:Array in points:
		var at:=pose*Vector3(p[0],0,p[1]);polygon.append(Vector2(at.x,at.z))
	return polygon
func waterwheel(record:Dictionary,source:Dictionary)->Dictionary:
	var wheel:Dictionary=handoff.designs.watermill.waterwheel;var pose:=Imported.frame(record);var c:Array=wheel.clear_water_corridor_xz
	var corridor:=local_polygon([[c[0],c[1]],[c[2],c[1]],[c[2],c[3]],[c[0],c[3]]],pose);var bed:=terrain_range(corridor)
	var wheel_parts:Array=source.parts.filter(func(p):return p.semantic.get("part","")=="waterwheel")
	var bearing:Array=source.parts.filter(func(p):return p.semantic.get("part","")=="wheel_support")
	var axles:Array=source.parts.filter(func(p):return p.semantic.get("part","")=="drive_axle")
	if not check(wheel_parts.size()==1 and bearing.size()==1 and axles.size()==1,"actual wheel, axle and bearing source components exist"):return {"passed":false}
	var bottom:float=wheel_parts[0].world_box.position.y;var axis:Vector3=wheel_parts[0].transform.origin;var designed:Vector3=pose*vector(wheel.axis_center)
	var area:=0.;var levels:Array=[];var water_ids:Dictionary={}
	for water:Dictionary in document.records:
		if water.get("surface_id","")!="water" or not water.has("channel_mesh"):continue
		var water_pose:=Transform3D(Basis.from_euler(vector(water.rotation)*PI/180),vector(water.position))
		for poly:Array in Channel.local_polygons(water):
			var points:Array=poly.map(func(p):return water_pose*p);var flat:=flat_triangle(points)
			for patch:PackedVector2Array in Geometry2D.intersect_polygons(corridor,flat):
				area+=absf(Poly.area(Array(patch)));water_ids[water.uuid]=true;var plane:=Plane(points[0],points[1],points[2])
				for p:Vector2 in patch:levels.append((plane.d-plane.normal.x*p.x-plane.normal.z*p.y)/plane.normal.y)
	var required:=absf(Poly.area(Array(corridor)));var wet:bool=not levels.is_empty() and absf(area-required)<maxf(.001,required*.00001)
	var allowed:Array=wheel.accepted_water_y_design_range;var min_water:float=levels.min() if wet else -INF;var max_water:float=levels.max() if wet else INF
	var bearing_at:Vector3=pose*vector(wheel.outer_bearing_position)
	var geometry_ok:bool=axis.distance_to(designed)<.001 and absf(bottom-(float(record.position[1])+float(wheel.bottom_y)))<.01 and bearing[0].world_box.grow(.001).has_point(bearing_at) and axles[0].world_box.grow(.001).has_point(bearing_at)
	var good:bool=geometry_ok and bed.complete and bed.max<=float(record.position[1])+float(wheel.minimum_bed_y)+.0001 and bottom-bed.max>=.249 and wet and min_water>=float(record.position[1])+allowed[0]-.0001 and max_water<=float(record.position[1])+allowed[1]+.0001
	var result:={"passed":good,"actual_axis_world":xyz(axis),"actual_source_wheel_bottom_y":bottom,"bed":bed,"minimum_wheel_bed_clearance_m":bottom-bed.max if bed.complete else null,"actual_water_levels":[min_water,max_water] if wet else [],"water_ids":water_ids.keys(),"covered_water_area":area,"required_water_area":required,"bearing_source":bearing[0].source_id,"bearing_world":xyz(bearing_at),"axis_and_actual_component_geometry_passed":geometry_ok,"water_drive_animation_tested":false}
	check(good,"actual wheel, flowing-water footprint, bed and source supports agree",result);return result
func prepare_imported_treads(record:Dictionary,source:Dictionary,access:Dictionary)->void:
	active_root=str(record.uuid);active_threshold=vector(access.threshold);active_outward=vector(access.outward).normalized();tread_triangles.clear()
	for part:Dictionary in source.parts:
		records[part.id]={"building":{"id":active_root,"role":part.semantic.get("role",""),"floor":part.semantic.get("floor",-1)}}
		if int(part.semantic.get("floor",-1))!=0 or not (part.semantic.get("role","") in ["floor","stairs"] or part.get("collision","")=="walk"):continue
		var accepted:Array=[]
		for triangle:Array in part.triangles:
			var normal:Vector3=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized()
			if normal.y<.99:continue
			if triangle[0].y>active_threshold.y+.035 or triangle[0].y<float(record.position[1])-.4:continue
			accepted.append(triangle)
		if not accepted.is_empty():tread_triangles[part.id]=accepted
func step_owner(id:String)->bool:return tread_triangles.has(id)
func authored_step(point:Vector3,id:String)->bool:
	if not tread_triangles.has(id):return false
	var along:float=(point-active_threshold).dot(active_outward)
	if along<.35 or along>4.:return false
	for triangle:Array in tread_triangles[id]:
		if absf(point.y-triangle[0].y)>.035:continue
		var p:=Vector2(point.x,point.z);var poly:=flat_triangle(triangle)
		if Geometry2D.is_point_in_polygon(p,poly):return true
		for i in 3:
			# The authored 15 mm bevel becomes 0.0150076 m at this town's
			# float32 coordinates. Twenty micrometres cover that rounding only.
			if Geometry2D.get_closest_point_to_segment(p,poly[i],poly[(i+1)%3]).distance_to(p)<=.01502:return true
	return false
func step_contact_points(feet_point:Vector3,id:String,points:PackedVector3Array)->Dictionary:
	var invalid:Array=[];var evidence:Array=[]
	if not step_owner(id) or points.is_empty() or points.size()%2!=0 or points.size()>=256:return {"passed":false,"reason":"Missing or truncated exact source tread contact pairs"}
	for i in range(0,points.size(),2):
		var capsule_point:Vector3=points[i];var source_point:Vector3=points[i+1]
		var low_contact:=true
		for point:Vector3 in [capsule_point,source_point]:
			if not point.is_finite() or point.y>feet_point.y+.32 or point.y<feet_point.y-.035:low_contact=false
		# collide_shape pairs contain a point on the query capsule followed by
		# one on the environment. Only the latter belongs to the GLB tread;
		# requiring the capsule point to lie in that plane rejects real steps.
		var valid:bool=low_contact and authored_step(source_point,id)
		var pair:={"capsule_point":xyz(capsule_point),"source_point":xyz(source_point),"both_within_low_step_height":low_contact,"source_on_authored_tread":authored_step(source_point,id),"passed":valid}
		evidence.append(pair)
		if not valid:invalid.append(pair)
	return {"passed":invalid.is_empty(),"contact_points":points.size(),"invalid_pairs":invalid,"pairs":evidence,"method":"Actual collide_shape environment endpoint on outside-door upward GLB tread triangles; both endpoints remain inside the original low-step height band"}
func capsule_clear(point:Vector3)->Dictionary:
	var shape:CollisionShape3D=world._player.get_node("CollisionShape3D");var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape.shape
	query.transform=world._player.global_transform*shape.transform;query.transform.origin=point+Vector3.UP*.94+shape.position;query.exclude=[world._player.get_rid()];query.collision_mask=world._player.collision_mask;query.margin=.001
	var contacts:Array=world._player.get_world_3d().direct_space_state.intersect_shape(query,64);var blocked:Array=[];var supports:Array=[];var visited:Dictionary={}
	if contacts.size()>=64:blocked.append({"reason":"Capsule contacts truncated"})
	for contact:Dictionary in contacts:
		var id:=object_id(contact.collider);var record:Dictionary=records.get(id,{});var rid:RID=contact.get("rid",RID())
		if visited.has(rid):continue
		visited[rid]=true
		if record.has("terrain_mesh") or record.has("road_mesh"):supports.append(id);continue
		if step_owner(id) and rid.is_valid():
			var excluded:Array[RID]=[world._player.get_rid()]
			for other:Dictionary in contacts:
				var other_rid:RID=other.get("rid",RID())
				if other_rid.is_valid() and other_rid!=rid and not excluded.has(other_rid):excluded.append(other_rid)
			query.exclude=excluded;var pairs:PackedVector3Array=world._player.get_world_3d().direct_space_state.collide_shape(query,128);var exact:=step_contact_points(point,id,pairs)
			if exact.passed:supports.append({"id":id,"contacts":exact})
			else:blocked.append({"id":id,"contacts":exact})
		else:blocked.append({"id":id,"reason":"Non-ground/non-exterior-tread collider"})
	return {"passed":blocked.is_empty(),"blocked":blocked,"support_contacts":supports}
func saved_pavement_point(at:Vector3)->Dictionary:
	# A remote waypoint may not yet have streamed collision. Resolve its exact
	# authored pavement top first; verify live collision only after walking there.
	var result:Dictionary={"ok":false};var query:=Vector2(at.x,at.z)
	for road:Dictionary in document.records:
		if not road.has("road_mesh"):continue
		var pose:=Transform3D(Basis.from_euler(vector(road.rotation)*PI/180),vector(road.position))
		for polygon:Array in preload("res://scripts/world3d/road_surface.gd").local_polygons(road):
			var points:Array=polygon.map(func(p):return pose*p)
			for i in range(1,points.size()-1):
				var tri:Array=[points[0],points[i],points[i+1]];var flat:=flat_triangle(tri)
				var inside:=Geometry2D.is_point_in_polygon(query,flat)
				for j in 3:
					inside=inside or Geometry2D.get_closest_point_to_segment(query,flat[j],flat[(j+1)%3]).distance_to(query)<.0002
				if not inside:continue
				var plane:=Plane(tri[0],tri[1],tri[2])
				if absf(plane.normal.y)<.7:continue
				var height:float=(plane.d-plane.normal.x*at.x-plane.normal.z*at.z)/plane.normal.y
				if not result.ok or height>float(result.position[1]):result={"ok":true,"id":road.uuid,"position":[at.x,height,at.z]}
	return result

func pavement_source_interior(source:Dictionary)->bool:
	if not source.get("ok",false):return false
	var road:Dictionary=records.get(source.get("id",""),{})
	if not road.has("road_mesh"):return false
	var at:=vector(source.position);var query:=Vector2(at.x,at.z)
	var pose:=Transform3D(Basis.from_euler(vector(road.rotation)*PI/180),vector(road.position))
	for polygon:Array in preload("res://scripts/world3d/road_surface.gd").local_polygons(road):
		var points:=PackedVector2Array()
		for p:Vector3 in polygon:
			var world_point:Vector3=pose*p;points.append(Vector2(world_point.x,world_point.z))
		if not Geometry2D.is_point_in_polygon(query,points):continue
		var edge_distance:=INF
		for i in points.size():edge_distance=minf(edge_distance,Geometry2D.get_closest_point_to_segment(query,points[i],points[(i+1)%points.size()]).distance_to(query))
		if edge_distance>.0002:return true
	return false
func pavement_hit_matches(source:Dictionary,hit:Dictionary,owner:String)->bool:
	return source.get("ok",false) and source.get("id","")==owner and records.get(owner,{}).has("road_mesh") and hit.get("ok",false) and hit.get("id","")==owner and float(hit.get("normal",[0,0,0])[1])>=cos(deg_to_rad(45)) and absf(float(hit.get("position",[0,-999,0])[1])-float(source.position[1]))<.005
func pavement_center_allows_patch(source:Dictionary,hit:Dictionary)->bool:
	if not source.get("ok",false) or not records.get(source.get("id",""),{}).has("road_mesh") or not hit.get("ok",false) or not records.get(hit.get("id",""),{}).has("terrain_mesh"):return false
	return float(hit.get("normal",[0,0,0])[1])>=cos(deg_to_rad(45)) and absf(float(source.position[1])-float(hit.get("position",[0,-999,0])[1])-.025)<.005
func pavement_arrival_patch_result(source:Dictionary,hit:Dictionary,patch:Array)->Dictionary:
	var result:={"passed":false,"authored":source,"hit":hit,"contact_patch":patch,"mode":"center"}
	var owner:=str(source.get("id",""))
	if pavement_hit_matches(source,hit,owner):result.passed=true;return result
	result.mode="strict_four_corner_support"
	result.diagnosis={"path":FB_OUT+"/mill_approach_road_diagnosis.json","sha256":"b5e19467518e31fe078aede7cafb01929aa8f15c85c1b029be0095cd17763082"}
	result.center_terrain_below_pavement=pavement_center_allows_patch(source,hit)
	if not result.center_terrain_below_pavement or patch.size()!=4:return result
	var expected_offsets:Array=[Vector2(.02,.02),Vector2(-.02,.02),Vector2(-.02,-.02),Vector2(.02,-.02)]
	for i in 4:
		var sample:Dictionary=patch[i];var offset:Array=sample.get("offset",[])
		if offset.size()!=2 or Vector2(offset[0],offset[1]).distance_to(expected_offsets[i])>.000001:return result
		if not sample.get("source_interior",false) or not pavement_hit_matches(sample.get("source",{}),sample.get("hit",{}),owner):return result
		var expected_xz:Vector2=Vector2(source.position[0],source.position[2])+expected_offsets[i]
		for position:Array in [sample.source.position,sample.hit.position]:
			if Vector2(position[0],position[2]).distance_to(expected_xz)>.00005:return result
	result.passed=true;return result
func pavement_arrival_support(source:Dictionary)->Dictionary:
	# A zero-width ray can miss a micrometre-wide clipped polygon seam. Never
	# substitute terrain for pavement: all four source-interior corners must hit
	# this same real road at their own authored height. Walking remains unchanged.
	var at:=vector(source.position);var hit:=ray_surface(at,1.,2.);var patch:Array=[]
	if not pavement_hit_matches(source,hit,str(source.get("id",""))) and pavement_center_allows_patch(source,hit):
		for offset:Vector2 in [Vector2(.02,.02),Vector2(-.02,.02),Vector2(-.02,-.02),Vector2(.02,-.02)]:
			var point:=at+Vector3(offset.x,0,offset.y);var authored:=saved_pavement_point(point)
			patch.append({"offset":[offset.x,offset.y],"source":authored,"source_interior":pavement_source_interior(authored),"hit":ray_surface(point,1.,2.)})
	return pavement_arrival_patch_result(source,hit,patch)

func audit_functional(placement:Dictionary,access:Dictionary)->void:
	var key:=str(placement.key);var before_failures:=failures;var row:={"key":key,"passed":false,"uuid":placement.uuid,"source_sha256":placement.source_sha256};report.functional_buildings.checks.append(row);report.phase="functional_"+key
	var record:Dictionary=records[placement.uuid];var source:Dictionary=geometry[key];prepare_imported_treads(record,source,access)
	row.foundation=foundations(key,record,source)
	if key=="watermill":row.waterwheel=waterwheel(record,source)
	var points:Array=access.get("access_points_xz",[])
	if not check(points.size()>=2 and points.all(func(p):return p is Array and p.size()==2),"actual authored public approach points "+key):save_report();return
	var start:=ground_point(Vector3(points[0][0],0,points[0][1]));var anchor:=layout_view_anchor(start)
	if not check(anchor.ok and vector(anchor.position).distance_to(start)<1.,"approach begins on saved native road "+key,anchor):save_report();return
	if not await relocate(vector(anchor.position)+Vector3.UP*.04,"functional "+key+" existing road"):save_report();return
	var routes:Array=[];var pavement_arrivals:=0
	for i in range(1,points.size()):
		var at:=ground_point(Vector3(points[i][0],0,points[i][1]));var authored:=saved_pavement_point(at)
		if not check(authored.ok,"saved approach contains authored pavement "+key+" "+str(i),authored):break
		routes.append(await walk_route(vector(authored.position),key+" public approach "+str(i)))
		if not routes.back().passed:break
		var arrival:=pavement_arrival_support(authored)
		if not check(arrival.passed,"arrived approach has actual streamed pavement "+key+" "+str(i),arrival):break
		pavement_arrivals+=1
	var public_complete:bool=routes.size()==points.size()-1 and pavement_arrivals==routes.size() and routes.all(func(r):return r.passed)
	row.road_walks=routes;check(public_complete,"complete public approach walked "+key)
	var side:=Vector3(active_outward.z,0,-active_outward.x);var samples:Array=[];var center:Dictionary={};var joins:Array=[];var previous:Dictionary={}
	for offset in [2.4,1.8,1.2,.85]:
		for lane in [-.30,0.,.30]:
			var at:=active_threshold+active_outward*float(offset)+side*float(lane);var hit:=ray_surface(at,.7,3.);var good:bool=hit.ok;var clear:Dictionary={}
			if good:
				var owner:Dictionary=records.get(hit.id,{});good=owner.has("terrain_mesh") or owner.has("road_mesh") or authored_step(vector(hit.position),hit.id)
				clear=capsule_clear(vector(hit.position));good=good and clear.passed
			samples.append({"offset":offset,"lane":lane,"hit":hit,"clearance":clear,"passed":good})
			if lane==0. and hit.ok:
				center[str(offset)]=hit
				if not previous.is_empty():joins.append({"rise":absf(float(hit.position[1])-float(previous.position[1])),"passed":absf(float(hit.position[1])-float(previous.position[1]))<=.32})
				previous=hit
	check(samples.all(func(s):return s.passed),"outside closed door has support and measured capsule clearance "+key,{"invalid":samples.filter(func(s):return not s.passed)})
	check(joins.size()==3 and joins.all(func(j):return j.passed),"exterior steps have no excessive unsupported rise "+key,{"joins":joins})
	var walks:Array=[]
	# Remain on the real road arrival. No teleport from road to doorstep and no
	# opening the model's closed doors to manufacture a successful route.
	if center.has("2.4") and center.has("0.85") and public_complete:
		walks.append(await walk_doorway(vector(center["2.4"].position),key+" road-to-step"))
		if walks.back().passed:walks.append(await walk_doorway(vector(center["0.85"].position),key+" stop safely outside closed door"))
		if walks.back().passed:walks.append(await walk_doorway(vector(center["2.4"].position),key+" return from step"))
	check(walks.size()==3 and walks.all(func(w):return w.passed),"physical exterior access stops outside door and returns "+key)
	row.entrance={"threshold":access.threshold,"outward":access.outward,"minimum_outside_door_offset_m":.85,"samples":samples,"joins":joins,"walks":walks,"doors_modified":false}
	var box:AABB=source.bounds;var target:=box.get_center();target.y=box.position.y+box.size.y*.43
	capture_fov=58.;await capture("functional_"+key+"_wide",target+active_outward*maxf(22.,box.size.length()*.95)+side*box.size.x*.45+Vector3.UP*maxf(4.,box.size.y*.25),target)
	var detail:=active_threshold+Vector3.UP*1.3;capture_fov=55.;await capture("functional_"+key+"_entry",detail+active_outward*7.+side*2.+Vector3.UP*1.7,detail)
	if key=="watermill":
		var pose:=Imported.frame(record);var axis:=pose*vector(handoff.designs.watermill.waterwheel.axis_center);capture_fov=58.
		await capture("functional_watermill_wheel",axis+pose.basis.x.normalized()*11.+pose.basis.z.normalized()*6.+Vector3.UP*3.3,axis-Vector3.UP*.7)
	row.passed=failures==before_failures;save_report()
func run()->void:
	started_ms=Time.get_ticks_msec();map_path="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf";output=FB_OUT+"/functional_building_exterior_runtime";build_path=FB_OUT+"/functional_buildings_apply.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_path=arg.trim_prefix("--map=").replace("\\","/").simplify_path()
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=").replace("\\","/").simplify_path()
		elif arg.begins_with("--build="):build_path=arg.trim_prefix("--build=").replace("\\","/").simplify_path()
		elif arg.begins_with("--expected-map-sha="):expected_map_sha=arg.trim_prefix("--expected-map-sha=")
		elif arg.begins_with("--expected-build-sha="):expected_build_sha=arg.trim_prefix("--expected-build-sha=")
	report={"scope":"Three new imported functional buildings: public exterior access, foundation contact, waterwheel/river relationship and seven scene views","not_tested":["interiors","door operation","old residences","old bridges","whole-town performance","waterwheel-drive animation"],"checks":[],"screenshots":[],"phase":"metadata","map_path":map_path,"functional_buildings":{"passed":false,"build_receipt_sha256":"","checks":[]}}
	if not Paths.allowed(output) or DirAccess.make_dir_recursive_absolute(output)!=OK:quit(1);return
	create_timer(1500).timeout.connect(func():
		if not finished:check(false,"functional exterior review timeout",{"phase":report.phase});finish(2))
	if not check(DisplayServer.get_name()!="headless","actual renderer required") or not check(Paths.allowed(map_path) and FileAccess.file_exists(map_path),"final candidate exists"):finish();return
	if not check(Paths.allowed(build_path) and FileAccess.file_exists(build_path),"actual functional-building build receipt exists"):finish();return
	report.map_sha256=FileAccess.get_sha256(map_path);report.build_sha256=FileAccess.get_sha256(build_path);report.functional_buildings.build_receipt_sha256=report.build_sha256
	if not check(expected_map_sha.length()==64 and report.map_sha256==expected_map_sha,"exact final map SHA") or not check(expected_build_sha.length()==64 and report.build_sha256==expected_build_sha,"exact applied building receipt SHA"):finish();return
	var camera_path:=FB_OUT+"/functional_review_cameras.json"
	var camera_recipe:Variant=JSON.parse_string(FileAccess.get_file_as_string(camera_path))
	if not check(camera_recipe is Dictionary and camera_recipe.get("candidate_sha256","")==expected_map_sha and camera_recipe.get("cameras",[]).size()==7,"seven review cameras pin exact candidate"):finish();return
	for camera:Dictionary in camera_recipe.cameras:
		var good:bool=str(camera.get("id","")).is_valid_identifier() and not review_cameras.has(camera.id) and camera.get("eye",[]).size()==3 and camera.get("target",[]).size()==3 and vector(camera.eye).is_finite() and vector(camera.target).is_finite() and vector(camera.eye).distance_to(vector(camera.target))>.1 and float(camera.get("fov",0))>=30. and float(camera.get("fov",0))<=100.
		if not check(good,"finite unique review camera "+str(camera.get("id",""))):finish();return
		review_cameras[camera.id]=camera
	report.review_camera_recipe={"path":camera_path,"sha256":FileAccess.get_sha256(camera_path),"cameras":camera_recipe.cameras}
	build_receipt=JSON.parse_string(FileAccess.get_file_as_string(build_path))
	if not check(build_receipt.get("phase","")=="native_functional_buildings_complete_outdoor_review_pending" and build_receipt.get("saved",false) and build_receipt.get("native_reopen_passed",false) and int(build_receipt.get("failures",-1))==0,"three models actually applied, saved and reopened"):finish();return
	document=Document.open_file(map_path)
	if not check(document!=null,"final saved native document opens read-only"):finish();return
	for record:Dictionary in document.records:records[str(record.uuid)]=record
	terrain_records=document.records.filter(func(r):return r.has("terrain_mesh"))
	var handoff_path:=FB_OUT+"/blender_building_handoff.json";handoff=JSON.parse_string(FileAccess.get_file_as_string(handoff_path))
	var placements:Array=build_receipt.get("placements",[]);var accesses:Array=build_receipt.get("outdoor_access",[])
	check(placements.size()==3 and KEYS.all(func(key):return placements.filter(func(p):return p.key==key).size()==1),"exact three recorded model identities")
	check(City.token(document.map_meta.get("town_reference",{}).get("functional_buildings",{}).get("placements",[]))==City.token(placements),"final candidate retains actual placement receipt")
	check(City.analyze(City.resolve(document.map_meta).roads).ok,"current final native road graph valid")
	for placement:Dictionary in placements:
		var actual:Dictionary=records.get(str(placement.uuid),{});var key:=str(placement.key)
		var good:bool=not actual.is_empty() and actual.get("asset_path","")==placement.asset_path and FileAccess.get_sha256(placement.asset_path)==placement.source_sha256 and City.token(actual.get("model_building",{}))==placement.model_building_token
		good=good and vector(actual.get("position",[INF,INF,INF])).distance_to(vector(placement.position))<.00001 and vector(actual.get("rotation",[INF,INF,INF])).distance_to(vector(placement.rotation))<.00001 and vector(actual.get("size",[0,0,0])).distance_to(Vector3.ONE)<.00001
		if not check(good,"actual native model identity, components and pose "+key):continue
		var published:Dictionary=handoff.get("formal_publications",{}).get(key,{})
		check(published.get("asset_id","")==actual.asset_path and published.get("source",{}).get("sha256","")==placement.source_sha256,"current published source supports design anchors "+key)
		check(accesses.filter(func(a):return a.key==key and a.uuid==placement.uuid).size()==1,"one actual exterior approach record "+key)
		geometry[key]=source_geometry(actual);check(geometry[key].get("ok",false),"actual source geometry readable "+key)
	if failures:finish();return
	capture_directory=output.path_join("images_"+expected_map_sha.left(12)+"_"+str(Time.get_unix_time_from_system()).replace(".","_"));check(DirAccess.make_dir_recursive_absolute(capture_directory)==OK,"fresh functional exterior image directory")
	Engine.max_fps=60;root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	preload("res://tools/world3d_test_character.gd").ensure(self);var session=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"};session.world3d_requested=true;session.loading_mode="world3d_preview";session.world3d_map_path=map_path;session.world3d_spawn=Vector3(0,.9,4);session.prepared_world3d=null
	report.phase="native_loading";save_report()
	if not check(change_scene_to_file("res://scenes/loading.tscn")==OK,"production LoadingScene"):finish();return
	while not finished:
		await process_frame;world=current_scene
		if world==null:continue
		if world.has_meta("entry_loading_error"):check(false,"runtime loading failed",{"error":world.get_meta("entry_loading_error")});finish();return
		if world.has_method("is_world_ready") and world.is_world_ready() and not session._world_transition_active:break
	if finished:return
	check(canonical_path(world._map_path)==canonical_path(map_path),"production runtime loaded exact final candidate")
	for placement:Dictionary in placements:await audit_functional(placement,accesses.filter(func(a):return a.key==placement.key)[0])
	check(report.functional_buildings.checks.size()==3 and report.functional_buildings.checks.all(func(r):return r.passed),"three actual exterior probe suites passed")
	check(report.screenshots.size()==7,"all seven exclusive functional exterior views captured")
	check(FileAccess.get_sha256(map_path)==expected_map_sha and FileAccess.get_sha256(build_path)==expected_build_sha,"review leaves exact map and build receipt unchanged")
	report.functional_buildings.passed=failures==0;report.phase="complete";finish()
