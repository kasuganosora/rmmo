extends RefCounted
const W=preload("res://scripts/world3d/waterway_data.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Scatter=preload("res://scripts/world3d/vegetation_scatter.gd")
const Surface=preload("res://scripts/world3d/channel_surface.gd")
var operations:=0
var failed:=false

static func triangles(poly: Array) -> Array:
	var points:=PackedVector2Array(poly)
	if Geometry2D.is_polygon_clockwise(points): points.reverse()
	var indices:=Geometry2D.triangulate_polygon(points); var out: Array=[]
	for i in range(0,indices.size(),3): out.append([points[indices[i]],points[indices[i+1]],points[indices[i+2]]])
	return out
static func simple(poly: Array) -> bool:
	return preload("res://scripts/world3d/planning_zones.gd").valid([{"id":"shape","purpose":"no_build","polygon":poly.map(func(p):return [p.x,p.y]),"min_y":0,"max_y":1}])
static func outline(points: Array, radius: float) -> Array:
	var left: Array=[]; var right: Array=[]
	for i in points.size():
		var before: Vector2=(points[maxi(i,1)]-points[maxi(i-1,0)]).normalized()
		var after: Vector2=(points[mini(i+1,points.size()-1)]-points[mini(i,points.size()-2)]).normalized()
		var a:=Vector2(-before.y,before.x); var b:=Vector2(-after.y,after.x); var m: Vector2=(a+b).normalized()
		var dot:=m.dot(a)
		if dot<.5: return [] # At most a 120 degree change; no unbounded acute miters.
		left.append(points[i]+m*radius/dot); right.append(points[i]-m*radius/dot)
	right.reverse(); left.append_array(right)
	return left
func subtract(subjects: Array,masks: Array) -> Array:
	var fragments:=subjects.duplicate()
	for mask in masks:
		var next: Array=[]
		for poly in fragments:
			operations+=1
			if operations>200000 or fragments.size()>4096: failed=true; return []
			if preload("res://scripts/world3d/road_plan.gd").intersection(poly,mask).is_empty(): next.append(poly)
			else: next.append_array(Poly.subtract(poly,mask))
		fragments=next
	return fragments
static func ground_polygons(r: Dictionary) -> Array:
	var shape:=Foot.record_shape(r); var p: Array=Array(shape.polygon); p.pop_back(); return triangles(p)
static func bridge_polygon(points: Array,bridge: Dictionary,half: float) -> Array:
	var a: Vector2=points[int(bridge.segment)]; var b: Vector2=points[int(bridge.segment)+1]; var tangent: Vector2=(b-a).normalized(); var normal:=Vector2(-tangent.y,tangent.x); var center: Vector2=a.lerp(b,bridge.t); var wide: float=bridge.width*.5
	return [center-tangent*wide-normal*(half+bridge.approach),center+tangent*wide-normal*(half+bridge.approach),center+tangent*wide+normal*(half+bridge.approach),center-tangent*wide+normal*(half+bridge.approach)]
static func clean_patch(raw: Array) -> Array:
	var points: Array=[]
	for p in raw:
		var v:=Vector2(p[0],p[1])
		if points.is_empty() or v.distance_squared_to(points.back())>1e-12: points.append(v)
	if points.size()>1 and points[0].distance_squared_to(points.back())<=1e-12: points.pop_back()
	if points.size()<3: return []
	var area:=0.0
	for i in range(1,points.size()-1): area+=(points[i]-points[0]).cross(points[i+1]-points[0])
	if area<=2e-9: return []
	return points.map(func(p):return [p.x,p.y])
static func slab(id: String,polys: Array,top: float,bottom: float,surface: String,color: Array) -> Dictionary:
	var bounds:=Rect2(polys[0][0],Vector2.ZERO)
	for poly in polys:
		for p in poly: bounds=bounds.expand(p)
	var center:=Vector3(bounds.get_center().x,(top+bottom)*.5,bounds.get_center().y); var size:=Vector3(bounds.size.x,top-bottom,bounds.size.y)
	var patches: Array=[]
	for poly in polys:
		var patch:=clean_patch(poly.map(func(p):return [(p.x-center.x)/size.x,(p.y-center.z)/size.z]))
		if not patch.is_empty(): patches.append(patch)
	return {"uuid":id,"kind":"box","surface_id":surface,"position":Data.xyz(center),"rotation":[0,0,0],"size":Data.xyz(size),"color":color,"channel_mesh":{"polygons":patches,"uv_origin":Data.xyz(center)}}
func chunked(prefix: String,polys: Array,top: float,bottom: float,surface: String,color: Array) -> Array:
	var cells:={}
	for poly in polys:
		var b:=Rect2(poly[0],Vector2.ZERO)
		for p in poly: b=b.expand(p)
		for x in range(floori(b.position.x/32),floori(b.end.x/32)+1):
			for z in range(floori(b.position.y/32),floori(b.end.y/32)+1):
				operations+=1
				if operations>200000: failed=true; return []
				var clipped:=preload("res://scripts/world3d/road_plan.gd").intersection(poly,Poly.rect([x*32,z*32,(x+1)*32,(z+1)*32]))
				if clipped.is_empty(): continue
				var key:="%d_%d"%[x,z]; key=key.replace("-","m")
				if not cells.has(key): cells[key]=[]
				cells[key].append(clipped)
	var out: Array=[]; var keys:=cells.keys(); keys.sort()
	for key in keys:
		# Keep painted top faces below the shared 128 face record limit.
		for i in range(0,cells[key].size(),24): out.append(slab(prefix+"_"+key+"_%d"%(i/24),cells[key].slice(i,i+24),top,bottom,surface,color))
	return out
func build(settings: Dictionary,sources: Array) -> Dictionary:
	operations=0; failed=false
	if not W.valid_settings(settings): return Data.fail("河道参数、地面列表或桥梁参数无效")
	var points: Array=settings.points.map(func(p):return Vector2(p[0],p[1])); var length_:=0.0
	for i in points.size()-1:
		var distance: float=points[i].distance_to(points[i+1])
		if distance<1: return Data.fail("相邻河道点至少相距 1 米")
		length_+=distance
	if length_>1000: return Data.fail("单条河道最长 1000 米，请分区域规划")
	var inner:=outline(points,settings.width*.5); var outer:=outline(points,settings.width*.5+settings.bank_width)
	if inner.is_empty() or outer.is_empty() or not simple(inner) or not simple(outer): return Data.fail("河道急弯、自交或两岸重叠，请加大转弯半径 / 缩小宽度")
	var water:=triangles(inner); var envelope:=triangles(outer); var banks:=subtract(envelope,water)
	var support: Array=[]
	for source in sources: support.append_array(ground_polygons(source))
	if not Scatter.inside(PackedVector2Array(outer),support): return Data.fail("河道及两岸必须完整落在指定平地内")
	var records: Array=[]; var roles:={}; var prefix: String="river_"+settings.id.sha256_text().left(16)
	var y: float=settings.bank_height; var water_y: float=y-settings.water_drop; var bed_y: float=water_y-settings.depth
	for source in sources:
		var remaining:=subtract(ground_polygons(source),envelope)
		if remaining.is_empty(): return Data.fail("单个地面被全部挖去，请使用范围更大的平地")
		if remaining.size()>512: return Data.fail("地面裁切超过 512 个补片，请先拆小地面")
		# Keep source transform/UUID/color, replacing only its geometry with the true remainder.
		var r: Dictionary=source.duplicate(true); var patches: Array=[]
		var inverse:=Transform3D(Basis.from_euler(Data.vec(r.rotation)*PI/180),Data.vec(r.position)).affine_inverse()
		for poly in remaining:
			var patch: Array=[]
			for p in poly:
				var local: Vector3=inverse*Vector3(p.x,y,p.y); patch.append([local.x/r.size[0],local.z/r.size[2]])
			patch=clean_patch(patch)
			if not patch.is_empty(): patches.append(patch)
		r.channel_mesh={"polygons":patches,"uv_origin":r.position.duplicate()}; records.append(r); roles[r.uuid]="ground"
	# Banks continue underneath bridge slabs, without coincident top faces/flicker.
	var abutments: Array=[]
	for bridge in settings.bridges:
		var masks:=triangles(bridge_polygon(points,bridge,settings.width*.5+settings.bank_width))
		for bank in banks:
			for mask in masks:
				var overlap:=preload("res://scripts/world3d/road_plan.gd").intersection(bank,mask)
				if not overlap.is_empty(): abutments.append(overlap)
		banks=subtract(banks,masks)
	for role in ["water","bed","bank","abutment"]:
		var is_bank: bool=role in ["bank","abutment"]
		var polys: Array=(banks if role=="bank" else abutments) if is_bank else water
		var top: float=(y+.025 if role=="bank" else y-.35) if is_bank else (water_y if role=="water" else bed_y)
		var bottom: float=bed_y-.2 if is_bank else top-.1
		var color: Array=[.47,.44,.37] if is_bank else ([.09,.27,.29] if role=="water" else [.28,.25,.18])
		var pieces:=chunked(prefix+"_"+role,polys,top,bottom,"water" if role=="water" else ("river_bank" if is_bank else "river_bed"),color)
		for r in pieces:
			if role=="water": r.channel_clearance=settings.water_drop+3
			r.collision="none" if role=="water" else "walk"; r.editor_name=settings.name+" · "+("河岸" if is_bank else ("水面" if role=="water" else "河床")); roles[r.uuid]="bank" if is_bank else role; records.append(r)
	# Close the depth below the original (potentially thin) ground at both ends.
	for end in [0,points.size()-1]:
		var next: int=1 if end==0 else end-1; var direction: Vector2=(points[next]-points[end]).normalized(); var n: Vector2=Vector2(-direction.y,direction.x)*settings.width*.5
		var c: Vector2=points[end]; var cap:=triangles([c-n,c+direction*.15-n,c+direction*.15+n,c+n])
		var r:=slab(prefix+"_end_%d"%end,cap,y,bed_y-.2,"river_bank",[.47,.44,.37]); r.editor_name=settings.name+" · 端部挡土墙"; records.append(r); roles[r.uuid]="bank"
	var crossings: Array=[]
	for bridge in settings.bridges:
		var a: Vector2=points[int(bridge.segment)]; var b: Vector2=points[int(bridge.segment)+1]; var tangent: Vector2=(b-a).normalized(); var normal:=Vector2(-tangent.y,tangent.x); var center: Vector2=a.lerp(b,bridge.t)
		var half: float=settings.width*.5+settings.bank_width; var wide: float=bridge.width*.5
		if minf(center.distance_to(a),center.distance_to(b))<wide+settings.width*.5+settings.bank_width: return Data.fail("桥梁太靠近河道端点或转角，请移到足够长的直线段中部")
		var deck:=bridge_polygon(points,bridge,half)
		if not Scatter.inside(PackedVector2Array(deck),support): return Data.fail("桥头必须完整落在指定平地内")
		var deck_shape:=shape(deck,y-.4,y+3)
		for other in crossings:
			if Foot.overlaps(deck_shape,other.shape): return Data.fail("桥梁或桥头彼此重叠")
		# Landings must be outside the entire river, not just the chosen segment.
		for side in [-1,1]:
			var c: Vector2=center+normal*side*(half+bridge.approach*.5)
			var end: Array=[c-tangent*wide-normal*bridge.approach*.49,c+tangent*wide-normal*bridge.approach*.49,c+tangent*wide+normal*bridge.approach*.49,c-tangent*wide+normal*bridge.approach*.49]
			if subtract([end],envelope).reduce(func(sum,p):return sum+Poly.area(p),0.0)<Poly.area(end)-.001: return Data.fail("桥头落入其他河段，请移动桥梁")
		var base_id: String=prefix+"_bridge_"+bridge.id.sha256_text().left(10)
		var r:=slab(base_id,triangles(deck),y+.025,y-.35,"bridge_deck",[.43,.40,.34]); r.channel_clearance=3.0; r.editor_name=settings.name+" · 桥面 / 桥头"; records.append(r); roles[r.uuid]="bridge"
		for side in [-1,1]:
			var c: Vector2=center+tangent*side*(wide-.15)
			var railing: Array=[c-tangent*.15-normal*half,c+tangent*.15-normal*half,c+tangent*.15+normal*half,c-tangent*.15+normal*half]
			var rail:=slab(base_id+"_rail_"+str(side).replace("-","m"),triangles(railing),y+.025+bridge.rail_height,y+.025,"block",[.48,.45,.39]); rail.collision="block"; rail.editor_name=settings.name+" · 桥栏杆"; records.append(rail); roles[rail.uuid]="rail"
		crossings.append({"id":bridge.id,"shape":deck_shape,"polygon":deck.map(func(p):return [p.x,p.y]),"endpoints":[Data.xyz(Vector3((center-normal*(half+bridge.approach)).x,y,(center-normal*(half+bridge.approach)).y)),Data.xyz(Vector3((center+normal*(half+bridge.approach)).x,y,(center+normal*(half+bridge.approach)).y))],"width":bridge.width})
	if failed or records.size()>2048: return Data.fail("河道几何超过计算或构件预算，请缩小范围")
	for r in records:
		if not Surface.valid(r): return Data.fail("河道裁切产生退化网格，请调整路径："+str(r.uuid))
	return {"ok":true,"records":records,"roles":roles,"outer":outer,"water":water,"envelope":envelope,"crossings":crossings,"length":length_,"area":Poly.area(inner),"operations":operations}
static func shape(poly: Array,low: float,high: float) -> Dictionary:
	var points: Array[Vector3]=[]
	for p in poly: points.append(Vector3(p.x,low,p.y)); points.append(Vector3(p.x,high,p.y))
	return Foot.from_points(points)
