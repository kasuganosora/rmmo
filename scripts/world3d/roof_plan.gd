extends RefCounted
## Deterministic planar envelope for the editor's rectangular building modules.
## This is our own bounded solver, not an implementation of a proprietary solver
## or a general straight-skeleton algorithm. All downstream geometry uses faces.
const EPS := .00001
const MAX_FACES := 512

static func rect(r: Array) -> Array:
	return [Vector2(r[0],r[1]),Vector2(r[2],r[1]),Vector2(r[2],r[3]),Vector2(r[0],r[3])]

static func area(poly: Array) -> float:
	var value:=0.0
	for i in poly.size(): value+=poly[i].cross(poly[(i+1)%poly.size()])
	return absf(value)*.5

static func clean(poly: Array) -> Array:
	var out: Array=[]
	for p in poly:
		if out.is_empty() or p.distance_squared_to(out.back())>EPS*EPS: out.append(p)
	if out.size()>1 and out[0].distance_squared_to(out.back())<EPS*EPS: out.pop_back()
	return out if out.size()>=3 and area(out)>EPS else []

## Keep n.dot(p)+c >= 0. No epsilon expansion: shared edges must coincide.
static func clip(poly: Array, n: Vector2, c: float) -> Array:
	var out: Array=[]
	for i in poly.size():
		var a: Vector2=poly[i]; var b: Vector2=poly[(i+1)%poly.size()]
		var da:=n.dot(a)+c; var db:=n.dot(b)+c
		if da>=0: out.append(a)
		if (da>=0)!=(db>=0): out.append(a.lerp(b,da/(da-db)))
	return clean(out)

## Subtract a CCW convex mask into disjoint convex fragments (no hole fans).
static func subtract(poly: Array, mask: Array) -> Array:
	var remaining: Array=poly; var out: Array=[]
	for i in mask.size():
		var a: Vector2=mask[i]; var e: Vector2=mask[(i+1)%mask.size()]-a
		var n:=Vector2(-e.y,e.x); var c:=-n.dot(a)
		var outside:=clip(remaining,-n,-c)
		if not outside.is_empty(): out.append(outside)
		remaining=clip(remaining,n,c)
		if remaining.is_empty(): break
	return out

static func height(plane: Vector3, p: Vector2) -> float: return plane.x*p.x+plane.y*p.y+plane.z
static func point(plane: Vector3, p: Vector2) -> Vector3: return Vector3(p.x,height(plane,p),p.y)
static func arr(p: Vector3) -> Array: return [snappedf(p.x,.000001)+0.0,snappedf(p.y,.000001)+0.0,snappedf(p.z,.000001)+0.0]
static func vec(a: Array) -> Vector3: return Vector3(a[0],a[1],a[2])

static func planes(m: Dictionary) -> Array:
	var r: Array=m.rect; var slope: float=tan(deg_to_rad(m.pitch)); var y: float=m.eave_y
	var result: Array=[]
	if m.style=="flat": return [Vector3(0,0,y)]
	if m.axis=="depth" or m.style=="hip":
		result.append(Vector3(slope,0,y-r[0]*slope)); result.append(Vector3(-slope,0,y+r[2]*slope))
	if m.axis=="width" or m.style=="hip":
		result.append(Vector3(0,slope,y-r[1]*slope)); result.append(Vector3(0,-slope,y+r[3]*slope))
	if m.style=="shed": return [result[0]]
	return result

static func facets(modules: Array) -> Array:
	var all: Array=[]
	for m in modules:
		var ps:=planes(m)
		for i in ps.size():
			var poly:=rect(m.domain)
			for j in ps.size():
				if i==j: continue
				var delta: Vector3=ps[j]-ps[i]
				poly=clip(poly,Vector2(delta.x,delta.y),delta.z)
				if poly.is_empty(): break
			if not poly.is_empty(): all.append({"id":m.id+"/face%d"%i,"module":m,"plane":ps[i],"polygon":poly})
	return all

static func solve(modules: Array, openings: Array=[]) -> Dictionary:
	if modules.is_empty() or modules.size()>16: return {"ok":false,"error":"屋顶主体数量必须为 1–16"}
	var ids: Dictionary={}
	for m in modules:
		if ids.has(m.id) or m.style not in ["gable","hip","shed","flat"] or m.axis not in ["depth","width"]: return {"ok":false,"error":"屋顶主体标识或样式无效"}
		ids[m.id]=true
		for field in ["rect","domain"]:
			if m[field].size()!=4 or m[field].any(func(v):return not is_finite(float(v))) or m[field][2]-m[field][0]<.05 or m[field][3]-m[field][1]<.05: return {"ok":false,"error":"屋顶轮廓退化"}
		if not is_finite(float(m.eave_y)) or not is_finite(float(m.pitch)) or m.pitch<0 or m.pitch>75: return {"ok":false,"error":"屋顶高度或坡度无效"}
	var source:=facets(modules); var faces: Array=[]
	# An attached ridge must die inside the parent roof. Otherwise its cut end
	# would need an unsupported vertical step; report the incompatible dimensions.
	for module in modules:
		if not module.has("join_end"): continue
		var at: int=module.join_end; var domain: Array=module.domain
		var a:=Vector2(domain[at],domain[1]) if at==2 else Vector2(domain[0],domain[at])
		var b:=Vector2(domain[at],domain[3]) if at==2 else Vector2(domain[2],domain[at])
		var samples: Array=[a,b,(a+b)/2]
		for facet in source:
			if facet.module.id==module.id:
				for p in facet.polygon:
					if absf(p.x-domain[at] if at==2 else p.y-domain[at])<EPS: samples.append(p)
		for p in samples:
			var own:=INF; var parent:=-INF
			for plane in planes(module): own=minf(own,height(plane,p))
			for other in modules:
				if other.id==module.id or absf(other.eave_y-module.eave_y)>EPS: continue
				if not Geometry2D.is_point_in_polygon(p,PackedVector2Array(rect(other.domain))): continue
				var y:=INF
				for plane in planes(other): y=minf(y,height(plane,p))
				parent=maxf(parent,y)
			if own>parent+.001: return {"ok":false,"error":"同高翼楼屋脊无法收进主屋屋面，请减少翼楼跨度、增加主屋跨度或调整屋脊方向","module":module.id}
	for i in source.size():
		var f: Dictionary=source[i]; var fragments: Array=[f.polygon]
		for j in source.size():
			if i==j: continue
			var other: Dictionary=source[j]
			if other.module.id==f.module.id: continue
			var mask: Array=[]
			if absf(other.module.eave_y-f.module.eave_y)<EPS:
				var delta: Vector3=other.plane-f.plane
				if delta.length()<EPS:
					if j>i: continue # Stable owner for coincident planes.
					mask=other.polygon
				else: mask=clip(other.polygon,Vector2(delta.x,delta.y),delta.z)
			elif other.module.eave_y>f.module.eave_y:
				# Lower roofs terminate at the actual upper building wall, not its overhang.
				mask=rect(other.module.rect)
			else: continue
			if mask.is_empty(): continue
			var next: Array=[]
			for poly in fragments: next.append_array(subtract(poly,mask))
			fragments=next
		for cut in openings:
			if cut.module!=f.module.id: continue
			var next: Array=[]
			for poly in fragments: next.append_array(subtract(poly,rect(cut.rect)))
			fragments=next
		for k in fragments.size():
			var poly: Array=fragments[k]; var boundary: Array=[]
			for p in poly: boundary.append(arr(point(f.plane,p)))
			faces.append({"id":f.id+"/patch%d"%k,"module":f.module.id,"floor":f.module.floor,"plane":arr(f.plane),"boundary":boundary,"material":"roof_top","area":area(poly)*sqrt(1+f.plane.x*f.plane.x+f.plane.y*f.plane.y)})
		if faces.size()>MAX_FACES: return {"ok":false,"error":"屋顶裁切超过 512 个面，请简化建筑组合"}
	# Reject a dormer/chimney on a swallowed roof/valley. Never ignore an invalid hole.
	for cut in openings:
		var visible:=0.0; var expected:=area(rect(cut.rect))
		for f in source:
			if f.module.id!=cut.module: continue
			var poly: Array=f.polygon
			for edge in 4:
				var mask:=rect(cut.rect); var a: Vector2=mask[edge]; var e: Vector2=mask[(edge+1)%4]-a; var n:=Vector2(-e.y,e.x)
				poly=clip(poly,n,-n.dot(a))
			for other in source:
				if other.module.id==cut.module or poly.is_empty(): continue
				var delta: Vector3=other.plane-f.plane
				var covered: Array=clip(poly,Vector2(delta.x,delta.y),delta.z-.001)
				for i in other.polygon.size():
					var a: Vector2=other.polygon[i]; var e: Vector2=other.polygon[(i+1)%other.polygon.size()]-a; var n:=Vector2(-e.y,e.x)
					covered=clip(covered,n,-n.dot(a))
				if area(covered)>.00001: return {"ok":false,"error":"屋顶开洞与交接谷线重叠，请移动翼楼、改变屋脊方向或减少老虎窗","opening":cut.id}
			visible+=area(poly)
		if absf(visible-expected)>.001: return {"ok":false,"error":"屋顶开洞越过檐口","opening":cut.id}
	var result:={"ok":true,"version":1,"solver":"module_planar_envelope","modules":modules,"faces":faces,"openings":openings,"diagnostics":[]}
	result.edges=edges(faces,modules,openings)
	return result

static func edge_key(a: Vector3, b: Vector3) -> String:
	var aa:="%d,%d,%d"%[roundi(a.x*10000),roundi(a.y*10000),roundi(a.z*10000)]; var bb:="%d,%d,%d"%[roundi(b.x*10000),roundi(b.y*10000),roundi(b.z*10000)]
	return aa+"|"+bb if aa<bb else bb+"|"+aa

static func on_segment(p: Vector3, a: Vector3, b: Vector3) -> bool:
	var delta:=b-a; var t:=(p-a).dot(delta)/delta.length_squared()
	return t>=-EPS and t<=1+EPS and (a+delta*t).distance_to(p)<.0001

static func edges(faces: Array, modules: Array, openings: Array) -> Array:
	var points: Array[Vector3]=[]; var segments: Dictionary={}
	for face in faces:
		for p in face.boundary: points.append(vec(p))
	# Split T junctions before comparing edges; rectangular clipping creates them.
	for face in faces:
		for i in face.boundary.size():
			var a:=vec(face.boundary[i]); var b:=vec(face.boundary[(i+1)%face.boundary.size()]); var splits: Array[Vector3]=[a,b]
			for p in points:
				if on_segment(p,a,b) and not splits.any(func(q):return q.distance_to(p)<.0001): splits.append(p)
			splits.sort_custom(func(p,q):return a.distance_squared_to(p)<a.distance_squared_to(q))
			for j in splits.size()-1:
				var key:=edge_key(splits[j],splits[j+1])
				if not segments.has(key): segments[key]={"a":arr(splits[j]),"b":arr(splits[j+1]),"faces":[]}
				segments[key].faces.append(face)
	var out: Array=[]
	for key in segments:
		var edge: Dictionary=segments[key]; var a:=vec(edge.a); var b:=vec(edge.b); var mid:=(a+b)/2; var fs: Array=edge.faces
		var kind:="eave"
		if fs.size()>1:
			var p0:=vec(fs[0].plane); var p1:=vec(fs[1].plane)
			if p0.distance_to(p1)<.0001: continue
			var sample:=vec(fs[0].boundary[0]); var best:=0.0
			for v in fs[0].boundary:
				var distance:=(b-a).cross(vec(v)-a).length()
				if distance>best: sample=vec(v); best=distance
			kind="ridge" if height(p0,Vector2(sample.x,sample.z))<height(p1,Vector2(sample.x,sample.z)) else "valley"
			if kind=="ridge" and absf(a.y-b.y)>.001: kind="hip"
		else:
			for cut in openings:
				if cut.module!=fs[0].module: continue
				var r: Array=cut.rect
				if mid.x>=r[0]-.001 and mid.x<=r[2]+.001 and mid.z>=r[1]-.001 and mid.z<=r[3]+.001: kind="opening"
			for m in modules:
				if m.id==fs[0].module: continue
				var r: Array=m.rect
				if m.eave_y>mid.y-.001 and mid.x>=r[0]-.001 and mid.x<=r[2]+.001 and mid.z>=r[1]-.001 and mid.z<=r[3]+.001: kind="wall_abutment"
			if kind=="eave" and absf(a.y-b.y)>.001: kind="gable"
		out.append({"id":"edge%d"%out.size(),"type":kind,"a":edge.a,"b":edge.b,"faces":fs.map(func(f):return f.id),"module":fs[0].module,"floor":fs[0].floor})
	return out
