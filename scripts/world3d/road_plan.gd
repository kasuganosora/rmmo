extends RefCounted
const Data=preload("res://scripts/world3d/city_layout.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const CELL:=32.0

static func settings_schema() -> Dictionary:
	return Data.object({"thickness":Data.S.number(.1,.5),"lift":Data.S.number(.005,.05),"clearance":Data.S.number(2.5,10),"material_id":Data.text(256)})
static func defaults() -> Dictionary:
	return {"thickness":.2,"lift":.025,"clearance":3.0,"material_id":""}

static func intersection(a: Array,b: Array) -> Array:
	var result: Array=a
	for i in b.size():
		var delta: Vector2=b[(i+1)%b.size()]-b[i]; var n:=Vector2(-delta.y,delta.x)
		result=Poly.clip(result,n,-n.dot(b[i]))
		if result.is_empty(): break
	return result

static func normalized_patch(poly: Array, center: Vector3) -> Array:
	# Clipping near a cell corner can leave micrometre slivers. Clean in cell-local
	# coordinates so large world coordinates cannot cancel the signed area.
	var points: Array=[]
	for p in poly:
		var value:=Vector2((p.x-center.x)/CELL,(p.y-center.z)/CELL)
		if points.is_empty() or value.distance_squared_to(points.back())>1e-12: points.append(value)
	if points.size()>1 and points[0].distance_squared_to(points.back())<=1e-12: points.pop_back()
	if points.size()<3: return []
	var area:=0.0
	for i in range(1,points.size()-1): area+=(points[i]-points[0]).cross(points[i+1]-points[0])
	if area<2e-9: return []
	return points.map(func(p):return [p.x,p.y])

static func build(graph: Dictionary, settings: Dictionary, portals: Array=[]) -> Dictionary:
	var issue:=Data.S.validate(settings,settings_schema())
	if not issue.is_empty(): return Data.fail(issue)
	var checked:=Data.analyze(graph)
	if not checked.ok: return checked
	for warning in checked.diagnostics:
		if warning.code not in ["grade_separated_crossing"]: return Data.fail("请先处理道路诊断再铺面："+str(warning.code))
	var chunks:={}; var sources: Array=[]; var sorted: Array=graph.edges.duplicate(true); sorted.sort_custom(func(a,b): return a.id<b.id)
	var radii:={}; var junctions:={}; var capped:={}
	for edge in sorted:
		radii[edge.from]=maxf(radii.get(edge.from,0),edge.width_start*.5); radii[edge.to]=maxf(radii.get(edge.to,0),edge.width_end*.5)
		var path: Array=checked.paths[edge.id]
		for end in [0,1]:
			var id: String=edge.from if end==0 else edge.to
			var at: Vector3=path[0] if end==0 else path[-1]
			var direction: Vector3=(path[1]-path[0]) if end==0 else (path[-2]-path[-1])
			var side:=Vector2(-direction.z,direction.x).normalized()*float(edge.width_start if end==0 else edge.width_end)*.5
			if not junctions.has(id): junctions[id]={"count":0,"points":PackedVector2Array()}
			junctions[id].count+=1
			junctions[id].points.append(Vector2(at.x,at.z)+side); junctions[id].points.append(Vector2(at.x,at.z)-side)
	for edge in sorted:
		if edge.has("bridge_ref"):
			if not portals.any(func(p):return p.edge_id==edge.id): return Data.fail("桥梁路网绑定缺失或尚未验证")
			continue # The waterway owns the physical deck; never pave a duplicate.
		var path: Array=checked.paths[edge.id]; var y: float=path[0].y
		var ramp: bool=path.any(func(p):return absf(p.y-y)>.001)
		if ramp:
			if edge.has("controls"): return Data.fail("当前坡道需用直线段，弯曲坡道请拆成带平坦节点的多段："+edge.id)
			var delta: Vector3=path[-1]-path[0]; var length_: float=Vector2(delta.x,delta.z).length()
			var run: float=length_-radii[edge.from]-radii[edge.to]
			if run<1 or absf(delta.y)/run>.15: return Data.fail("坡道扣除两端平坦接驳后坡度超过 15%，请加长道路："+edge.id)
			var start: Vector3=path[0]+Vector3(delta.x,0,delta.z)*float(radii[edge.from])/length_
			var end: Vector3=path[-1]-Vector3(delta.x,0,delta.z)*float(radii[edge.to])/length_
			path=[path[0],start,end,path[-1]]
		# Smooth sampled bends share cross sections. Stacking a complete disc at
		# every sample creates thousands of tiny clipped patches in a city curve.
		# Keep the established round join for tight turns and short/wide segments.
		var joins:={}
		if not ramp:
			for i in range(1,path.size()-1):
				var before:=Vector2(path[i].x-path[i-1].x,path[i].z-path[i-1].z)
				var after:=Vector2(path[i+1].x-path[i].x,path[i+1].z-path[i].z)
				var u:=before.normalized(); var v:=after.normalized()
				if u.dot(v)<.95: continue
				var normal:=Vector2(-u.y,u.x); var bisector:=(normal+Vector2(-v.y,v.x)).normalized()
				var offset:=bisector/bisector.dot(normal)
				var extension:=absf(offset.dot(u))*maxf(edge.width_start,edge.width_end)*.5
				if extension<minf(before.length(),after.length())*.45: joins[i]=offset
		for i in path.size()-1:
			var a:=Vector2(path[i].x,path[i].z); var b:=Vector2(path[i+1].x,path[i+1].z)
			var n:=Vector2(-(b-a).y,(b-a).x).normalized()
			var t0: float=Vector2(path[i].x-path[0].x,path[i].z-path[0].z).length()/Vector2(path[-1].x-path[0].x,path[-1].z-path[0].z).length() if ramp else float(i)/(path.size()-1)
			var t1: float=Vector2(path[i+1].x-path[0].x,path[i+1].z-path[0].z).length()/Vector2(path[-1].x-path[0].x,path[-1].z-path[0].z).length() if ramp else float(i+1)/(path.size()-1)
			var w0:=lerpf(edge.width_start,edge.width_end,t0)*.5; var w1:=lerpf(edge.width_start,edge.width_end,t1)*.5
			var grade: Vector2=(b-a)*(path[i+1].y-path[i].y)/(b-a).length_squared()
			var plane:=Vector3(grade.x,grade.y,path[i].y-grade.dot(a))
			var start_offset: Vector2=joins.get(i,n)*w0; var end_offset: Vector2=joins.get(i+1,n)*w1
			sources.append({"polygon":[a-start_offset,b-end_offset,b+end_offset,a+start_offset],"plane":plane,"kind":edge.kind,"edge":edge})
		for i in path.size():
			# Round caps and round joins avoid unbounded miter spikes at acute corners.
			if i==0 or i==path.size()-1:
				var id: String=edge.from if i==0 else edge.to
				if junctions[id].count>1:
					if capped.has(id): continue
					capped[id]=true
					# Connected streets end at their shared cross sections. A full
					# dead-end disc here pokes through the far side of a narrow T.
					var hull:=Geometry2D.convex_hull(junctions[id].points)
					if hull.size()>3:
						var polygon: Array=Array(hull).slice(0,-1)
						if Poly.area(polygon)<0: polygon.reverse()
						sources.append({"polygon":polygon,"plane":Vector3(0,0,path[i].y),"kind":edge.kind,"edge":edge})
					continue
			if i>0 and i<path.size()-1:
				if joins.has(i): continue
				if ramp: continue
				if (path[i]-path[i-1]).normalized().dot((path[i+1]-path[i]).normalized())>.99999: continue
			var radius:=lerpf(edge.width_start,edge.width_end,float(i)/(path.size()-1))*.5; var poly: Array=[]
			for j in 24: poly.append(Vector2(path[i].x,path[i].z)+Vector2(cos(TAU*j/24),sin(TAU*j/24))*radius)
			sources.append({"polygon":poly,"plane":Vector3(0,0,path[i].y),"kind":edge.kind,"edge":edge})
	if sources.size()>8192: return Data.fail("路面源轮廓超过 8192，请分区规划")
	var operations:=0
	for source in sources:
		# Flat-cut the cap at a linked deck boundary. Approaching roads keep their
		# own identity/material and never overlap the bridge's walking surface.
		for portal in portals:
			for at in 2:
				if portal.nodes[at] not in [source.edge.from,source.edge.to]: continue
				var endpoint: Vector3=Data.vec(portal.endpoints[at]); var opposite: Vector3=Data.vec(portal.endpoints[1-at]); var n:=Vector2(endpoint.x-opposite.x,endpoint.z-opposite.z).normalized()
				source.polygon=Poly.clip(source.polygon,n,-n.dot(Vector2(endpoint.x,endpoint.z)))
		if source.polygon.is_empty(): continue
		var bounds:=Rect2(source.polygon[0],Vector2.ZERO)
		for p in source.polygon: bounds=bounds.expand(p)
		if bounds.size.x*bounds.size.y>CELL*CELL*4096: return Data.fail("单段道路覆盖范围过大")
		for x in range(floori(bounds.position.x/CELL),floori(bounds.end.x/CELL)+1):
			for z in range(floori(bounds.position.y/CELL),floori(bounds.end.y/CELL)+1):
				var boundary:=Poly.rect([x*CELL,z*CELL,(x+1)*CELL,(z+1)*CELL]); var piece: Array=source.polygon
				for i in 4:
					var a: Vector2=boundary[i]; var d: Vector2=boundary[(i+1)%4]-a; var n:=Vector2(-d.y,d.x)
					piece=Poly.clip(piece,n,-n.dot(a))
				if piece.is_empty(): continue
				var plane: Vector3=source.plane
				var key:="road_%d_%d_%d"%[x,z,roundi(plane.z*1000)] if absf(plane.x)+absf(plane.y)<.0000001 else "ramp_%s_%d_%d"%[source.edge.id.sha256_text().left(16),x,z]; key=key.replace("-","m")
				if not chunks.has(key): chunks[key]={"x":x,"z":z,"plane":plane,"polygons":[],"masks":[],"kind":source.kind}
				var chunk: Dictionary=chunks[key]
				var fragments: Array=[piece]
				for mask in chunk.masks:
					var next: Array=[]
					for poly in fragments:
						operations+=1
						if operations>1000000: return Data.fail("路口裁切超过预算，请简化密集线段")
						if intersection(poly,mask).is_empty(): next.append(poly)
						else: next.append_array(Poly.subtract(poly,mask))
					fragments=next
					if fragments.is_empty(): break
				chunk.polygons.append_array(fragments)
				chunk.masks.append(piece)
				if chunk.polygons.size()>512 or chunks.size()>4096: return Data.fail("道路分块 / 裁切数量超过上限")
	# Elevated crossings need actual polygon overlap and sufficient slab underside clearance.
	var by_cell:={}
	for chunk in chunks.values():
		var key:=Vector2i(chunk.x,chunk.z)
		if not by_cell.has(key): by_cell[key]=[]
		for other in by_cell[key]:
			for a in chunk.polygons:
				for b in other.polygons:
					var overlap:=intersection(a,b)
					if overlap.is_empty(): continue
					var lo:=INF; var hi:=-INF
					for p in overlap:
						var gap:=Poly.height(chunk.plane,p)-Poly.height(other.plane,p); lo=minf(lo,gap); hi=maxf(hi,gap)
					if not (lo>=settings.clearance+settings.thickness or hi<=-settings.clearance-settings.thickness): return Data.fail("路面交叠处高度不一致或通行净空不足；请调整坡道接驳和交叉")
		by_cell[key].append(chunk)
	var records: Array=[]; var area:=0.0
	var keys:=chunks.keys(); keys.sort()
	for key in keys:
		var chunk: Dictionary=chunks[key]; var center:=Vector3((chunk.x+.5)*CELL,0,(chunk.z+.5)*CELL)
		center.y=Poly.height(chunk.plane,Vector2(center.x,center.z))+settings.lift-settings.thickness*.5
		var polygons: Array=[]
		for poly in chunk.polygons:
			var normalized:=normalized_patch(poly,center)
			if normalized.is_empty(): continue
			area+=Poly.area(poly)
			polygons.append(normalized)
		if polygons.is_empty(): continue
		var record:={"uuid":key,"kind":"box","surface_id":"road","position":Data.xyz(center),"rotation":[0,0,0],"size":[CELL,settings.thickness,CELL],"color":[.39,.36,.31],"road_source":key,"road_mesh":{"polygons":polygons,"uv_origin":Data.xyz(center)},"editor_name":"道路铺面 · %d,%d / %.2fm"%[chunk.x,chunk.z,center.y+settings.thickness*.5-settings.lift]}
		if absf(chunk.plane.x)+absf(chunk.plane.y)>.0000001: record.road_mesh.grade=[chunk.plane.x,chunk.plane.y]
		record.road_clearance=settings.clearance
		if not preload("res://scripts/world3d/road_surface.gd").valid(record): return Data.fail("道路裁切产生无效网格，已取消")
		records.append(record)
	return {"ok":true,"records":records,"area":area,"chunks":records.size(),"operations":operations}
