extends RefCounted
## Clip authored convex footprints to terrain triangles so a curved heightfield
## never pokes through a road whose original vertices were metres apart.
const T=preload("res://scripts/world3d/terrain_surface.gd")
const R=preload("res://scripts/world3d/road_surface.gd")
const P=preload("res://scripts/world3d/road_plan.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
static func fit(record:Dictionary,terrains:Array,offset:float=.025,max_grade:float=.15)->Dictionary:
	if absf(record.rotation[0])+absf(record.rotation[1])+absf(record.rotation[2])>.0001:return T.fail("贴地生成只支持世界轴路面，请先烘焙旋转")
	var next:=record.duplicate(true);var field:="road_mesh" if record.has("road_mesh") else "channel_mesh"
	var source:Array=record.get("terrain_follow",{}).get("polygons",record[field].polygons).duplicate(true)
	var output:Array=[];var heights:Array=[];var ids:Array=[];var covered:=0.;var area:=0.
	var wanted:Array=[];var wanted_bounds:Array[Rect2]=[];var wanted_extent:=Rect2()
	for raw:Array in source:
		var polygon:Array=[]
		for p:Array in raw:polygon.append(Vector2(record.position[0]+p[0]*record.size[0],record.position[2]+p[1]*record.size[2]))
		wanted.append(polygon);area+=absf(Poly.area(polygon))
		var bounds:=Rect2(polygon[0],Vector2.ZERO)
		for point:Vector2 in polygon:bounds=bounds.expand(point)
		# Broad-phase bounds only: preserve exact clipping and coverage tolerances.
		bounds=bounds.grow(.001)
		wanted_bounds.append(bounds)
		wanted_extent=bounds if wanted_bounds.size()==1 else wanted_extent.merge(bounds)
	for terrain:Dictionary in terrains:
		if not terrain.has("terrain_mesh") or absf(terrain.rotation[0])+absf(terrain.rotation[2])>.0001:continue
		var pose:=T.transform(terrain);var used:=false
		var horizontal:bool=float(terrain.rotation[0])==0.0 and float(terrain.rotation[2])==0.0
		var columns:int=terrain.terrain_mesh.columns;var rows:int=terrain.terrain_mesh.rows
		var corner:Vector3=pose*T.point(terrain,0,0)
		var terrain_bounds:=Rect2(Vector2(corner.x,corner.z),Vector2.ZERO)
		for grid:Vector2i in [Vector2i(columns,0),Vector2i(columns,rows),Vector2i(0,rows)]:
			corner=pose*T.point(terrain,grid.x,grid.y)
			terrain_bounds=terrain_bounds.expand(Vector2(corner.x,corner.z))
		# Accepted near-zero X/Z tilts can shift high interior vertices beyond
		# corner bounds. Keep their triangle filtering but skip this coarse test.
		if wanted.is_empty() or (horizontal and not terrain_bounds.intersects(wanted_extent,true)):continue
		var terrain_wanted:Array[int]=[]
		for index in wanted.size():
			if not horizontal or terrain_bounds.intersects(wanted_bounds[index],true):terrain_wanted.append(index)
		if terrain_wanted.is_empty():continue
		for z in int(terrain.terrain_mesh.rows):
			for x in int(terrain.terrain_mesh.columns):
				if not T.solid(terrain.terrain_mesh,x,z):continue
				var cell:=T.cell(terrain,x,z)
				var triangles:Array=[[cell[0],cell[1],cell[2]],[cell[0],cell[2],cell[3]]]
				for triangle_index in triangles.size():
					var triangle:Array=triangles[triangle_index]
					var corners:Array=triangle.map(func(p):return pose*p)
					var boundary:Array=corners.map(func(p):return Vector2(p.x,p.z))
					var triangle_bounds:=Rect2(boundary[0],Vector2.ZERO)
					triangle_bounds=triangle_bounds.expand(boundary[1]).expand(boundary[2])
					if not triangle_bounds.intersects(wanted_extent,true):continue
					var plane:=Plane(corners[0],corners[1],corners[2])
					for index:int in terrain_wanted:
						if not triangle_bounds.intersects(wanted_bounds[index],true):continue
						var polygon:Array=wanted[index]
						var overlap:=P.intersection(polygon,boundary)
						if overlap.size()<3 or absf(Poly.area(overlap))<.000001:continue
						var grade:float=Vector2(plane.normal.x,plane.normal.z).length()/absf(plane.normal.y) if absf(plane.normal.y)>=.0001 else INF
						if absf(plane.normal.y)<.0001 or grade>max_grade+.0001:
							var at:=Vector2.ZERO
							for p:Vector2 in overlap:at+=p
							at/=overlap.size()
							var y:float=(plane.d-plane.normal.x*at.x-plane.normal.z*at.y)/plane.normal.y if is_finite(grade) else corners[0].y
							var description:String="%.3f%%"%(grade*100.) if is_finite(grade) else "近垂直"
							return {"ok":false,"code":"terrain_projection_grade_limit","error":"地形 %s 在 X %.3f、Z %.3f 处坡度 %s，超过 %.3f%% 通行限制（网格 %d,%d，三角 %d）；请局部平缓地形或改走其他路径"%[terrain.uuid,at.x,at.y,description,max_grade*100.,x,z,triangle_index],"record_id":record.get("uuid",""),"road_source":record.get("road_source",""),"terrain_id":terrain.uuid,"position":[at.x,y,at.y],"cell":[x,z],"triangle_index":triangle_index,"triangle_world":corners.map(func(p:Vector3):return [p.x,p.y,p.z]),"grade":grade if is_finite(grade) else null,"max_grade":max_grade}
						var raw:Array=[];var ys:Array=[]
						for p:Vector2 in overlap:
							raw.append([(p.x-record.position[0])/record.size[0],(p.y-record.position[2])/record.size[2]])
							ys.append((plane.d-plane.normal.x*p.x-plane.normal.z*p.y)/plane.normal.y+offset-record.position[1])
						output.append(raw);heights.append(ys);used=true;covered+=absf(Poly.area(overlap))
						if output.size()>512:return {"ok":false,"error":"单块贴地路面超过 512 片，请缩小路段或提高地形格距","code":"terrain_projection_piece_limit"}
		if used:ids.append(terrain.uuid)
	if absf(covered-area)>maxf(.005,area*.0001):return T.fail("路面范围含地形洞口、缺口或重叠地块，无法完整贴合（覆盖 %.6f / 目标 %.6f 平方米，中心 %.3f, %.3f）"%[covered,area,record.position[0],record.position[2]])
	next[field].polygons=output;next[field].elevations=heights;next[field].erase("grade")
	# Existing kerbs are regenerated against the fitted surface below.
	var source_kerbs:Array=record.get("terrain_follow",{}).get("kerbs",record[field].get("kerbs",[])).duplicate(true)
	if not source_kerbs.is_empty():next[field].kerbs=source_kerbs.duplicate(true)
	for kerb:Dictionary in next[field].get("kerbs",[]):
		for side:String in ["a","b"]:
			for point:Array in kerb[side]:
				var world:=Vector3(point[0]+record.position[0],0,point[2]+record.position[2]);var y:=-INF
				for terrain:Dictionary in terrains:
					var pose:=T.transform(terrain);var local:Vector3=pose.affine_inverse()*world;var sample:=T.sample(terrain,local)
					if is_finite(sample):y=maxf(y,(pose*Vector3(local.x,sample,local.z)).y)
				if not is_finite(y):return T.fail("路缘缺少地形承托")
				point[1]=y+offset-record.position[1]+(point[1]-record.size[1]*.5)
	next.terrain_follow={"version":1,"terrain_ids":ids,"polygons":source,"offset":offset,"max_grade":max_grade}
	if not source_kerbs.is_empty():next.terrain_follow.kerbs=source_kerbs
	return {"ok":true,"record":next}
