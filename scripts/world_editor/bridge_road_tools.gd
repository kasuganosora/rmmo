extends RefCounted
const Data=preload("res://scripts/world3d/city_layout.gd")
const Ports=preload("res://scripts/world3d/road_bridges.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
static func prepare(editor,args: Dictionary) -> Dictionary:
	var data: Dictionary=Data.resolve(editor._doc.map_meta).duplicate(true); var found: Array=data.roads.edges.filter(func(e):return e.id==args.road_edge_id)
	if found.size()!=1: return Data.fail("桥梁道路不存在")
	var edge: Dictionary=found[0]; var nodes:={}
	for n in data.roads.nodes: nodes[n.id]=n
	if edge.kind!="bridge" or edge.has("controls") or edge.has("bridge_ref"): return Data.fail("请选择直线桥梁道路；河道配方桥请在河道面板修改")
	for r in [edge,nodes[edge.from],nodes[edge.to]]:
		if r.get("locked",false) or r.get("hidden",false): return Data.fail("桥梁道路或桥头节点已锁定 / 隐藏")
	var original: Dictionary=edge.get("stone_bridge",{})
	if not original.is_empty():
		if original.id!=args.id or Data.token(editor._doc._find(args.id))!=original.signature: return Data.fail("已绑定桥梁的身份或构件已被手改，请先撤销手改")
		if Data.vec(args.start).distance_to(Data.vec(original.start))>.001 or Data.vec(args.end).distance_to(Data.vec(original.end))>.001 or absf(args.get("width",original.width)-original.width)>.001: return Data.fail("已绑定桥梁可改桥型、拱高和深度；跨度/净宽变化需先撤销该桥的转换")
	elif not editor._doc._find(args.id).is_empty(): return Data.fail("新绑定桥梁 ID 已被其他物件占用")
	var a:=Data.vec(nodes[edge.from].position); var b:=Data.vec(nodes[edge.to].position); var delta:=b-a; var length_:=delta.length(); var direction:=delta.normalized()
	if absf(a.y-b.y)>.001: return Data.fail("现阶段桥梁道路的两端须同高")
	var first:=Data.vec(args.start); var last:=Data.vec(args.end)
	var t0: float=(first-a).dot(direction); var t1: float=(last-a).dot(direction)
	for p in [first,last]:
		var ground: Vector3=p-Vector3.UP*.025
		if ground.distance_to(a+direction*(ground-a).dot(direction))>.003: return Data.fail("石桥须位于所选道路中心线，桥头高度为道路标高 + 0.025 米")
	if t0<2 or t1>length_-2 or t1-t0<6: return Data.fail("请在道路两端各保留至少 2 米引道，桥梁跨度至少 6 米")
	if args.get("width",6)<maxf(edge.width_start,edge.width_end)+1.16-.001: return Data.fail("桥梁总宽须比原道路宽至少 1.16 米，以保留石栏内通行净宽")
	var request:=args.duplicate(true); request.erase("road_edge_id"); request.erase("plan_token")
	var plan: Dictionary=editor._bridges.prepare(request,true)
	if not plan.ok: return plan
	var binding:={"id":args.id,"start":args.start,"end":args.end,"width":plan.record.bridge_mesh.width,"signature":Data.token(plan.record),"source_token":Ports.stone_source(edge,nodes)}
	var mask:=Ports.stone_polygon(binding); var box:=Rect2(mask[0],Vector2.ZERO)
	for p in mask: box=box.expand(p)
	var replacements:={}; var removed:={}; var touched: Array=[]
	for r in editor._doc.records:
		if not r.has("road_mesh") or absf(r.position[1]+r.size[1]*.5-first.y)>.08: continue
		var bounds: AABB=Foot.record_shape(r).bounds
		if not box.intersects(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z)): continue
		var cut: Dictionary=preload("res://scripts/world_editor/bridge_road_cut.gd").cut(r,mask,first.y)
		if not cut.ok: return cut
		if not cut.changed: continue
		if not editor._record_editable(r) or editor._selection_tools.members(r.uuid).is_empty(): return Data.fail("需要裁切的旧路面已受保护")
		touched.append(r.uuid)
		if cut.removed: removed[r.uuid]=true
		else: replacements[r.uuid]=cut.record
	edge.stone_bridge=binding
	if data.has("road_surface"):
		var parts: Array=[]
		for part in data.road_surface.parts:
			if part.id in touched:
				var old: Dictionary=editor._doc._find(part.id)
				if Surface.signature(old)!=part.signature: return Data.fail("生成路面已被手改，不能安全更新桥梁关联")
				if removed.has(part.id): continue
				var changed: Dictionary=replacements[part.id]; part.signature=Surface.signature(changed)
				if Data.token(old.get("surface_paint",[]))==part.paint_signature: part.paint_signature=Data.token(changed.get("surface_paint",[]))
			parts.append(part)
		data.road_surface.parts=parts; data.road_surface.graph_token=Data.token(data.roads)
	if not Data.valid({"editor_layout":data}): return Data.fail("桥梁道路绑定无法保存")
	var records: Array=[]
	for r in editor._doc.records:
		if r.uuid==args.id or removed.has(r.uuid): continue
		records.append(replacements.get(r.uuid,r))
	records.append(plan.record)
	var token:=Data.token([args.duplicate(true).merged({"plan_token":""},true),records,data,editor._doc.recovery_snapshot(),editor._authoring.settings])
	if args.has("plan_token") and args.plan_token!=token: return Data.fail("桥梁与道路预览已过期，请重新预览")
	return {"ok":true,"record":plan.record,"records":records,"layout":data,"trimmed_roads":touched,"plan_token":token,"road_edge_id":edge.id,"navigation":plan.navigation}
static func verify(editor,portal: Dictionary) -> Dictionary:
	var r: Dictionary=editor._doc._find(portal.deck_id)
	if not r.has("bridge_mesh") or Data.token(r)!=portal.signature: return Data.fail("道路石桥已被手改或删除，不能重新铺路")
	if not editor._record_editable(r): return Data.fail("道路石桥已隐藏、锁定或隔层")
	var transform:=Transform3D(Basis.from_euler(Data.vec(r.rotation)*PI/180).scaled(Data.vec(r.size)),Data.vec(r.position))
	for i in 2:
		if (transform*Vector3((i*2-1)*r.bridge_mesh.length*.5,0,0)).distance_to(Data.vec(portal.endpoints[i]))>.003: return Data.fail("道路绑定与实际桥梁位置不一致")
	if absf(r.bridge_mesh.width*r.size[2]-portal.width-1.16)>.003: return Data.fail("道路绑定与实际桥梁宽度不一致")
	return {"ok":true}
