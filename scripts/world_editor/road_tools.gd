extends RefCounted
const Data=preload("res://scripts/world3d/city_layout.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Footprint=preload("res://scripts/world_editor/building_footprint.gd")
var editor: Node3D

func split() -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var graph: Dictionary=Data.resolve(editor._doc.map_meta).roads
	var solved:=preload("res://scripts/world3d/road_intersections.gd").split(graph)
	if not solved.ok: return solved
	var result: Dictionary=editor._city.update_roads({"expected_token":Data.token(graph),"nodes":solved.graph.nodes,"edges":solved.graph.edges})
	result.added_nodes=solved.added_nodes; result.added_edges=solved.added_edges
	return result

func zones(args: Dictionary) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var value:=Data.resolve(editor._doc.map_meta); var old: Array=value.get("zones",[])
	if args.expected_token!=JSON.stringify(old).sha256_text(): return Data.fail("保留区已经变化，请重新读取 zone_token")
	var table:={}; var touched:={}
	for zone in old: table[zone.id]=zone
	for id in args.get("remove",[]):
		if not table.has(id) or touched.has(id): return Data.fail("保留区不存在或 ID 重复")
		if table[id].get("locked",false) or table[id].get("hidden",false): return Data.fail("先解锁并显示保留区")
		touched[id]=true; table.erase(id)
	for zone in args.get("zones",[]):
		if touched.has(zone.id): return Data.fail("同次修改不能重复保留区 ID")
		touched[zone.id]=true
		if table.has(zone.id) and (table[zone.id].get("locked",false) or table[zone.id].get("hidden",false)):
			var a: Dictionary=table[zone.id].duplicate(true); var b: Dictionary=zone.duplicate(true)
			for flag in ["locked","hidden"]: a.erase(flag); b.erase(flag)
			a.name=a.get("name",""); b.name=b.get("name","")
			if a!=b: return Data.fail("先单独解锁并显示保留区，再修改形状")
		table[zone.id]=zone.duplicate(true)
	value.zones=table.values()
	if not preload("res://scripts/world3d/planning_zones.gd").valid(value.zones): return Data.fail("保留区需为无自交的简单多边形，面积至少 1 平方米，且高度范围有效")
	return editor._city.commit(value)

func prepare(args: Dictionary) -> Dictionary:
	var settings:=Plan.defaults(); settings.merge(Data.resolve(editor._doc.map_meta).get("road_surface",{}).get("settings",{}),true); var changes:=args.duplicate(true); changes.erase("plan_token"); settings.merge(changes,true)
	var data:=Data.resolve(editor._doc.map_meta); var old: Dictionary=data.get("road_surface",{}); var by_key:={}; var excluded:={}
	for part in old.get("parts",[]):
		var record: Dictionary=editor._doc._find(part.id)
		if record.is_empty() or record.get("road_source","")!=part.key or Surface.signature(record)!=part.signature: return Data.fail("道路铺面已被手改或删除；请恢复修改，或解除铺面关联后自行处理")
		if not editor._record_editable(record): return Data.fail("道路铺面包含锁定、隐藏或隔层构件")
		by_key[part.key]=part; excluded[part.id]=true
	for edge in data.roads.edges+data.roads.nodes:
		if edge.get("hidden",false) or edge.get("locked",false): return Data.fail("生成前请显示并解锁道路骨架")
	var binding:=preload("res://scripts/world3d/road_bridges.gd").resolve(data)
	if not binding.ok: return binding
	for portal in binding.portals:
		if absf(settings.lift-.025)>.000001: return Data.fail("接桥道路须使用 0.025 米铺面偏移以保持桥头齐平")
		for region in data.get("waterways",[]):
			if region.settings.id==portal.reference.waterway_id:
				var owner: Dictionary=editor._waterways.owned(region)
				if not owner.ok: return owner
	var result:=Plan.build(data.roads,settings,binding.portals)
	if not result.ok: return result
	var material: Dictionary={}
	if not settings.material_id.is_empty():
		material=editor._material_tool.library.find(settings.material_id)
		if material.is_empty(): return Data.fail("所选铺路材质不存在")
	var manifest:={"version":1,"settings":settings,"graph_token":Data.token(data.roads),"parts":[]}
	var seen:={}; var added:=0; var updated:=0; var unchanged:=0
	for record in result.records:
		if not editor._authoring.Settings.contains(record,editor._authoring.settings): return Data.fail("道路铺面落在当前隔离楼层外")
		var key: String=record.road_source; seen[key]=true
		record.uuid=by_key[key].id if by_key.has(key) else "pavement_"+key.sha256_text().left(20)
		if not by_key.has(key) and editor._doc.has_uuid(record.uuid): return Data.fail("道路构件 ID 已被其他物件占用")
		if not material.is_empty():
			var painted:=paint_default(record,material)
			if not painted.ok: return painted
		var automatic:=Data.token(record.get("surface_paint",[]))
		if by_key.has(key):
			var previous: Dictionary=editor._doc._find(record.uuid)
			var custom: bool=Data.token(previous.get("surface_paint",[]))!=by_key[key].paint_signature
			var decorated: bool=custom or previous.has("event_template") or previous.has("event")
			if decorated and Surface.signature(record)!=by_key[key].signature: return Data.fail("路面改变会覆盖手刷材质或事件，已保留原道路")
			if custom:
				if previous.has("surface_paint"): record.surface_paint=previous.surface_paint.duplicate(true)
				else: record.erase("surface_paint")
			for field in ["event_template","event","editor_name","editor_group","editor_group_name"]:
				if previous.has(field): record[field]=previous[field]
			if record==previous: unchanged+=1
			else: updated+=1
		else: added+=1
		manifest.parts.append({"key":key,"id":record.uuid,"signature":Surface.signature(record),"paint_signature":automatic})
	for key in by_key:
		if seen.has(key): continue
		var part: Dictionary=by_key[key]; var record: Dictionary=editor._doc._find(part.id)
		if record.has("event_template") or record.has("event") or Data.token(record.get("surface_paint",[]))!=part.paint_signature: return Data.fail("将移除的道路构件上有手刷材质或事件")
	# Actual convex occupied patches, not cell AABBs, protect courtyards and empty corners.
	var obstacles: Array=[]
	for record in editor._doc.records:
		if excluded.has(record.uuid): continue
		if record.has("fortification") and record.has("fixture"): continue # A gate controls road traffic; its open/closed pose is intentional.
		for shape in Footprint.record_shapes(record): obstacles.append({"record":record,"shape":shape})
	for record in result.records:
		var occupancy:=Footprint.record_shapes(record)
		for obstacle in obstacles:
			var support:=false
			for shape in occupancy:
				var overlap:=Plan.intersection(Array(shape.polygon).slice(0,-1),Array(obstacle.shape.polygon).slice(0,-1))
				if overlap.is_empty(): continue
				var foot:=INF; var grade: Array=record.road_mesh.get("grade",[0,0])
				for p in overlap: foot=minf(foot,record.position[1]+record.size[1]*.5-settings.lift+grade[0]*(p.x-record.position[0])+grade[1]*(p.y-record.position[2]))
				support=Footprint.supporting_ground(obstacle.record,obstacle.shape.bounds.end.y,foot)
				if not support: break
			if support: continue
			if Footprint.batches_overlap(occupancy,[obstacle.shape]): return {"ok":false,"error":"路面或通行净空与现有物件重叠","conflicts":[obstacle.record.uuid]}
	if editor._doc.records.size()-excluded.size()+result.records.size()>100000: return Data.fail("生成后超过地图物件上限")
	result.manifest=manifest; result.excluded=excluded
	result.diff={"added":added,"updated":updated,"unchanged":unchanged,"removed":by_key.size()+added-result.records.size()}
	result.plan_token=JSON.stringify([settings,data.roads,editor._doc.records,old]).sha256_text()
	return result

func paint_default(record: Dictionary, material: Dictionary) -> Dictionary:
	var node:=MeshInstance3D.new(); node.mesh=Surface.mesh(record,null)
	var geometry:=Paint.geometry(node); node.free()
	if not geometry.ok: return geometry
	var surface: Dictionary=geometry.surfaces[0]; var entries: Array=[]; var tile: Array=material.get("tile_size",[1,1])
	for face in surface.faces:
		entries.append({"mesh":".","surface":0,"face":face,"geometry":surface.signature,"material":material.duplicate(true),"mapping":"uv","scale":[1.0/tile[0],1.0/tile[1]],"offset":[0,0],"rotation":0.0})
	record.surface_paint=entries
	return {"ok":true} if Paint.valid(record) and Paint.missing([record]).is_empty() else Data.fail("路面材质依赖缺失或单块刷面数量超限")

func summary(args: Dictionary) -> Dictionary:
	var result:=prepare(args)
	if not result.ok: return result
	return {"ok":true,"chunks":result.chunks,"area":result.area,"diff":result.diff,"plan_token":result.plan_token,"graph_token":result.manifest.graph_token}

func generate(args: Dictionary) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var result:=prepare(args)
	if not result.ok: return result
	if args.has("plan_token") and args.plan_token!=result.plan_token: return Data.fail("道路方案或现有物件已改变，请重新预览")
	if result.diff.added==0 and result.diff.updated==0 and result.diff.removed==0 and Data.resolve(editor._doc.map_meta).get("road_surface",{})==result.manifest: return {"ok":true,"changed":false,"diff":result.diff}
	editor._doc.checkpoint_recovery()
	editor._doc.records=editor._doc.records.filter(func(r):return not result.excluded.has(r.uuid))
	editor._doc.records.append_array(result.records)
	var data:=Data.resolve(editor._doc.map_meta); data.road_surface=result.manifest; editor._doc.map_meta.editor_layout=data
	editor._dirty=true; editor._rebuild()
	return {"ok":true,"changed":true,"chunks":result.chunks,"diff":result.diff,"ids":result.records.map(func(r):return r.uuid)}

func detach() -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var data:=Data.resolve(editor._doc.map_meta)
	if not data.has("road_surface"): return Data.fail("当前没有生成的路面")
	for part in data.road_surface.parts:
		var record: Dictionary=editor._doc._find(part.id)
		if not record.is_empty() and not editor._record_editable(record): return Data.fail("请先显示并解锁全部道路构件")
	editor._doc.checkpoint_recovery()
	for part in data.road_surface.parts:
		var record: Dictionary=editor._doc._find(part.id)
		if not record.is_empty(): record.erase("road_source")
	data.erase("road_surface"); editor._doc.map_meta.editor_layout=data; editor._dirty=true; editor._city.refresh()
	return {"ok":true}
