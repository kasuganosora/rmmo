extends RefCounted
const Data=preload("res://scripts/world3d/city_layout.gd")

static func position(edge: Dictionary, nodes: Dictionary, t: float) -> Vector3:
	var a:=Data.vec(nodes[edge.from].position); var b:=Data.vec(nodes[edge.to].position)
	return a.bezier_interpolate(Data.vec(edge.controls[0]),Data.vec(edge.controls[1]),b,t) if edge.has("controls") else a.lerp(b,t)
static func derivative(edge: Dictionary, nodes: Dictionary, t: float) -> Vector3:
	var a:=Data.vec(nodes[edge.from].position); var b:=Data.vec(nodes[edge.to].position)
	if not edge.has("controls"): return b-a
	var c:=Data.vec(edge.controls[0]); var d:=Data.vec(edge.controls[1])
	return 3*((c-a)*(1-t)*(1-t)+2*(d-c)*t*(1-t)+(b-d)*t*t)
static func nearest(edge: Dictionary, nodes: Dictionary, p: Vector3) -> float:
	var samples:=Data.samples(edge,nodes); var distance:=INF; var t:=0.0
	for i in samples.size()-1:
		var a:=Vector2(samples[i].x,samples[i].z); var b:=Vector2(samples[i+1].x,samples[i+1].z); var point:=Vector2(p.x,p.z)
		var u:=clampf((point-a).dot(b-a)/(b-a).length_squared(),0,1)
		var d:=a.lerp(b,u).distance_squared_to(point)
		if d<distance: distance=d; t=(i+u)/(samples.size()-1)
	return t

static func split(graph: Dictionary) -> Dictionary:
	var checked:=Data.analyze(graph)
	if not checked.ok: return checked
	var edges:={}; var nodes: Dictionary=checked.nodes.duplicate(true); var cuts:={}
	for edge in graph.edges: edges[edge.id]=edge; cuts[edge.id]=[{"t":0.0,"node":edge.from},{"t":1.0,"node":edge.to}]
	for issue in checked.diagnostics:
		if issue.code in ["self_crossing","overlapping_centerlines"]: return Data.fail("自交曲线或重叠道路需先手工整理，不能自动猜测连接关系")
		if issue.code!="unconnected_crossing": continue
		var a: Dictionary=edges[issue.edges[0]]; var b: Dictionary=edges[issue.edges[1]]
		if a.has("bridge_ref") or b.has("bridge_ref"): return Data.fail("不能拆分已绑定桥梁，请将道路连接到桥头节点")
		if a.kind!=b.kind: continue # Bridge portals must be authored explicitly.
		var p:=Data.vec(issue.position); var t:=nearest(a,nodes,p); var u:=nearest(b,nodes,p)
		for iteration in 12:
			var delta:=position(a,nodes,t)-position(b,nodes,u)
			if Vector2(delta.x,delta.z).length()<.0001: break
			var da:=derivative(a,nodes,t); var db:=derivative(b,nodes,u); var det:=da.x*db.z-da.z*db.x
			if absf(det)<.000001: return Data.fail("近切线交汇无法稳定拆分，请增加连接节点")
			t=clampf(t-(delta.x*db.z-delta.z*db.x)/det,0,1)
			u=clampf(u-(delta.x*da.z-delta.z*da.x)/det,0,1)
		var pa:=position(a,nodes,t); var pb:=position(b,nodes,u)
		if Vector2(pa.x-pb.x,pa.z-pb.z).length()>.01: return Data.fail("曲线交汇超出求解误差，请手动增加节点")
		if absf(pa.y-pb.y)>.01: continue
		p=(pa+pb)*.5
		var id:=""
		for node in nodes.values():
			if Data.vec(node.position).distance_to(p)<.01:
				if not id.is_empty() and id!=node.id: return Data.fail("交点有多个重合节点，请先统一端点 ID")
				id=node.id
		if id.is_empty():
			id="junction_"+str([snappedf(p.x,.001),snappedf(p.y,.001),snappedf(p.z,.001)]).sha256_text().left(16)
			nodes[id]={"id":id,"position":Data.xyz(p)}
		for pair in [[a,t],[b,u]]:
			var edge: Dictionary=pair[0]; var at: float=pair[1]
			if at<.00001 or at> .99999: continue
			if not cuts[edge.id].any(func(c): return absf(c.t-at)<.00001): cuts[edge.id].append({"t":at,"node":id})
	var out:={"nodes":nodes.values(),"edges":[]}
	for edge in graph.edges:
		var points: Array=cuts[edge.id]; points.sort_custom(func(a,b): return a.t<b.t)
		if points.size()==2:
			out.edges.append(edge.duplicate(true)); continue
		for i in points.size()-1:
			var lo: float=points[i].t; var hi: float=points[i+1].t; var part: Dictionary=edge.duplicate(true)
			part.from=points[i].node; part.to=points[i+1].node
			if i>0: part.id=edge.id.left(60)+"_"+str([part.from,part.to]).sha256_text().left(10)
			part.width_start=lerpf(edge.width_start,edge.width_end,lo); part.width_end=lerpf(edge.width_start,edge.width_end,hi)
			if edge.has("controls"):
				part.controls=[Data.xyz(position(edge,nodes,lo)+derivative(edge,nodes,lo)*(hi-lo)/3),Data.xyz(position(edge,nodes,hi)-derivative(edge,nodes,hi)*(hi-lo)/3)]
			out.edges.append(part)
	var audit:=Data.analyze(out)
	if not audit.ok: return audit
	return {"ok":true,"graph":out,"added_nodes":out.nodes.size()-graph.nodes.size(),"added_edges":out.edges.size()-graph.edges.size(),"diagnostics":audit.diagnostics}
