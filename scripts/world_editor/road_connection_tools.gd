extends RefCounted
const Data=preload("res://scripts/world3d/city_layout.gd")
const Bridges=preload("res://scripts/world3d/road_bridges.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
var editor: Node3D
func connect_bridge(waterway_id: String,bridge_id: String) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var data:=Data.resolve(editor._doc.map_meta); var region: Dictionary={}; var bridge: Dictionary={}
	for r in data.get("waterways",[]):
		if r.settings.id==waterway_id: region=r
	if region.is_empty(): return Data.fail("河道不存在")
	for b in region.settings.bridges:
		if b.id==bridge_id: bridge=b
	if bridge.is_empty(): return Data.fail("河道桥梁不存在")
	var owned: Dictionary=editor._waterways.owned(region)
	if not owned.ok: return owned
	for edge in data.roads.edges:
		if edge.get("bridge_ref",{})=={"waterway_id":waterway_id,"bridge_id":bridge_id}: return {"ok":true,"changed":false,"edge_id":edge.id}
	var port:=Bridges.geometry(region.settings,bridge); var ids: Array=[]; var prefix: String="bridge_link_"+str([waterway_id,bridge_id]).sha256_text().left(16)
	for i in 2:
		var id: String=prefix+"_%d"%i
		for node in data.roads.nodes:
			if Data.vec(node.position).distance_to(Data.vec(port.endpoints[i]))<.25:
				if node.get("hidden",false) or node.get("locked",false): return Data.fail("桥头附近道路节点受保护")
				for edge in data.roads.edges:
					if node.id in [edge.from,edge.to] and (edge.get("hidden",false) or edge.get("locked",false) or edge.has("bridge_ref")): return Data.fail("桥头附近节点关联了受保护道路或另一座桥")
				id=node.id; node.position=port.endpoints[i]; break
		var existing: Array=data.roads.nodes.filter(func(n):return n.id==id)
		if existing.is_empty(): data.roads.nodes.append({"id":id,"position":port.endpoints[i]})
		elif Data.vec(existing[0].position).distance_to(Data.vec(port.endpoints[i]))>.001: return Data.fail("桥头节点 ID 冲突")
		ids.append(id)
	if data.roads.edges.any(func(e):return e.id==prefix): return Data.fail("桥梁连线 ID 冲突")
	data.roads.edges.append({"id":prefix,"from":ids[0],"to":ids[1],"width_start":port.width,"width_end":port.width,"kind":"bridge","name":region.settings.name+" · 桥梁通行","bridge_ref":{"waterway_id":waterway_id,"bridge_id":bridge_id}})
	var linked:=Bridges.resolve(data)
	if not linked.ok: return linked
	var result: Dictionary=editor._city.commit(data); result.edge_id=prefix; result.nodes=ids; result.endpoints=port.endpoints; result.width=port.width
	return result
func disconnect_bridge(edge_id: String) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var data:=Data.resolve(editor._doc.map_meta); var found: Array=data.roads.edges.filter(func(e):return e.id==edge_id and e.has("bridge_ref"))
	if found.is_empty(): return Data.fail("桥梁连线不存在")
	var edge: Dictionary=found[0]
	if edge.get("locked",false) or edge.get("hidden",false): return Data.fail("请先解锁并显示桥梁连线")
	for n in data.roads.nodes:
		if n.id in [edge.from,edge.to] and (n.get("locked",false) or n.get("hidden",false)): return Data.fail("桥头节点受保护")
	var region: Array=data.get("waterways",[]).filter(func(r):return r.settings.id==edge.bridge_ref.waterway_id)
	if not region.is_empty():
		var owned: Dictionary=editor._waterways.owned(region[0],false)
		if not owned.ok: return owned
	data.roads.edges=data.roads.edges.filter(func(e):return e.id!=edge_id)
	# Keep nodes used by approach roads; remove only orphaned generated endpoints.
	data.roads.nodes=data.roads.nodes.filter(func(n):return n.id not in [edge.from,edge.to] or data.roads.edges.any(func(e):return n.id in [e.from,e.to]))
	return editor._city.commit(data)
func audit() -> Dictionary:
	var data:=Data.resolve(editor._doc.map_meta); var links:={}; var visited:={}; var components: Array=[]; var dead: Array=[]; var unsupported: Array=[]
	for n in data.roads.nodes: links[n.id]=[]
	for e in data.roads.edges: links[e.from].append(e.to); links[e.to].append(e.from)
	for n in data.roads.nodes:
		if links[n.id].size()==1: dead.append(n.id)
		if not visited.has(n.id):
			var pending: Array=[n.id]; var component: Array=[]; visited[n.id]=true
			while not pending.is_empty():
				var id: String=pending.pop_back(); component.append(id)
				for next in links[id]:
					if not visited.has(next): visited[next]=true; pending.append(next)
			components.append(component)
		var p:=Data.vec(n.position); var supported:=false
		for r in editor._doc.records:
			if r.get("collision","")=="none" or r.has("road_mesh"): continue
			if r.get("surface_id") not in ["ground","grass","dirt","stone","sand","bridge_deck","river_bank"]: continue
			if absf(r.rotation[0])+absf(r.rotation[2])>.001: continue
			if r.has("bridge_mesh"):
				var local: Vector3=Transform3D(Basis.from_euler(Data.vec(r.rotation)*PI/180),Data.vec(r.position)).affine_inverse()*p
				if absf(local.x)<=r.bridge_mesh.length*.5 and absf(local.z)<=(r.bridge_mesh.width-1.16)*.5 and absf(local.y-preload("res://scripts/world3d/bridge_mesh.gd").height_at(local.x,r.bridge_mesh))<.06: supported=true; break
				continue
			if r.has("terrain_mesh"):
				var terrain=preload("res://scripts/world3d/terrain_surface.gd")
				var h: float=terrain.sample(r,terrain.transform(r).affine_inverse()*p)
				if is_finite(h) and absf(h+r.position[1]-p.y)<.06: supported=true; break
				continue
			var top: float=r.position[1]+r.size[1]*.5
			if absf(top-p.y)>.06: continue
			for s in Foot.record_shapes(r):
				if Geometry2D.is_point_in_polygon(Vector2(p.x,p.z),s.polygon): supported=true; break
			if supported: break
		if not supported: unsupported.append(n.id)
	var build: Dictionary=editor._roads.summary({}); var binding:=Bridges.resolve(data)
	return {"ok":true,"components":components,"dead_end_nodes":dead,"unsupported_nodes":unsupported,"bridge_bindings":binding,"pavement_stale":editor._city.state().surface_stale,"buildability":build,"diagnostics":Data.analyze(data.roads).diagnostics}
