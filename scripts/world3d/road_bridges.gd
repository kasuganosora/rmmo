extends RefCounted
## Metadata-only bridge bindings, shared by persistence and editor operations.
static func vec(a: Array) -> Vector3: return Vector3(a[0],a[1],a[2])
static func xyz(p: Vector3) -> Array: return [p.x,p.y,p.z]
static func geometry(settings: Dictionary,bridge: Dictionary) -> Dictionary:
	var a:=Vector2(settings.points[int(bridge.segment)][0],settings.points[int(bridge.segment)][1]); var b:=Vector2(settings.points[int(bridge.segment)+1][0],settings.points[int(bridge.segment)+1][1])
	var tangent: Vector2=(b-a).normalized(); var n:=Vector2(-tangent.y,tangent.x); var c:=a.lerp(b,bridge.t)
	var half: float=settings.width*.5+settings.bank_width+bridge.approach; var y: float=settings.bank_height
	var prefix: String="river_"+settings.id.sha256_text().left(16)+"_bridge_"+bridge.id.sha256_text().left(10)
	var stone: bool=bridge.get("prefab_id","legacy_flat")!="legacy_flat"
	return {"endpoints":[xyz(Vector3((c-n*half).x,y,(c-n*half).y)),xyz(Vector3((c+n*half).x,y,(c+n*half).y))],"width":bridge.width-(1.16 if stone else .6),"deck_id":prefix,"part_ids":[prefix] if stone else [prefix,prefix+"_rail_m1",prefix+"_rail_1"]}
static func resolve(data: Dictionary) -> Dictionary:
	var nodes:={}; var ports: Array=[]; var used:={}
	for node in data.roads.nodes: nodes[node.id]=node
	for edge in data.roads.edges:
		if not edge.has("bridge_ref"): continue
		var settings: Dictionary={}; var bridge: Dictionary={}; var ref: Dictionary=edge.bridge_ref
		for region in data.get("waterways",[]):
			if region.settings.id==ref.waterway_id: settings=region.settings
		if not settings.is_empty():
			for b in settings.bridges:
				if b.id==ref.bridge_id: bridge=b
		if bridge.is_empty(): return {"ok":false,"error":"道路绑定的河道桥梁不存在"}
		var port:=geometry(settings,bridge)
		if used.has(port.deck_id): return {"ok":false,"error":"一座桥只能接入路网一次"}
		used[port.deck_id]=true
		if not nodes.has(edge.from) or not nodes.has(edge.to) or edge.kind!="bridge" or edge.has("controls") or absf(edge.width_start-port.width)>.001 or absf(edge.width_end-port.width)>.001: return {"ok":false,"error":"已绑定桥梁的端点、净宽和形状由河道配方管理"}
		for i in 2:
			if vec(nodes[[edge.from,edge.to][i]].position).distance_to(vec(port.endpoints[i]))>.001: return {"ok":false,"error":"桥头节点偏离实际桥梁，请先解除路网绑定"}
		port.nodes=[edge.from,edge.to]; port.edge_id=edge.id; port.reference=ref; ports.append(port)
	for port in ports:
		for i in 2:
			var node: String=port.nodes[i]; var endpoint:=vec(port.endpoints[i]); var outward: Vector3=(endpoint-vec(port.endpoints[1-i])).normalized()
			for edge in data.roads.edges:
				if edge.id==port.edge_id or node not in [edge.from,edge.to]: continue
				var start: bool=edge.from==node; var other:=vec(nodes[edge.to if start else edge.from].position)
				if edge.has("controls"): other=vec(edge.controls[0 if start else 1])
				var direction:=Vector3(other.x-endpoint.x,0,other.z-endpoint.z).normalized()
				if direction.dot(outward)<.999 or (edge.width_start if start else edge.width_end)>port.width+.001: return {"ok":false,"error":"桥头接路须朝桥外直向接入，端点路宽不能超过桥面净宽；请在外侧另设转弯节点"}
	return {"ok":true,"portals":ports}
