extends RefCounted
## Analyze the exact native volume mesh, retaining multiple surfaces at one X/Z.
const V=preload("res://scripts/world3d/terrain_volume.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const MAX_TRIANGLES=32768
const MAX_LINES=16384
static func fail(message:String)->Dictionary:return {"ok":false,"code":"terrain_analysis_unsupported","error":message}
static func clip_y(points:Array[Vector3],height:float,above:bool)->Array[Vector3]:
	var result:Array[Vector3]=[]
	for i in points.size():
		var a:Vector3=points[i];var b:Vector3=points[(i+1)%points.size()]
		var inside_a:bool=a.y>=height if above else a.y<=height
		var inside_b:bool=b.y>=height if above else b.y<=height
		if inside_a:result.append(a)
		if inside_a!=inside_b:result.append(a.lerp(b,(height-a.y)/(b.y-a.y)))
	return result
static func build(record:Dictionary,args:Dictionary)->Dictionary:
	if not V.valid(record):return fail("体积地形配方无效")
	if not args.has("surface") or not args.has("height_min") or not args.has("height_max"):return fail("体积分析须明确 surface 与世界标高 height_min／height_max，避免混淆洞顶与地面")
	if args.height_min>=args.height_max:return fail("分析标高下限必须小于上限")
	if args.get("seams",false):return fail("体积表面没有高度场边界高差语义，请关闭 seams")
	var arrays:=V.arrays(record)
	if arrays.is_empty():return fail("体积地形没有实际三角面")
	var pose:=Transform3D(Basis.from_euler(City.vec(record.rotation)*PI/180),City.vec(record.position))
	var interval:float=args.get("interval",1.);var threshold:float=args.get("slope_threshold",.15)
	var slopes:Array=[];var contours:Array=[];var seen:Dictionary={};var counts:Dictionary={"upward":0,"downward":0,"walls":0};var triangles:=0;var source_index:=0;var max_grade:=0.;var max_angle:=0.;var vertical:=0
	for surface:Array in arrays:
		var vertices:PackedVector3Array=surface[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=surface[Mesh.ARRAY_INDEX]
		for at in range(0,indices.size(),3):
			var points:Array[Vector3]=[pose*vertices[indices[at]],pose*vertices[indices[at+1]],pose*vertices[indices[at+2]]]
			var index:=source_index;source_index+=1
			# Godot's native volume builder emits clockwise faces, outward normal.
			var normal:Vector3=(points[2]-points[0]).cross(points[1]-points[0])
			if normal.length_squared()<.0000000001:continue
			normal=normal.normalized()
			var kind:="upward" if normal.y>.05 else ("downward" if normal.y<-.05 else "walls")
			if args.surface!="all" and args.surface!=kind:continue
			points=clip_y(clip_y(points,args.height_min,true),args.height_max,false)
			if points.size()<3:continue
			var horizontal:=Vector2(normal.x,normal.z).length();var is_vertical:=absf(normal.y)<.000001
			var grade:Variant=null if is_vertical else horizontal/absf(normal.y)
			var angle:=rad_to_deg(atan2(horizontal,absf(normal.y)))
			for j in range(1,points.size()-1):
				var tri:Array[Vector3]=[points[0],points[j],points[j+1]]
				if (tri[1]-tri[0]).cross(tri[2]-tri[0]).length_squared()<.0000000001:continue
				triangles+=1;counts[kind]+=1
				if triangles>MAX_TRIANGLES:return fail("分析超过 32768 三角面，请缩小标高范围或选择表面方向")
				if is_vertical:vertical+=1
				else:max_grade=maxf(max_grade,float(grade))
				max_angle=maxf(max_angle,angle)
				if args.get("slopes",true):slopes.append({"points":tri.map(func(p):return City.xyz(p)),"normal":City.xyz(normal),"grade":grade,"angle_degrees":angle,"vertical":is_vertical,"steep":kind!="upward" or float(grade)>threshold,"surface":kind,"source_triangle":index})
			if not args.get("contours",true):continue
			var low:=INF;var high:=-INF
			for p:Vector3 in points:low=minf(low,p.y);high=maxf(high,p.y)
			if high-low<.000001:continue
			var first:=ceili(low/interval);var end:=floori(high/interval)
			if end-first>MAX_LINES:return fail("单个表面等高线超预算，请增大等高距")
			for level in range(first,end+1):
				var height:float=level*interval;var hits:Array[Vector3]=[]
				for i in points.size():
					var a:Vector3=points[i];var b:Vector3=points[(i+1)%points.size()]
					if absf(a.y-b.y)<.000001:continue
					var fraction:float=(height-a.y)/(b.y-a.y)
					if fraction<0 or fraction>1:continue
					var hit:=a.lerp(b,fraction)
					if not hits.any(func(p):return p.distance_squared_to(hit)<.00000001):hits.append(hit)
				if hits.size()!=2 or hits[0].distance_squared_to(hits[1])<.00000001:continue
				var key_points:Array=[str(hits[0].snapped(Vector3.ONE*.0001)),str(hits[1].snapped(Vector3.ONE*.0001))];key_points.sort();var key:=str(key_points)
				if seen.has(key):continue
				if contours.size()>=MAX_LINES:return fail("等高线超过 16384 段预算，请缩小范围或增大等高距")
				seen[key]=true;contours.append({"height":height,"points":[City.xyz(hits[0]),City.xyz(hits[1])],"normal":City.xyz(normal),"surface":kind,"source_triangle":index})
	return {"ok":true,"id":record.uuid,"interval":interval,"slope_threshold":threshold,"contours":contours,"slopes":slopes,"seams":[],"max_grade":null if vertical>0 else max_grade,"max_angle_degrees":max_angle,"vertical_triangles":vertical,"selected_triangles":triangles,"surface_counts":counts,"surface":args.surface,"height_range":[args.height_min,args.height_max],"max_boundary_step":0.,"holes":null,"source":"native_volume_triangles","scope":"world height band clipped against actual triangles; upward normal.y > 0.05, downward < -0.05, otherwise walls; no heightfield seams or walkability certificate"}
