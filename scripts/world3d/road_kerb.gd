extends RefCounted
## Continuous inward profiles on exposed pavement boundaries. No object per stone.
const S=preload("res://scripts/world3d/document_schema.gd")
const EPS:=.001

static func settings()->Dictionary:
	return {"kerb_enabled":{"type":"boolean"},"kerb_width":S.number(.12,.4),"kerb_height":S.number(.025,.18),"kerb_material_id":{"type":"string","maxLength":256}}

static func defaults()->Dictionary:
	return {"kerb_enabled":false,"kerb_width":.28,"kerb_height":.055,"kerb_material_id":"pack:default:paving/automatic_limestone_kerb/material"}

static func schema()->Dictionary:
	var section:={"type":"array","minItems":6,"maxItems":6,"items":S.vector(-1000,1000)}
	var part:={"type":"object","properties":{"a":section,"b":section,"u":S.number(0,1000000),"length":S.number(.00001,1000),"cap_a":{"type":"boolean"},"cap_b":{"type":"boolean"}},"required":["a","b","u","length","cap_a","cap_b"],"additionalProperties":false}
	return {"type":"array","minItems":1,"maxItems":8192,"items":part}

static func vec(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
static func xyz(v:Vector3)->Array:return [v.x,v.y,v.z]
static func key(p:Vector3)->String:return "%d,%d,%d"%[roundi(p.x/EPS),roundi(p.y/EPS),roundi(p.z/EPS)]
static func flat(p:Vector3)->Vector2:return Vector2(p.x,p.z)

static func attach(records:Array, options:Dictionary, portals:Array)->Dictionary:
	if not options.get("kerb_enabled",false):return {"ok":true,"length":0.0}
	var edges:Array=[];var bins:Dictionary={}
	for record in records:
		var origin:=vec(record.position);var grade:Array=record.road_mesh.get("grade",[0,0])
		for polygon in record.road_mesh.polygons:
			var points:Array[Vector3]=[]
			for p in polygon:
				var x:float=p[0]*record.size[0];var z:float=p[1]*record.size[2]
				points.append(origin+Vector3(x,record.size[1]*.5+grade[0]*x+grade[1]*z,z))
			for i in points.size():
				var a:=points[i];var b:=points[(i+1)%points.size()]
				if a.distance_to(b)<EPS:continue
				var index:=edges.size();var cells:Array=[]
				for x in range(floori((minf(a.x,b.x)-EPS)/32),floori((maxf(a.x,b.x)+EPS)/32)+1):
					for z in range(floori((minf(a.z,b.z)-EPS)/32),floori((maxf(a.z,b.z)+EPS)/32)+1):
						var cell:=Vector2i(x,z);cells.append(cell)
						if not bins.has(cell):bins[cell]=[]
						bins[cell].append(index)
				edges.append({"a":a,"b":b,"record":record,"cells":cells})
	if edges.size()>100000:return {"ok":false,"error":"道路边界超过计算预算"}
	var exposed:Array=[];var work:=0
	for edge in edges:
		var d:Vector3=edge.b-edge.a;var length:=d.length();var unit:=d/length
		var cuts:Array=[0.0,1.0];var covers:Array=[];var candidates:Dictionary={}
		for cell in edge.cells:
			for index in bins[cell]:candidates[index]=true
		for index in candidates:
			work+=1
			if work>8000000:return {"ok":false,"error":"道路边界邻接计算超过预算，请分区规划"}
			var other:Dictionary=edges[index];var delta:Vector3=other.b-other.a
			if unit.dot(delta.normalized())>-.99999:continue
			if unit.cross(other.a-edge.a).length()>EPS or unit.cross(other.b-edge.a).length()>EPS:continue
			var t0:float=(other.a-edge.a).dot(unit)/length;var t1:float=(other.b-edge.a).dot(unit)/length
			var lo:=maxf(0,minf(t0,t1));var hi:=minf(1,maxf(t0,t1))
			if (hi-lo)*length<EPS:continue
			cuts.append(lo);cuts.append(hi);covers.append(Vector2(lo,hi))
		cuts.sort()
		for i in cuts.size()-1:
			if (cuts[i+1]-cuts[i])*length<EPS:continue
			var middle:float=(cuts[i]+cuts[i+1])*.5
			if covers.any(func(c):return middle>=c.x and middle<=c.y):continue
			var a:Vector3=edge.a+d*cuts[i];var b:Vector3=edge.a+d*cuts[i+1]
			if portal_edge(a,b,portals):continue
			exposed.append({"a":a,"b":b,"record":edge.record})
	# Boolean clipping can leave centimetre-long bevel fragments. Collapse these
	# before offsetting; otherwise the inner offset folds over its neighbour.
	var weld:Dictionary={}
	for edge in exposed:
		if edge.a.distance_to(edge.b)<.025:
			weld[key(edge.b)]=edge.a
	for edge in exposed:
		for field in ["a","b"]:
			var seen:Dictionary={}
			while weld.has(key(edge[field])) and not seen.has(key(edge[field])):
				seen[key(edge[field])]=true;edge[field]=weld[key(edge[field])]
	exposed=exposed.filter(func(e):return e.a.distance_to(e.b)>=EPS)
	var starts:Dictionary={};var ends:Dictionary={}
	for i in exposed.size():
		var edge:Dictionary=exposed[i]
		for pair in [[starts,key(edge.a)],[ends,key(edge.b)]]:
			if not pair[0].has(pair[1]):pair[0][pair[1]]=[]
			pair[0][pair[1]].append(i)
	var visited:Dictionary={};var total:=0.0;var seeds:Array=[]
	# Open boundaries start at their actual cap so UV distance never resets midway.
	for i in exposed.size():
		if not ends.has(key(exposed[i].a)):seeds.append(i)
	for i in exposed.size():seeds.append(i)
	for seed in seeds:
		if visited.has(seed):continue
		var at:int=seed;var u:=0.0
		while not visited.has(at):
			visited[at]=true
			var edge:Dictionary=exposed[at];var d:Vector2=(flat(edge.b)-flat(edge.a)).normalized();var inward:=Vector2(-d.y,d.x)
			var prev:Array=ends.get(key(edge.a),[]);var next:Array=starts.get(key(edge.b),[])
			if prev.size()>1 or next.size()>1:return {"ok":false,"error":"路缘边界在接点处分叉，请调整过窄或相切的道路"}
			var na:=inward;var nb:=inward
			if prev.size()==1:na=join(flat(exposed[prev[0]].b)-flat(exposed[prev[0]].a),d)
			if next.size()==1:nb=join(d,flat(exposed[next[0]].b)-flat(exposed[next[0]].a))
			if na==Vector2.ZERO or nb==Vector2.ZERO:return {"ok":false,"error":"路缘内角过尖，无法生成安全截面，请调宽或圆滑该路口"}
			var record:Dictionary=edge.record;var origin:=vec(record.position);var grade:Array=record.road_mesh.get("grade",[0,0]);var length:float=edge.a.distance_to(edge.b)
			var part:={"a":section(edge.a-origin,na,options,grade),"b":section(edge.b-origin,nb,options,grade),"u":u,"length":length,"cap_a":prev.is_empty(),"cap_b":next.is_empty()}
			# Reject folded strips rather than emitting overlapping corner geometry.
			if (flat(vec(part.b[5]))-flat(vec(part.a[5]))).dot(d)<-EPS:return {"ok":false,"error":"道路边角短于路缘宽度，请减小路缘宽度或调整路口"}
			if not record.road_mesh.has("kerbs"):record.road_mesh.kerbs=[]
			record.road_mesh.kerbs.append(part);u+=length;total+=length
			if next.is_empty():break
			at=next[0]
	return {"ok":true,"length":total}

static func join(before:Vector2,after:Vector2)->Vector2:
	var a:=before.normalized();var b:=after.normalized();var n:=Vector2(-a.y,a.x);var m:=(n+Vector2(-b.y,b.x)).normalized();var dot:=m.dot(n)
	return m/dot if dot>.34 else Vector2.ZERO

static func portal_edge(a:Vector3,b:Vector3,portals:Array)->bool:
	for portal in portals:
		for at in 2:
			var p:=vec(portal.endpoints[at]);var other:=vec(portal.endpoints[1-at]);var d:Vector2=(flat(p)-flat(other)).normalized()
			if absf(a.y-p.y)>.08 or absf(b.y-p.y)>.08:continue
			if absf((flat(a)-flat(p)).dot(d))<.08 and absf((flat(b)-flat(p)).dot(d))<.08:
				if (flat((a+b)*.5)-flat(p)).length()<float(portal.width)*.5+.05:return true
	return false

static func section(p:Vector3,n:Vector2,options:Dictionary,grade:Array)->Array:
	var w:float=options.kerb_width;var h:float=options.kerb_height;var bevel:=minf(.018,h*.4);var out:Array=[]
	for v in [Vector2(0,-.04),Vector2(0,h-bevel),Vector2(bevel,h),Vector2(w-bevel,h),Vector2(w,h-bevel),Vector2(w,-.04)]:
		var xz:Vector2=n*v.x;out.append(xyz(p+Vector3(xz.x,v.y+grade[0]*xz.x+grade[1]*xz.y,xz.y)))
	return out

static func arrays(record:Dictionary)->Array:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in record.road_mesh.get("kerbs",[]):
		var a:Array=part.a.map(vec);var b:Array=part.b.map(vec);var v:=0.0
		for i in 6:
			var j:=(i+1)%6;var next:float=v+a[i].distance_to(a[j])
			triangle(st,[a[i],b[i],b[j]],[Vector2(part.u,v),Vector2(part.u+part.length,v),Vector2(part.u+part.length,next)])
			triangle(st,[a[i],b[j],a[j]],[Vector2(part.u,v),Vector2(part.u+part.length,next),Vector2(part.u,next)])
			v=next
		for cap in 2:
			if not part["cap_a" if cap==0 else "cap_b"]:continue
			var points:Array=a if cap==0 else b
			for i in range(1,5):
				var tri:Array=[points[0],points[i],points[i+1]] if cap==0 else [points[0],points[i+1],points[i]]
				triangle(st,tri,tri.map(func(p):return Vector2(p.distance_to(points[0]),p.y)))
	st.generate_tangents();return st.commit_to_arrays()

static func triangle(st:SurfaceTool,points:Array,uv:Array)->void:
	var normal:Vector3=(points[2]-points[0]).cross(points[1]-points[0]).normalized()
	if normal.length()<.5:return
	for i in 3:
		st.set_normal(normal);st.set_uv(uv[i]/1.76);st.add_vertex(points[i])
