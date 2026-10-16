extends RefCounted
## Monotone longitudinal levels on the exact shared Hermite sampling parameters.
const Spline=preload("res://scripts/world3d/spline_route.gd")

static func validate(args:Dictionary)->String:
	if not args.has("water_levels"):return ""
	var levels:Variant=args.water_levels
	if not levels is Array or levels.size()!=args.get("points",[]).size() or levels.size()<2:return "逐点水位必须与中心线控制点等长"
	var previous:=INF
	for value:Variant in levels:
		if not (value is float or value is int) or not is_finite(float(value)) or float(value)<-1000 or float(value)>1000:return "逐点水位必须是有限数值（-1000～1000米）"
		if float(value)>previous:return "水位必须沿控制点顺序下降或等高，不能逆坡升高"
		previous=float(value)
	if args.get("natural_materials",true):return "纵向水位暂不支持单一水位的自然湿岸材质；请关闭自然材质并使用地形区域材质"
	return ""

static func prepare(args:Dictionary)->Dictionary:
	var error:=validate(args)
	if not error.is_empty():return {"ok":false,"error":error}
	var curve:=Spline.sample(args.points,2.,false,.5 if args.get("curved",true) else 0.)
	if not curve.ok:return curve
	var levels:Array=[]
	for span:Dictionary in curve.spans:
		levels.append(lerpf(float(args.water_levels[span.segment]),float(args.water_levels[span.segment+1]),span.t) if args.has("water_levels") else float(args.water_level))
	return {"ok":true,"path":curve.points,"levels":levels,"spans":curve.spans,"anchors":curve.anchors,"profile":args.has("water_levels")}

static func sample(point:Vector2,path:Array,levels:Array)->Dictionary:
	var best:=INF;var best_segment:=0;var best_t:=0.
	for i in path.size()-1:
		var a:=Vector2(path[i][0],path[i][1]);var b:=Vector2(path[i+1][0],path[i+1][1]);var delta:=b-a
		var t:=clampf((point-a).dot(delta)/maxf(.000001,delta.length_squared()),0,1)
		var distance:=point.distance_to(a+delta*t)
		if distance<best:
			best=distance;best_segment=i;best_t=t
	return {"distance":best,"level":lerpf(float(levels[best_segment]),float(levels[best_segment+1]),best_t),"segment":best_segment,"t":best_t}

static func triangle_level(point:Vector2,triangle:Array,levels:Array)->float:
	var a:Vector2=triangle[0];var b:Vector2=triangle[1];var c:Vector2=triangle[2]
	var area:float=(b-a).cross(c-a)
	var wb:float=(point-a).cross(c-a)/area
	var wc:float=(b-a).cross(point-a)/area
	return float(levels[0])*(1.-wb-wc)+float(levels[1])*wb+float(levels[2])*wc
