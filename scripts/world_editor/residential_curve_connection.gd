extends RefCounted
## Private cubic projection. Convex-hull bounds certify the distance error;
## point evaluations tighten the upper bound; only bounds can end the search.
const Data=preload("res://scripts/world3d/city_layout.gd")
const Split=preload("res://scripts/world3d/road_intersections.gd")
const DISTANCE_ERROR:=.0001
const MAX_VISITS:=4096

static func failure(code:String,message:String)->Dictionary:
	return {"ok":false,"code":code,"stage":"road_connection","error":message}

static func mix(a:Array,b:Array)->Array:
	return [(float(a[0])+float(b[0]))*.5,(float(a[1])+float(b[1]))*.5]

static func halves(points:Array)->Array:
	var a:=mix(points[0],points[1]);var b:=mix(points[1],points[2]);var c:=mix(points[2],points[3])
	var d:=mix(a,b);var e:=mix(b,c);var f:=mix(d,e)
	return [[points[0],a,d,f],[f,e,c,points[3]]]

static func distance(point:Array)->float:
	return sqrt(float(point[0])*float(point[0])+float(point[1])*float(point[1]))

static func lerp3(a:Array,b:Array,t:float)->Array:
	return [float(a[0])+(float(b[0])-float(a[0]))*t,float(a[1])+(float(b[1])-float(a[1]))*t,float(a[2])+(float(b[2])-float(a[2]))*t]

static func subcurves(edge:Dictionary,nodes:Dictionary,t:float)->Dictionary:
	# Preserve double authoring coordinates. Native Vector3 is float32 and
	# must not round the new graph's join or handles at distant coordinates.
	var a:Array=nodes[edge.from].position;var b:Array=edge.controls[0];var c:Array=edge.controls[1];var d:Array=nodes[edge.to].position
	var ab:=lerp3(a,b,t);var bc:=lerp3(b,c,t);var cd:=lerp3(c,d,t)
	var abc:=lerp3(ab,bc,t);var bcd:=lerp3(bc,cd,t);var at:=lerp3(abc,bcd,t)
	return {"position":at,"controls":[[ab,abc],[bcd,cd]]}

static func lower_bound(points:Array)->float:
	var min_x:=INF;var max_x:=-INF;var min_z:=INF;var max_z:=-INF
	for point:Array in points:
		min_x=minf(min_x,point[0]);max_x=maxf(max_x,point[0]);min_z=minf(min_z,point[1]);max_z=maxf(max_z,point[1])
	var x:=clampf(0.,min_x,max_x);var z:=clampf(0.,min_z,max_z)
	# Roundoff guard in local double scalar arithmetic, not float32 Vector2.
	return maxf(0.,sqrt(x*x+z*z)-1e-8)

static func nearest(edge:Dictionary,nodes:Dictionary,point:Vector3,budget:int=MAX_VISITS)->Dictionary:
	var source:Array=[nodes[edge.from].position,edge.controls[0],edge.controls[1],nodes[edge.to].position]
	var local:Array=[]
	for p:Array in source:local.append([float(p[0])-float(point.x),float(p[2])-float(point.z)])
	var best_t:=0.;var best:=distance(local[0])
	var last:=distance(local[3])
	if last<best:best=last;best_t=1.
	var pending:Array=[{"points":local,"lo":0.,"hi":1.,"bound":lower_bound(local)}]
	var visits:=0
	while not pending.is_empty():
		# Best-bound first, stable lower-parameter tie break. An exhausted budget
		# is a refusal, never a claim that the last sampled point was sufficient.
		var selected:=0
		for i in range(1,pending.size()):
			if pending[i].bound<pending[selected].bound or (pending[i].bound==pending[selected].bound and pending[i].lo<pending[selected].lo):selected=i
		var cell:Dictionary=pending[selected];pending.remove_at(selected)
		if cell.bound>=best-DISTANCE_ERROR:continue
		if visits>=budget:return failure("curve_projection_budget","曲线接驳点搜索超过有界预算，请分段道路或调整住宅位置")
		visits+=1
		var parts:=halves(cell.points);var mid:float=(cell.lo+cell.hi)*.5;var candidate:=distance(parts[0][3])
		if candidate<best or (candidate==best and mid<best_t):best=candidate;best_t=mid
		for i in 2:
			var bound:=lower_bound(parts[i])
			if bound<best-DISTANCE_ERROR:pending.append({"points":parts[i],"lo":cell.lo if i==0 else mid,"hi":mid if i==0 else cell.hi,"bound":bound})
	var position:Array=subcurves(edge,nodes,best_t).position;var at:=Data.vec(position);var tangent:=Split.derivative(edge,nodes,best_t)
	if Vector2(tangent.x,tangent.z).length()<.0001:return failure("curve_tangent_degenerate","接驳位置的曲线切向退化，请调整道路控制点")
	return {"ok":true,"t":best_t,"point":at,"position":position,"tangent":tangent,"distance":best,"distance_error_bound_m":DISTANCE_ERROR,"visits":visits}

static func controls(edge:Dictionary,nodes:Dictionary,t:float)->Array:
	return subcurves(edge,nodes,t).controls
