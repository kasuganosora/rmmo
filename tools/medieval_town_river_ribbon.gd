extends RefCounted
## C2 centreline x(z), with banks offset along its actual unit normal.
## This is the reference town's authoring recipe, not a new editor operation.
static func build(points: Array,width: float) -> Dictionary:
	if points.size()<3 or width<=0: return {"ok":false,"error":"Invalid river centreline"}
	var n:=points.size(); var diagonal: Array=[]; var upper: Array=[]; var rhs: Array=[]; var second: Array=[]
	for i in n: diagonal.append(1.); upper.append(0.); rhs.append(0.); second.append(0.)
	for i in range(1,n-1):
		var a: float=points[i].y-points[i-1].y; var b: float=points[i+1].y-points[i].y
		if minf(a,b)<=0: return {"ok":false,"error":"River anchors must increase in Z"}
		diagonal[i]=2.*(a+b); upper[i]=b
		rhs[i]=6.*((points[i+1].x-points[i].x)/b-(points[i].x-points[i-1].x)/a)
		var multiplier: float=a/diagonal[i-1]
		diagonal[i]-=multiplier*upper[i-1]; rhs[i]-=multiplier*rhs[i-1]
	for i in range(n-2,0,-1): second[i]=(rhs[i]-upper[i]*second[i+1])/diagonal[i]
	var left: Array=[]; var right: Array=[]; var centers: Array=[]; var normals: Array=[]
	var section:=0; var max_curvature:=0.
	for step in ceili(points[-1].y-points[0].y)+1:
		var z: float=minf(points[0].y+step,points[-1].y)
		while section<n-2 and z>points[section+1].y: section+=1
		var p: Vector2=points[section]; var q: Vector2=points[section+1]; var h:=q.y-p.y
		var a: float=(q.y-z)/h; var b: float=(z-p.y)/h
		var u: float=second[section]; var v: float=second[section+1]
		var x: float=a*p.x+b*q.x+((a*a*a-a)*u+(b*b*b-b)*v)*h*h/6.
		var dx: float=(q.x-p.x)/h+((-3.*a*a+1.)*u+(3.*b*b-1.)*v)*h/6.
		var curvature: float=absf(a*u+b*v)/pow(1.+dx*dx,1.5)
		max_curvature=maxf(max_curvature,curvature)
		var center:=Vector2(x,z); var normal:=Vector2(1.,-dx).normalized()
		centers.append(center); normals.append(normal); left.append(center-normal*width*.5); right.append(center+normal*width*.5)
	if max_curvature*width*.5>=.5: return {"ok":false,"error":"River bend radius is too small for its width"}
	for bank in [left,right]:
		for i in range(1,bank.size()):
			if bank[i].y<=bank[i-1].y: return {"ok":false,"error":"Offset bank folds back"}
	return {"ok":true,"left":left,"right":right,"centers":centers,"normals":normals,"width":width,"minimum_radius":1./maxf(max_curvature,.000001)}

static func bank_x(points: Array,z: float) -> float:
	var lo:=0; var hi:=points.size()-1
	while hi-lo>1:
		var mid: int=(lo+hi)/2
		if points[mid].y<=z: lo=mid
		else: hi=mid
	return lerpf(points[lo].x,points[hi].x,clampf((z-points[lo].y)/(points[hi].y-points[lo].y),0.,1.))
