extends RefCounted
const Data=preload("res://scripts/world3d/city_layout.gd")
const F=preload("res://scripts/world3d/fortification_data.gd")
const Plan=preload("res://scripts/world3d/fortification_plan.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Scatter=preload("res://scripts/world3d/vegetation_scatter.gd")
var editor: Node3D
var overlay_plan: Dictionary={}
func regions() -> Array: return Data.resolve(editor._doc.map_meta).get("fortifications",[])
func catalog() -> Dictionary:
	var items: Array=[]
	for r in regions(): items.append({"settings":r.settings,"count":r.parts.size(),"modified_or_missing":r.parts.filter(func(p):return Data.token(editor._doc._find(p.id))!=p.signature).map(func(p):return p.id)})
	return {"ok":true,"regions":items}
func owned(region: Dictionary,verify:=true) -> Dictionary:
	var ids:={}
	for part in region.get("parts",[]):
		var r: Dictionary=editor._doc._find(part.id)
		if not r.is_empty() and not editor._record_editable(r): return Data.fail("城墙含锁定、隐藏或隔层构件")
		if verify and (r.is_empty() or Data.token(r)!=part.signature): return Data.fail("城墙构件已手改或删除，请恢复修改或解除关联保留现场")
		ids[part.id]=true
	return {"ok":true,"ids":ids}
func paint(r: Dictionary,material: Dictionary) -> Dictionary:
	var node: MeshInstance3D=editor._doc._mesh(r); var geometry:=Paint.geometry(node); node.free()
	if not geometry.ok: return geometry
	var entries: Array=[]; var tile: Array=material.get("tile_size",[1,1])
	for slot in geometry.surfaces.size():
		var surface: Dictionary=geometry.surfaces[slot]
		for face in surface.faces: entries.append({"mesh":".","surface":slot,"face":face,"geometry":surface.signature,"material":material.duplicate(true),"mapping":"uv" if r.has("channel_mesh") else "meters","scale":[1.0/tile[0],1.0/tile[1]],"offset":[0,0],"rotation":0.0})
	r.surface_paint=entries
	return {"ok":true} if Paint.valid(r) and Paint.missing([r]).is_empty() else Data.fail("城墙材质依赖缺失")
func prepare(args: Dictionary) -> Dictionary:
	var issue:=F.S.validate(args,F.request_schema())
	if not issue.is_empty(): return Data.fail(issue)
	var old: Dictionary={}
	for r in regions():
		if r.settings.id==args.id: old=r
	if old.is_empty() and regions().size()>=64: return Data.fail("城墙最多 64 组")
	var settings:=F.defaults(); settings.merge(old.get("settings",{}),true); var changes:=args.duplicate(true); changes.erase("plan_token"); settings.merge(changes,true)
	if settings.shape=="ellipse": settings.closed=true
	if not F.valid_settings(settings): return Data.fail("城墙路径或参数无效")
	var owner:=owned(old)
	if not owner.ok: return owner
	var result:=Plan.new().build(settings)
	if not result.ok: return result
	var materials:={}
	for role in ["stone","door"]:
		var id: String=settings[role+"_material_id"]
		if not id.is_empty():
			materials[role]=editor._material_tool.library.find(id)
			if materials[role].is_empty(): return Data.fail("城墙材质不存在："+id)
	var token:=Data.token([settings,editor._doc.records,Data.resolve(editor._doc.map_meta),editor._authoring.settings,materials])
	if args.has("plan_token") and args.plan_token!=token: return Data.fail("城墙预览已过期，请重新预览")
	var supports: Array=[]; var obstacles: Array=[]; var buildings:={}
	for r in editor._doc.records:
		if owner.ids.has(r.uuid): continue
		if r.has("building"):
			if not buildings.has(r.building.id): buildings[r.building.id]=[]
			buildings[r.building.id].append(r); continue
		var shapes:=Foot.record_shapes(r)
		var blocked: Array=[]
		for shape in shapes:
			if Foot.level_ground(r,shape,settings.base_height): supports.append(shape.polygon)
			else: blocked.append(shape)
		if not blocked.is_empty(): obstacles.append({"id":r.uuid,"road":r.has("road_mesh"),"shapes":blocked})
	for id in buildings: obstacles.append({"id":id,"road":false,"shapes":Foot.components(buildings[id],Vector3.ZERO,Basis.IDENTITY)})
	for shape in preload("res://scripts/world3d/planning_zones.gd").obstacles(editor._doc.map_meta): obstacles.append({"id":"planning_zone","road":false,"shapes":[shape]})
	var data:=Data.resolve(editor._doc.map_meta); var graph: Dictionary=data.roads; var analysis:=Data.analyze(graph)
	if not analysis.ok: return analysis
	for edge in graph.edges:
		var points: Array=analysis.paths[edge.id]
		for i in points.size()-1:
			var a:=Vector2(points[i].x,points[i].z); var b:=Vector2(points[i+1].x,points[i+1].z); var n:=Vector2(-(b-a).y,(b-a).x).normalized()*maxf(edge.width_start,edge.width_end)*.5
			var shape:=preload("res://scripts/world3d/waterway_plan.gd").shape([a-n,b-n,b+n,a+n],minf(points[i].y,points[i+1].y),maxf(points[i].y,points[i+1].y)+data.get("road_surface",{}).get("settings",{}).get("clearance",3.0))
			obstacles.append({"id":edge.id,"road":true,"shapes":[shape]})
	var parts: Array=[]; var checks:=0; var support_cache:={}
	for r in result.records:
		if not owner.ids.has(r.uuid) and editor._doc.has_uuid(r.uuid): return Data.fail("城墙构件 ID 冲突")
		if not editor._authoring.Settings.contains(r,editor._authoring.settings): return Data.fail("城墙构件落在当前隔离楼层外")
		var shapes:=Foot.record_shapes(r)
		for shape in shapes:
			var key:=str(shape.polygon)
			if not support_cache.has(key): support_cache[key]=Scatter.inside(shape.polygon,supports)
			if not support_cache[key]: return Data.fail("城墙、角塔或城门活动范围缺少同标高地面承托")
		for obstacle in obstacles:
			if obstacle.road and r.has("fixture"): continue # Gates intentionally control traffic; static masonry may never block it.
			checks+=shapes.size()*obstacle.shapes.size()
			if checks>1000000: return Data.fail("城墙碰撞检查超过预算，请分段生成")
			if Foot.batches_overlap(shapes,obstacle.shapes): return {"ok":false,"error":"城墙或城门活动范围与现有物件 / 道路净空重叠","conflicts":[obstacle.id]}
		var role: String="door" if r.has("fixture") else "stone"
		if materials.has(role):
			var painted:=paint(r,materials[role])
			if not painted.ok: return painted
		parts.append({"id":r.uuid,"signature":Data.token(r)})
	if editor._doc.records.size()-owner.ids.size()+result.records.size()>100000: return Data.fail("生成后超过地图物件上限")
	result.manifest={"version":1,"settings":settings,"parts":parts}; result.excluded=owner.ids; result.plan_token=token
	data.fortifications=regions().filter(func(r):return r.settings.id!=settings.id); data.fortifications.append(result.manifest)
	if not Data.valid({"editor_layout":data}): return Data.fail("城墙配方未通过保存校验")
	result.metadata=data; return result
func summary(args: Dictionary) -> Dictionary:
	var r:=prepare(args)
	if not r.ok: return r
	return {"ok":true,"settings":r.manifest.settings,"count":r.records.size(),"length":r.length,"gates":r.gates,"outline":r.get("outline",r.manifest.settings.points),"plan_token":r.plan_token}
func generate(args: Dictionary) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var r:=prepare(args)
	if not r.ok: return r
	if Data.token(r.metadata)==Data.token(Data.resolve(editor._doc.map_meta)): return {"ok":true,"changed":false,"count":r.records.size()}
	editor._doc.checkpoint_recovery(); editor._doc.records=editor._doc.records.filter(func(item):return not r.excluded.has(item.uuid)); editor._doc.records.append_array(r.records); editor._doc.map_meta.editor_layout=r.metadata; editor._dirty=true; editor._rebuild()
	return {"ok":true,"changed":true,"count":r.records.size(),"ids":r.records.map(func(item):return item.uuid)}
func set_gate(id: String,gate_id: String,amount: float) -> Dictionary:
	for r in regions():
		if r.settings.id!=id: continue
		var gates: Array=r.settings.gates.duplicate(true)
		for gate in gates:
			if gate.id==gate_id: gate.open=amount; return generate({"id":id,"gates":gates})
	return Data.fail("城墙或城门不存在")
func remove(id: String,keep: bool) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var old: Dictionary={}
	for r in regions():
		if r.settings.id==id: old=r
	if old.is_empty(): return Data.fail("城墙不存在")
	var owner:=owned(old,not keep)
	if not owner.ok: return owner
	editor._doc.checkpoint_recovery()
	if not keep: editor._doc.records=editor._doc.records.filter(func(r):return not owner.ids.has(r.uuid))
	else:
		for r in editor._doc.records:
			if owner.ids.has(r.uuid):
				preload("res://scripts/world3d/building_fixtures.gd").bake_snapshot(r); r.erase("fortification")
	var data:=Data.resolve(editor._doc.map_meta); data.fortifications=regions().filter(func(r):return r.settings.id!=id); editor._doc.map_meta.editor_layout=data; editor._dirty=true; editor._rebuild(); return {"ok":true}
