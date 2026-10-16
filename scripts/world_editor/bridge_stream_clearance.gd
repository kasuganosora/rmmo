extends RefCounted
## A non-navigable crossing must clear the complete actual wet surface, including
## skewed banks and both faces along the flow. It never grants a boat passage.
const D=preload("res://scripts/world3d/bridge_data.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
const Meshes=preload("res://scripts/world3d/bridge_mesh.gd")
const HEIGHT:=.2
const EPS:=.00001

static func clip(poly:Array,a:Vector2,b:Vector2)->Array:
	var result:Array=[];var edge:=b-a
	for i in poly.size():
		var p:Vector3=poly[i];var q:Vector3=poly[(i+1)%poly.size()]
		var dp:float=edge.cross(Vector2(p.x,p.z)-a);var dq:float=edge.cross(Vector2(q.x,q.z)-a)
		if dp>=-EPS:result.append(p)
		if (dp>=-EPS)!=(dq>=-EPS):result.append(p.lerp(q,clampf(dp/(dp-dq),0,1)))
	return result

static func patches(waters:Array,origin:Vector3)->Array:
	var result:Array=[]
	for water:Dictionary in waters:
		var poly:PackedVector2Array=PackedVector2Array()
		for p:Vector2 in water.polygon:poly.append(p-Vector2(origin.x,origin.z))
		var indices:=Geometry2D.triangulate_polygon(poly)
		if indices.is_empty():return []
		var previous_count:int=result.size()
		for i in range(0,indices.size(),3):
			var triangle:Array=[poly[indices[i]],poly[indices[i+1]],poly[indices[i+2]]]
			var area:float=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0])
			# Ear clipping can return a collinear final triangle. It covers no
			# water; reject a wholly degenerate surface rather than invent a plane.
			if absf(area)<=EPS*EPS:continue
			if area<0:triangle.reverse()
			var bounds:=Rect2(triangle[0],Vector2.ZERO)
			for p:Vector2 in triangle:bounds=bounds.expand(p)
			result.append({"triangle":triangle,"bounds":bounds,"plane":water.plane,"source_id":water.get("source_id","")})
		if result.size()==previous_count:return []
	return result

static func measure_mesh(mesh:Mesh,pose:Transform3D,water_patches:Array)->Dictionary:
	var lowest:=INF;var witness:=Vector3.ZERO;var water_max:=-INF;var source_id:="";var touched:=0
	var faces:=mesh.get_faces()
	for i in range(0,faces.size(),3):
		# Keep XZ near zero when clipping small triangles at distant world origins.
		var triangle:Array=[pose.basis*faces[i],pose.basis*faces[i+1],pose.basis*faces[i+2]]
		var bounds:=Rect2(Vector2(triangle[0].x,triangle[0].z),Vector2.ZERO)
		for p:Vector3 in triangle:bounds=bounds.expand(Vector2(p.x,p.z))
		for water:Dictionary in water_patches:
			if not bounds.intersects(water.bounds,true):continue
			var clipped:Array=triangle
			for side in 3:
				clipped=clip(clipped,water.triangle[side],water.triangle[(side+1)%3])
				if clipped.is_empty():break
			if clipped.is_empty():continue
			touched+=1
			for p:Vector3 in clipped:
				var world:Vector3=p+pose.origin;var plane:Plane=water.plane
				if absf(plane.normal.y)<.000001:return Data.fail("溪流水面近乎垂直，无法测量桥下净空")
				var y:float=(plane.d-plane.normal.x*world.x-plane.normal.z*world.z)/plane.normal.y
				water_max=maxf(water_max,y)
				if world.y-y<lowest:lowest=world.y-y;witness=world;source_id=water.source_id
	if not is_finite(lowest):return Data.fail("桥体与实际溪流水面没有可测量的重叠区域")
	return {"ok":true,"clearance":lowest,"water_level":water_max,"minimum_at":Data.xyz(witness),"water_id":source_id,"clipped_triangles":touched}

static func measure(record:Dictionary,water_patches:Array)->Dictionary:
	var mesh:=Meshes.new().build(record)
	if mesh==null:return Data.fail("无法读取溪流桥的实际结构网格")
	var pose:=Transform3D(Basis.from_euler(Data.vec(record.rotation)*PI/180),Data.vec(record.position))
	return measure_mesh(mesh,pose,water_patches)

static func fit(record:Dictionary,waters:Array,automatic:bool)->Dictionary:
	var d:Dictionary=record.bridge_mesh;var requested:float=d.camber
	var water_patches:=patches(waters,Data.vec(record.position))
	if water_patches.is_empty():return Data.fail("溪流水面无法连续三角化，不能验证完整过水净空")
	var result:=measure(record,water_patches)
	if not result.ok:return result
	if result.clearance<HEIGHT:
		if not automatic:return Data.fail("非通航溪流桥完整水面净空 %.3f 米，不足 0.20 米；最低点 %s，水面 %s"%[result.clearance,str(result.minimum_at),result.water_id])
		var maximum:=minf(5,(d.length*.15-absf(d.get("rise",0.)))/PI)
		d.camber=maximum;var highest:=measure(record,water_patches)
		if not highest.ok or highest.clearance<HEIGHT:
			d.camber=requested
			return highest if not highest.ok else Data.fail("非通航溪流桥达到 15%% 坡度时完整水面净空仍仅 %.3f 米；请局部抬高桥头或改跨度，不能用桥墩堵住水路"%highest.clearance)
		var low:=requested;var high:=maximum
		# Exact deformed geometry is monotone in camber; no sampled centreline or
		# approximate arch formula substitutes for the complete clipped underside.
		for step in 10:
			d.camber=(low+high)*.5;var trial:=measure(record,water_patches)
			if not trial.ok:d.camber=requested;return trial
			if trial.clearance>=HEIGHT+.0001:high=d.camber
			else:low=d.camber
		d.camber=minf(maximum,ceilf(high*1000)/1000);result=measure(record,water_patches)
		if not result.ok or result.clearance<HEIGHT:
			d.camber=requested;return result if not result.ok else Data.fail("实际溪流桥网格净空不足 0.20 米")
	record.bounds_size=Data.xyz(D.dimensions(d))
	return result.merged({"applicable":true,"mode":"stream","scope":"entire_overlapped_water_surface","required_height":HEIGHT,"adjusted":d.camber>requested+.000001})
