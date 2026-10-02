extends RefCounted
const Data=preload("res://scripts/world3d/city_layout.gd")
const W=preload("res://scripts/world3d/waterway_data.gd")
const Plan=preload("res://scripts/world3d/waterway_plan.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var editor: Node3D
var overlay_plan: Dictionary={}
func regions() -> Array: return Data.resolve(editor._doc.map_meta).get("waterways",[])
func catalog() -> Dictionary:
	var result: Array=[]
	for region in regions():
		var modified: Array=[]
		for part in region.parts:
			if Data.token(editor._doc._find(part.id))!=part.signature: modified.append(part.id)
		result.append({"settings":region.settings,"count":region.parts.size(),"modified_or_missing":modified})
	return {"ok":true,"regions":result}
func owned(region: Dictionary,verify:=true) -> Dictionary:
	var ids:={}
	for part in region.get("parts",[]):
		var r: Dictionary=editor._doc._find(part.id)
		if not r.is_empty() and not editor._record_editable(r): return Data.fail("河道含锁定、隐藏或隔层构件，请先解除保护")
		if verify and (r.is_empty() or Data.token(r)!=part.signature): return Data.fail("河道或挖河地面已被手改 / 删除，请恢复修改，或解除关联后保留现场")
		ids[part.id]=true
	return {"ok":true,"ids":ids}
func paint(record: Dictionary,material: Dictionary) -> Dictionary:
	var node:=MeshInstance3D.new(); node.mesh=preload("res://scripts/world3d/channel_surface.gd").mesh(record,null)
	var geometry:=Paint.geometry(node); node.free()
	if not geometry.ok: return geometry
	var entries: Array=[]; var tile: Array=material.get("tile_size",[1,1])
	for slot in geometry.surfaces.size():
		var surface: Dictionary=geometry.surfaces[slot]
		for face in surface.faces:
			entries.append({"mesh":".","surface":slot,"face":face,"geometry":surface.signature,"material":material.duplicate(true),"mapping":"uv","scale":[1.0/tile[0],1.0/tile[1]],"offset":[0,0],"rotation":0.0})
	record.surface_paint=entries
	return {"ok":true} if Paint.valid(record) and Paint.missing([record]).is_empty() else Data.fail("河岸 / 桥梁材质依赖缺失或刷面数量超限")
func prepare(args: Dictionary) -> Dictionary:
	var issue:=W.S.validate(args,W.request_schema())
	if not issue.is_empty(): return Data.fail(issue)
	var old: Dictionary={}
	for region in regions():
		if region.settings.id==args.id: old=region
	if old.is_empty() and regions().size()>=32: return Data.fail("河道最多 32 条")
	var settings:=W.defaults(); settings.merge(old.get("settings",{}),true); var changes:=args.duplicate(true); changes.erase("plan_token"); settings.merge(changes,true)
	if not W.valid_settings(settings): return Data.fail("请提供河道中心线及要挖开的平地 ID，检查参数和桥梁位置")
	var linked: bool=Data.resolve(editor._doc.map_meta).roads.edges.any(func(e):return e.get("bridge_ref",{}).get("waterway_id","")==settings.id)
	if linked and Data.token(settings)!=Data.token(old.get("settings",{})): return Data.fail("河道桥梁已接入路网，请先解除桥梁路网绑定，再修改河道")
	if not old.is_empty() and settings.ground_ids!=old.settings.ground_ids: return Data.fail("更新河道时不能更换挖河地面；请先恢复原地面，再新建河道")
	var ownership:=owned(old)
	if not ownership.ok: return ownership
	var sources: Array=[]
	if not old.is_empty(): sources=old.sources.duplicate(true)
	else:
		var other_members:={}
		for region in regions():
			for part in region.parts: other_members[part.id]=true
		for id in settings.ground_ids:
			var r: Dictionary=editor._doc._find(id)
			if r.is_empty() or other_members.has(id): return Data.fail("地面不存在或属于另一条河道")
			if not editor._record_editable(r): return Data.fail("挖河前请显示并解锁地面，关闭隔层保护")
			if not W.ground_valid(r,settings.bank_height): return Data.fail("仅支持同标高的普通水平地面盒；带刷面、事件、分组、自动瓦片或生成归属的地面需先另行整理")
			sources.append(r.duplicate(true)); ownership.ids[id]=true
	var result:=Plan.new().build(settings,sources)
	if not result.ok: return result
	var materials:={}
	for role in ["bank","bed","bridge"]:
		var id: String=settings[role+"_material_id"]
		if not id.is_empty():
			var material: Dictionary=editor._material_tool.library.find(id)
			if material.is_empty(): return Data.fail("材质不存在："+id)
			materials[role]=material
	var token:=Data.token([settings,Data.resolve(editor._doc.map_meta),editor._doc.records,editor._authoring.settings,materials])
	if args.has("plan_token") and args.plan_token!=token: return Data.fail("河道预览已过期，请重新预览")
	# Reserve excavated volume and the space above the water, including hidden objects.
	var envelopes: Array=[]
	for poly in result.envelope: envelopes.append(Plan.shape(poly,settings.bank_height-settings.water_drop-settings.depth-.2,settings.bank_height+3))
	for crossing in result.crossings: envelopes.append(crossing.shape)
	if not old.is_empty():
		# A moved/narrower path restores terrain in the previous channel as part of the
		# same operation; independent objects there must not be silently filled over.
		var previous:=Plan.new().build(old.settings,old.sources)
		if not previous.ok: return previous
		for poly in previous.envelope: envelopes.append(Plan.shape(poly,old.settings.bank_height-old.settings.water_drop-old.settings.depth-.2,old.settings.bank_height+3))
	var checks:=0
	var buildings:={}; var obstacles: Array=[]
	for r in editor._doc.records:
		if ownership.ids.has(r.uuid): continue
		if r.has("building"):
			if not buildings.has(r.building.id): buildings[r.building.id]=[]
			buildings[r.building.id].append(r)
		else: obstacles.append({"id":r.uuid,"shapes":Foot.record_shapes(r)})
	for id in buildings: obstacles.append({"id":id,"shapes":Foot.components(buildings[id],Vector3.ZERO,Basis.IDENTITY)})
	for obstacle in obstacles:
		for shape in obstacle.shapes:
			for envelope in envelopes:
				checks+=1
				if checks>1000000: return Data.fail("河道碰撞检查超过预算，请分区规划")
				if Foot.overlaps(shape,envelope): return {"ok":false,"error":"河槽、河岸、桥头或恢复地面与现有物件重叠","conflicts":[obstacle.id]}
	# Road guides reserve space even before paving. A new river cannot silently cut a planned road.
	var graph: Dictionary=Data.resolve(editor._doc.map_meta).roads; var analysis:=Data.analyze(graph)
	if not analysis.ok: return analysis
	for edge in graph.edges:
		if edge.get("bridge_ref",{}).get("waterway_id","")==settings.id: continue
		var points: Array=analysis.paths[edge.id]
		for i in points.size()-1:
			var a:=Vector2(points[i].x,points[i].z); var b:=Vector2(points[i+1].x,points[i+1].z); var n:=Vector2(-(b-a).y,(b-a).x).normalized()*maxf(edge.width_start,edge.width_end)*.5
			var shape:=Plan.shape([a-n,b-n,b+n,a+n],minf(points[i].y,points[i+1].y)-.5,maxf(points[i].y,points[i+1].y)+3)
			if Foot.batches_overlap([shape],envelopes): return Data.fail("河道与已有道路骨架相交，请先调整道路；本批不自动拆改道路图")
	var parts: Array=[]
	for r in result.records:
		if not ownership.ids.has(r.uuid) and editor._doc.has_uuid(r.uuid): return Data.fail("河道构件 ID 已被其他物件占用")
		var role: String=result.roles[r.uuid]; var material_role: String="bridge" if role=="rail" else role
		if materials.has(material_role):
			var applied:=paint(r,materials[material_role])
			if not applied.ok: return applied
		if not editor._authoring.Settings.contains(r,editor._authoring.settings): return Data.fail("生成构件落在当前隔离楼层之外")
		parts.append({"id":r.uuid,"role":role,"signature":Data.token(r)})
	if editor._doc.records.size()-ownership.ids.size()+result.records.size()>100000: return Data.fail("生成后超过地图物件上限")
	result.manifest={"version":1,"settings":settings,"sources":sources,"parts":parts}; result.excluded=ownership.ids; result.plan_token=token
	var value:=Data.resolve(editor._doc.map_meta); value.waterways=regions().filter(func(r):return r.settings.id!=settings.id); value.waterways.append(result.manifest)
	if not Data.valid({"editor_layout":value}): return Data.fail("河道记录未通过保存校验")
	result.metadata=value
	return result
func summary(args: Dictionary) -> Dictionary:
	var r:=prepare(args)
	if not r.ok: return r
	var s: Dictionary=r.manifest.settings
	return {"ok":true,"settings":s,"length":r.length,"water_area":r.area,"chunks":r.records.size(),"plan_token":r.plan_token,"outline":r.outer.map(func(p):return [p.x,p.y]),"bridges":r.crossings.map(func(b):return {"id":b.id,"endpoints":b.endpoints,"width":b.width,"polygon":b.polygon})}
func generate(args: Dictionary) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var result:=prepare(args)
	if not result.ok: return result
	if Data.token(result.metadata)==Data.token(Data.resolve(editor._doc.map_meta)): return {"ok":true,"changed":false,"chunks":result.records.size()}
	editor._doc.checkpoint_recovery(); editor._doc.records=editor._doc.records.filter(func(r):return not result.excluded.has(r.uuid)); editor._doc.records.append_array(result.records)
	editor._doc.map_meta.editor_layout=result.metadata; editor._dirty=true; editor._rebuild()
	return {"ok":true,"changed":true,"chunks":result.records.size(),"ids":result.records.map(func(r):return r.uuid)}
func remove(id: String,keep_objects: bool) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var old: Dictionary={}
	for region in regions():
		if region.settings.id==id: old=region
	if old.is_empty(): return Data.fail("河道不存在")
	if Data.resolve(editor._doc.map_meta).roads.edges.any(func(e):return e.get("bridge_ref",{}).get("waterway_id","")==id): return Data.fail("请先解除此河道桥梁的路网绑定，再删除或解除河道关联")
	var ownership:=owned(old,not keep_objects)
	if not ownership.ok: return ownership
	# Restoring original ground must not fill over independently added objects in the channel.
	if not keep_objects:
		var plan:=Plan.new().build(old.settings,old.sources)
		if not plan.ok: return plan
		for r in editor._doc.records:
			if ownership.ids.has(r.uuid): continue
			for poly in plan.envelope:
				if Foot.batches_overlap(Foot.record_shapes(r),[Plan.shape(poly,old.settings.bank_height-old.settings.water_drop-old.settings.depth,old.settings.bank_height+.05)]): return Data.fail("河槽中已有独立物件，恢复地面会覆盖它；请先移开或保留现场解除关联")
	editor._doc.checkpoint_recovery()
	if not keep_objects:
		editor._doc.records=editor._doc.records.filter(func(r):return not ownership.ids.has(r.uuid)); editor._doc.records.append_array(old.sources.duplicate(true))
	var value:=Data.resolve(editor._doc.map_meta); value.waterways=regions().filter(func(r):return r.settings.id!=id); editor._doc.map_meta.editor_layout=value; editor._dirty=true; editor._rebuild()
	return {"ok":true,"kept_objects":keep_objects,"restored_ground":0 if keep_objects else old.sources.size()}
