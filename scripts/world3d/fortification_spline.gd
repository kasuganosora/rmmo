extends RefCounted
const RouteCurve=preload("res://scripts/world3d/spline_route.gd")
static func resolve(settings:Dictionary)->Dictionary:
	if settings.get("shape","path")!="spline":return {"ok":true,"settings":settings}
	var sampled:=RouteCurve.sample(settings.points,maxf(3.,settings.thickness*1.5),settings.closed,settings.get("curve_tension",.5))
	if not sampled.ok:return sampled
	var path:Array=sampled.points.duplicate(true)
	if settings.closed:path.append(path[0])
	var lengths:Array=[0.]
	for i in path.size()-1:lengths.append(lengths[-1]+Vector2(path[i][0],path[i][1]).distance_to(Vector2(path[i+1][0],path[i+1][1])))
	var openings:Array=[]
	for gate:Dictionary in settings.gates:
		var from:int=sampled.anchors[int(gate.segment)];var to:int=sampled.anchors[(int(gate.segment)+1)%sampled.anchors.size()]
		if to<=from:to=path.size()-1
		var at:float=lerpf(lengths[from],lengths[to],gate.t);var margin:float=gate.width*.5+settings.thickness*2.
		if at-margin<0 or at+margin>lengths[-1]:return {"ok":false,"error":"曲线城门距路径端点太近"}
		for other:Dictionary in openings:
			if absf(at-other.at)<margin+other.margin:return {"ok":false,"error":"曲线城门的直线接驳区重叠"}
		openings.append({"gate":gate,"at":at,"margin":margin})
	var stations:Array=[]
	for distance:float in lengths:
		if not openings.any(func(o):return distance>o.at-o.margin and distance<o.at+o.margin):stations.append(distance)
	for opening:Dictionary in openings:stations.append(opening.at-opening.margin);stations.append(opening.at+opening.margin)
	stations.sort();var points:Array=[]
	for station:float in stations:points.append(point_at(path,lengths,station))
	var next:=settings.duplicate(true);next.shape="path";next.points=points
	if settings.closed:next.points.pop_back()
	var anchors:Array=settings.get("tower_indices",range(settings.points.size()))
	next.tower_indices=[]
	for index:int in anchors:
		var distance:float=lengths[sampled.anchors[index]];var closest:=0
		for i in stations.size():
			if absf(stations[i]-distance)<absf(stations[closest]-distance):closest=i
		closest=mini(closest,next.points.size()-1)
		if not next.tower_indices.has(closest):next.tower_indices.append(closest)
	next.gates=[]
	for opening:Dictionary in openings:
		var gate:Dictionary=opening.gate.duplicate(true);gate.segment=stations.find(opening.at-opening.margin);gate.t=.5;next.gates.append(gate)
	return {"ok":true,"settings":next}
static func point_at(path:Array,lengths:Array,station:float)->Array:
	for i in lengths.size()-1:
		if station<=lengths[i+1]+.000001:
			var p:=Vector2(path[i][0],path[i][1]).lerp(Vector2(path[i+1][0],path[i+1][1]),clampf((station-lengths[i])/(lengths[i+1]-lengths[i]),0,1))
			return [p.x,p.y]
	return path[-1].duplicate()
