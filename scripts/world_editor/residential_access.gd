extends RefCounted
## Conservative entrance proof from the frozen collision payload, never a recipe
## rebuild. Ordinary terrain plus horizontal entrance treads are supported.
const Data=preload("res://scripts/world3d/city_layout.gd")
const House=preload("res://scripts/world3d/house_prefab.gd")
const Support=preload("res://scripts/world_editor/residential_support.gd")
const Clip=preload("res://scripts/world3d/road_plan.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const HALF_WIDTH=.4 # .30 m player capsule plus .10 m clearance on either side.
const STEP_LIMIT=.35 # Existing controller's .40 m step reach, with skin margin.

static func fail(code:String,message:String)->Dictionary:
	return {"ok":false,"code":code,"error":message,"stage":"entrance_access"}

static func entrance(records:Array,yaw:float)->Dictionary:
	var doors:Array=records.filter(func(r):return r.get("building",{}).get("floor",-1)==0 and r.get("fixture",{}).get("kind")=="door" and (str(r.fixture.id).ends_with("/entrance/door") or str(r.fixture.id).ends_with("/entry/door")))
	if doors.size()!=1:return fail("unsupported","当前需要一个明确的首层入户门；拱形通廊或多入口需单独建模入口语义")
	var r:Dictionary=doors[0].duplicate(true);r.fixture.open=0.
	var out:=Basis(Vector3.UP,deg_to_rad(yaw))*Vector3.FORWARD
	var side:=Vector3(-out.z,0,out.x);var center:=Data.vec(r.position)
	var bounds:=Geometry.bounds([r]);var floor_top:=-INF
	for floor_record:Dictionary in records:
		if floor_record.get("building",{}).get("floor",-1)!=0 or floor_record.building.get("role")!="floor":continue
		var faces:=_faces(floor_record)
		for i in range(0,faces.size(),3):
			var a:=faces[i];var b:=faces[i+1];var c:=faces[i+2]
			if absf(a.y-b.y)>.0001 or absf(a.y-c.y)>.0001:continue
			if Geometry2D.is_point_in_polygon(Vector2(center.x,center.z),PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])):floor_top=maxf(floor_top,a.y)
	if not is_finite(floor_top):return fail("unsupported","实际冻结入口下方缺少可验证的首层楼板")
	center.y=floor_top
	var lo:=INF;var hi:=-INF
	for point:Vector3 in Geometry.corners(r):lo=minf(lo,(point-center).dot(side));hi=maxf(hi,(point-center).dot(side))
	if hi-lo<HALF_WIDTH*2+.1:return fail("entrance_too_narrow","实际冻结门口不足以容纳玩家胶囊和通行余量")
	return {"ok":true,"position":center,"outward":out,"side":side,"door_id":r.uuid,"fixture_id":r.fixture.id,"floor_y":center.y,"door_bounds":{"position":Data.xyz(bounds.position),"size":Data.xyz(bounds.size)}}

static func _faces(record:Dictionary)->PackedVector3Array:
	if not record.has("house_prefab") or record.get("collision","")=="none":return PackedVector3Array()
	var data:=House.decode(record.house_prefab);var slot:=House.source_slot(record.house_prefab)
	if slot<0 or data.is_empty():return PackedVector3Array()
	var pose:=Transform3D(Basis.from_euler(Data.vec(record.rotation)*PI/180),Data.vec(record.position))
	var result:=PackedVector3Array()
	for arrays:Array in data.meshes[slot].surfaces:
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:Variant=arrays[Mesh.ARRAY_INDEX]
		if indices!=null and not indices.is_empty():
			for i:int in indices:result.append(pose*vertices[i])
		else:
			for point:Vector3 in vertices:result.append(pose*point)
	return result

static func _polygon(entry:Dictionary,from:float,to:float)->Array:
	var points:Array=[]
	for p:Vector2 in [Vector2(-HALF_WIDTH,from),Vector2(HALF_WIDTH,from),Vector2(HALF_WIDTH,to),Vector2(-HALF_WIDTH,to)]:
		var v:Vector3=entry.position+entry.side*p.x+entry.outward*p.y;points.append(Vector2(v.x,v.z))
	return _ccw(points)

static func _ccw(points:Array)->Array:
	var signed_area:=0.
	for i in range(1,points.size()-1):signed_area+=(points[i]-points[0]).cross(points[i+1]-points[0])
	if signed_area<0:points.reverse()
	return points

static func _clip3(points:Array,normal:Vector3,offset:float)->Array:
	var result:Array=[]
	for i in points.size():
		var a:Vector3=points[i];var b:Vector3=points[(i+1)%points.size()]
		var da:=normal.dot(a)+offset;var db:=normal.dot(b)+offset
		if da>=0:result.append(a)
		if (da>=0)!=(db>=0):result.append(a.lerp(b,da/(da-db)))
	return result

static func _covers(polygons:Array,region:Array)->bool:
	var remaining:Array=[region]
	for polygon:Array in polygons:
		var next:Array=[]
		for piece:Array in remaining:next.append_array(Poly.subtract(piece,polygon))
		remaining=next
		if remaining.is_empty():return true
		if remaining.size()>512:return false
	var missing:=0.
	for piece:Array in remaining:missing+=Poly.area(piece)
	return missing<=.00001

static func _blocks(faces:PackedVector3Array,polygon:Array,bottom:float,top:float)->bool:
	for i in range(0,faces.size(),3):
		if maxf(faces[i].y,maxf(faces[i+1].y,faces[i+2].y))<=bottom or minf(faces[i].y,minf(faces[i+1].y,faces[i+2].y))>=top:continue
		var clipped:Array=[faces[i],faces[i+1],faces[i+2]]
		clipped=_clip3(clipped,Vector3.UP,-bottom);clipped=_clip3(clipped,Vector3.DOWN,top)
		for j in polygon.size():
			var a:Vector2=polygon[j];var delta:Vector2=polygon[(j+1)%polygon.size()]-a
			var n:=Vector3(-delta.y,0,delta.x)
			clipped=_clip3(clipped,n,-n.dot(Vector3(a.x,0,a.y)))
			if clipped.is_empty():break
		if clipped.size()<3:continue
		for j in range(1,clipped.size()-1):
			if (clipped[j]-clipped[0]).cross(clipped[j+1]-clipped[0]).length_squared()>.0000000001:return true
	return false

static func _terrain_strip(doc,polygon:Array)->Dictionary:
	# The complete corridor already proved slope and terrain seams. Retain the
	# exact clipped triangles here for one-sided support-boundary sections.
	var origin:=Vector3(polygon[0].x,0,polygon[0].y);var local:Array=[]
	for point:Vector2 in polygon:local.append([float(point.x)-origin.x,float(point.y)-origin.z])
	local=Support.clean(local)
	var component:={"record_id":"","part":"entrance_corridor","foundation_id":"","polygon":local,"bounds":Support.bounds(local),"area":Support.area(local),"floor_bottom":0.,"foundation_bottom":0.}
	var counts:={"terrain_candidates":0,"cells_visited":0,"triangle_clips":0,"overlaps":0}
	var result:Dictionary=Support.region(doc,component,origin,counts,true)
	if result.ok:result.origin=origin;result.height_range=result.component.terrain_range
	return result

static func _section(terrain:Dictionary,entry:Dictionary,distance:float)->Dictionary:
	# Intersect the full-width boundary line with every actual support triangle.
	# Height is affine on each interval, so its two endpoints prove its extrema;
	# interval union proves the entire cross-section, without point sampling.
	var origin:Vector3=terrain.origin
	# Use the very same float32 endpoints/order as _polygon. Computing a
	# separate center first can move the line outside its clipped support strip
	# after rotation, producing a spurious full-width gap. Interpolate the
	# shared endpoints with scalar doubles; do not widen coverage tolerances.
	var left:Vector3=entry.position-entry.side*HALF_WIDTH+entry.outward*distance
	var right:Vector3=entry.position+entry.side*HALF_WIDTH+entry.outward*distance
	var q:Array=[(float(left.x)+right.x)*.5-origin.x,(float(left.z)+right.z)*.5-origin.z]
	var direction:Array=[(float(right.x)-left.x)/(2.*HALF_WIDTH),(float(right.z)-left.z)/(2.*HALF_WIDTH)]
	var intervals:Array=[];var lowest:=INF;var highest:=-INF
	for piece:Dictionary in terrain.pieces:
		var lo:=-HALF_WIDTH;var hi:=HALF_WIDTH
		var polygon:Array=piece.polygon
		for i in polygon.size():
			var a:Array=polygon[i];var b:Array=polygon[(i+1)%polygon.size()]
			var dx:float=b[0]-a[0];var dz:float=b[1]-a[1]
			var offset:float=dx*(q[1]-a[1])-dz*(q[0]-a[0])
			var slope:float=dx*direction[1]-dz*direction[0]
			if absf(slope)<1e-12:
				if offset < -1e-8:hi=lo-1.;break
			elif slope>0.:lo=maxf(lo,-offset/slope)
			else:hi=minf(hi,-offset/slope)
		if hi-lo<=1e-8:continue
		intervals.append([lo,hi])
		for t:float in [lo,hi]:
			var height:float=Support.height_at(piece.corners,[q[0]+direction[0]*t,q[1]+direction[1]*t])
			lowest=minf(lowest,height);highest=maxf(highest,height)
	intervals.sort_custom(func(a,b):return a[0]<b[0])
	var covered:=-HALF_WIDTH
	for interval:Array in intervals:
		if interval[0]>covered+.00001:return fail("unsupported","支撑切换断面存在未能可靠证明的缺口")
		covered=maxf(covered,interval[1])
	if covered<HALF_WIDTH-.00001 or not is_finite(lowest):return fail("unsupported","支撑切换断面无法完整验证")
	return {"ok":true,"low":lowest,"high":highest}

static func elevation_limit(doc,house:Array,entry:Dictionary)->Dictionary:
	# Find the outermost complete horizontal tread in actual frozen collision.
	# It supplies a necessary upper elevation bound before trying road setbacks.
	# The later corridor check still proves every tread, seam and clearance.
	var groups:Dictionary={};var farthest:=0.;var tread_y:float=entry.floor_y
	for record:Dictionary in house:
		if record.has("fixture") or record.get("building",{}).get("floor",-1)!=0:continue
		var faces:=_faces(record)
		for i in range(0,faces.size(),3):
			var a:=faces[i];var b:=faces[i+1];var c:=faces[i+2]
			if absf(a.y-b.y)>.0001 or absf(a.y-c.y)>.0001 or a.y>entry.floor_y+.01 or a.y<entry.floor_y-1.:continue
			var triangle:=_ccw([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])
			var cut:=Clip.intersection(triangle,_polygon(entry,0,8))
			if cut.size()<3 or Poly.area(cut)<.000001:continue
			var height:=snappedf(a.y,.00001)
			if not groups.has(height):groups[height]={"polygons":[],"far":0.}
			groups[height].polygons.append(triangle)
			for point:Vector2 in cut:groups[height].far=maxf(groups[height].far,(Vector3(point.x,a.y,point.y)-entry.position).dot(entry.outward))
	for height:float in groups:
		var far:float=groups[height].far
		if far<.05 or far<farthest-.0001:continue
		var strip:=_polygon(entry,far-.025,far-.00001)
		if _covers(groups[height].polygons,strip) and (far>farthest+.0001 or height>tread_y):farthest=far;tread_y=height
	var ground:Dictionary=Support.terrain_region(doc,_polygon(entry,farthest+.005,farthest+.055))
	if not ground.ok:return ground
	return {"ok":true,"maximum_shift":float(ground.height_range[0])+STEP_LIMIT-.02-tread_y,"tread_height":tread_y,"tread_distance":farthest}

static func check(doc,house:Array,entry:Dictionary,start:Vector3,width:float)->Dictionary:
	if width<HALF_WIDTH*2:return fail("access_too_narrow","入户路小于胶囊通行宽度")
	var distance:float=(start-entry.position).dot(entry.outward)
	if distance<=0:return fail("access_direction","入户路端点必须位于门前")
	var corridor:=_polygon(entry,0,distance)
	var ground:Dictionary=Support.terrain_region(doc,corridor)
	if not ground.ok:return ground.merged({"stage":"entrance_ground"},true)
	if ground.get("max_grade",INF)>1.0 or ground.get("max_seam_step",INF)>STEP_LIMIT:return fail("access_slope","门前地面坡度或地块接缝超过玩家通行范围")
	var heights:Dictionary={};var breaks:Array[float]=[0.,distance];var obstacles:Array=[]
	for r:Dictionary in house:
		if r.has("fixture"):continue
		var faces:=_faces(r)
		obstacles.append({"id":r.uuid,"faces":faces})
		if r.get("building",{}).get("floor",-1)!=0:continue
		for i in range(0,faces.size(),3):
			var a:=faces[i];var b:=faces[i+1];var c:=faces[i+2]
			if absf(a.y-b.y)>.0001 or absf(a.y-c.y)>.0001 or a.y>entry.floor_y+.01:continue
			var triangle:Array=[Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)]
			if absf(Poly.area(triangle))<.000001:continue
			triangle=_ccw(triangle)
			var cut:=Clip.intersection(triangle,corridor)
			if cut.size()<3 or absf(Poly.area(cut))<.000001:continue
			var key:=snappedf(a.y,.00001)
			if not heights.has(key):heights[key]=[]
			heights[key].append(triangle)
			for p:Vector2 in cut:
				var d:float=(Vector3(p.x,entry.position.y,p.y)-entry.position).dot(entry.outward)
				if d>.0001 and d<distance-.0001:breaks.append(d)
	breaks.sort()
	var previous:={"flat":true,"height":entry.floor_y};var maximum_step:float=ground.max_seam_step;var intervals:=0
	for i in breaks.size()-1:
		var a:float=breaks[i];var b:float=breaks[i+1]
		if b-a<.0001:continue
		var strip:=_polygon(entry,a,b);var terrain:Dictionary=_terrain_strip(doc,strip)
		if not terrain.ok:return terrain
		var low:float=terrain.height_range[0];var high:float=terrain.height_range[1];var top:float=-INF
		for height:float in heights:
			if height<high-.0001:continue
			if _covers(heights[height],strip):top=maxf(top,height)
		if is_finite(top):low=top;high=top
		var current:={"flat":is_finite(top),"height":top,"terrain":terrain}
		var step:=0.
		if previous.flat and current.flat:step=absf(previous.height-current.height)
		elif previous.flat or current.flat:
			var section:Dictionary=_section(current.terrain if previous.flat else previous.terrain,entry,a)
			if not section.ok:return section.merged({"position":Data.xyz(entry.position+entry.outward*a)},true)
			var flat_height:float=previous.height if previous.flat else current.height
			step=maxf(absf(flat_height-section.low),absf(flat_height-section.high))
		# Terrain-to-terrain variation is governed by the already-proved actual
		# triangle grades and seam jumps, never by a whole strip's total rise.
		maximum_step=maxf(maximum_step,step)
		if step>STEP_LIMIT:return fail("entrance_step","实际门槛、台阶与地面高差超过胶囊台阶能力").merged({"position":Data.xyz(entry.position+entry.outward*a),"measured_step":step,"limit":STEP_LIMIT})
		for obstacle:Dictionary in obstacles:
			# Vertical risers at proven interval boundaries are governed by the
			# step test; all collision faces inside the interval must clear feet.
			if _blocks(obstacle.faces,_polygon(entry,a+.00001,b-.00001),low+.02,high+1.8):return fail("entrance_clearance","实际冻结墙体、门框或梁遮挡了入户走廊").merged({"conflicts":[obstacle.id],"position":Data.xyz(entry.position+entry.outward*(a+b)*.5)})
		previous=current;intervals+=1
	# Independent nearby props cannot be hidden by a successful road-only check.
	var ground_lo:float=ground.height_range[0];var ground_hi:float=maxf(ground.height_range[1],entry.floor_y)
	var points:Array[Vector3]=[]
	for p:Vector2 in corridor:points.append(Vector3(p.x,ground_lo+.02,p.y));points.append(Vector3(p.x,ground_hi+1.8,p.y))
	var envelope:=Foot.from_points(points);var ids:Dictionary={}
	for r:Dictionary in house:ids[r.uuid]=true
	for r:Dictionary in doc.records:
		if ids.has(r.uuid) or r.has("terrain_mesh") or r.has("road_source") or r.get("collision","")=="none":continue
		for shape:Dictionary in Foot.record_shapes(r):
			if Foot.supporting_ground(r,shape.bounds.end.y,ground_lo):continue
			if Foot.overlaps(envelope,shape):return fail("entrance_obstructed","住宅门前通行走廊被已有物件阻挡").merged({"conflicts":[r.uuid]})
	return {"ok":true,"corridor_width":HALF_WIDTH*2,"intervals":intervals,"max_step":maximum_step,"max_grade":ground.max_grade,"max_seam_step":ground.max_seam_step,"door_id":entry.door_id,"fixture_id":entry.fixture_id,"threshold":Data.xyz(entry.position),"terrain_ids":ground.terrain_ids}
