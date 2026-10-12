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
	var wanted:Array=[]
	for raw:Array in source:
		var polygon:Array=[]
		for p:Array in raw:polygon.append(Vector2(record.position[0]+p[0]*record.size[0],record.position[2]+p[1]*record.size[2]))
		wanted.append(polygon);area+=absf(Poly.area(polygon))
	for terrain:Dictionary in terrains:
		if not terrain.has("terrain_mesh") or absf(terrain.rotation[0])+absf(terrain.rotation[2])>.0001:continue
		var pose:=T.transform(terrain);var used:=false
		for z in int(terrain.terrain_mesh.rows):
			for x in int(terrain.terrain_mesh.columns):
				if not T.solid(terrain.terrain_mesh,x,z):continue
				var cell:=T.cell(terrain,x,z)
				for triangle:Array in [[cell[0],cell[1],cell[2]],[cell[0],cell[2],cell[3]]]:
					var corners:Array=triangle.map(func(p):return pose*p)
					var boundary:Array=corners.map(func(p):return Vector2(p.x,p.z))
					var plane:=Plane(corners[0],corners[1],corners[2])
					for polygon:Array in wanted:
						var overlap:=P.intersection(polygon,boundary)
						if overlap.size()<3 or absf(Poly.area(overlap))<.000001:continue
						if absf(plane.normal.y)<.0001 or Vector2(plane.normal.x,plane.normal.z).length()/absf(plane.normal.y)>max_grade+.0001:return T.fail("地形坡度超过通行限制，请先平缓地形或改走其他路径")
						var raw:Array=[];var ys:Array=[]
						for p:Vector2 in overlap:
							raw.append([(p.x-record.position[0])/record.size[0],(p.y-record.position[2])/record.size[2]])
							ys.append((plane.d-plane.normal.x*p.x-plane.normal.z*p.y)/plane.normal.y+offset-record.position[1])
						output.append(raw);heights.append(ys);used=true;covered+=absf(Poly.area(overlap))
						if output.size()>512:return T.fail("单块贴地路面超过 512 片，请缩小路段或提高地形格距")
		if used:ids.append(terrain.uuid)
	if absf(covered-area)>maxf(.005,area*.0001):return T.fail("路面范围含地形洞口、缺口或重叠地块，无法完整贴合")
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
