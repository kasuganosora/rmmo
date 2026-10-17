extends RefCounted
const Data=preload("res://scripts/world3d/city_layout.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Footprint=preload("res://scripts/world_editor/building_footprint.gd")
var editor: Node3D
## Local opt-in diagnostics; never part of author records or MCP arguments.
var profile_enabled:=false
var last_profile:Dictionary={}
var _profile_phase:=""
var _profile_started:=0

static func _same(left:Variant,right:Variant)->bool:
	# JSON reload can change int zero into float zero and dictionary insertion
	# order. Compare every authored field exactly; never round geometry or use
	# an epsilon when deciding whether an existing record can be retained.
	if left is Array:
		if not right is Array or left.size()!=right.size():return false
		for i in left.size():
			if not _same(left[i],right[i]):return false
		return true
	if left is Dictionary:
		if not right is Dictionary or left.size()!=right.size():return false
		for key:Variant in left:
			if not right.has(key) or not _same(left[key],right[key]):return false
		return true
	if typeof(left)!=typeof(right):
		if not ((left is int or left is float) and (right is int or right is float)):return false
		var integer:int=left if left is int else right
		var decimal:float=left if left is float else right
		# Outside the exact-integer double domain, conservatively rebuild
		# instead of allowing a rounded conversion to hide a real change.
		if integer < -9007199254740992 or integer > 9007199254740992 or not is_finite(decimal):return false
		return float(integer)==decimal
	return left==right

func _profile_next(stage:String)->void:
	if not profile_enabled:return
	var now:=Time.get_ticks_usec()
	if not _profile_phase.is_empty():
		last_profile.stages_ms[_profile_phase]=float(last_profile.stages_ms.get(_profile_phase,0.))+(now-_profile_started)/1000.
	_profile_phase=stage;_profile_started=now

static func _flat_terrain_xz(record:Dictionary)->Variant:
	# Only an identity heightfield has XZ bounds independent of heights and
	# cultivation. Tilt/yaw and other footprint kinds keep the exact old path.
	if not record.has("terrain_mesh") or record.has("rock_bank"):return null
	for angle:float in record.rotation:
		if angle!=0.:return null
	for value:float in record.position+record.size:
		if not is_finite(value):return null
	if record.size.any(func(value):return value<=0.):return null
	var terrain=preload("res://scripts/world3d/terrain_surface.gd")
	var pose:Transform3D=terrain.transform(record)
	if pose.basis!=Basis.IDENTITY:return null
	var first:Vector3=pose*terrain.point(record,0,0)
	var last:Vector3=pose*terrain.point(record,int(record.terrain_mesh.columns),int(record.terrain_mesh.rows))
	# Native float32 AABB expansion and Rect2 end reconstruction can round
	# outwards. Pad in world scale so a boundary obstacle is never culled.
	var pad:=8.*pow(2.,-23.)*(maxf(absf(pose.origin.x),absf(pose.origin.z))+maxf(record.size[0],record.size[2])+1.)
	return Rect2(Vector2(first.x,first.z),Vector2(last.x-first.x,last.z-first.z)).grow(pad)

static func _terrain_unneeded(record:Dictionary,roads:Array,bounds_cache:Dictionary)->bool:
	if not record.has("terrain_mesh"):return false
	var bounds:Variant=_flat_terrain_xz(record)
	for index in roads.size():
		var road:Dictionary=roads[index]
		# This exemption belongs to each projected road, never to the map.
		if road.has("terrain_follow") and record.uuid in road.terrain_follow.terrain_ids:continue
		if bounds==null:return false
		if not bounds_cache.has(index):
			var shapes:=Footprint.record_shapes(road)
			var occupied:AABB=shapes[0].bounds
			for shape:Dictionary in shapes:occupied=occupied.merge(shape.bounds)
			# Cache only coarse rectangles for this prepare call. Keeping every
			# road's exact polygons here would increase peak temporary residency.
			bounds_cache[index]=Rect2(occupied.position.x,occupied.position.z,occupied.size.x,occupied.size.z).grow(.001)
		if bounds_cache[index].intersects(bounds,true):return false
	return true

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

func prepare(args: Dictionary, override_data:Dictionary={}) -> Dictionary:
	last_profile={"stages_ms":{},"counts":{}} if profile_enabled else {}
	_profile_phase=""
	var started:=Time.get_ticks_usec() if profile_enabled else 0
	_profile_next("source_validation")
	var result:=_prepare(args,override_data)
	_profile_next("") # Include the active phase even when validation returns early.
	if profile_enabled:
		last_profile.total_ms=(Time.get_ticks_usec()-started)/1000.
		last_profile.ok=result.get("ok",false)
	return result

func _prepare(args: Dictionary, override_data:Dictionary={}) -> Dictionary:
	var settings:=Plan.defaults(); settings.merge(Data.resolve(editor._doc.map_meta).get("road_surface",{}).get("settings",{}),true); var changes:=args.duplicate(true); changes.erase("plan_token"); settings.merge(changes,true)
	var data:=Data.resolve(editor._doc.map_meta) if override_data.is_empty() else override_data; var old: Dictionary=data.get("road_surface",{}); var by_key:={}; var excluded:={}
	for part in old.get("parts",[]):
		var record: Dictionary=editor._doc._find(part.id)
		if record.is_empty() or record.get("road_source","")!=part.key or Surface.signature(record)!=part.signature: return Data.fail("道路铺面已被手改或删除；请恢复修改，或解除铺面关联后自行处理")
		if not editor._record_editable(record): return Data.fail("道路铺面包含锁定、隐藏或隔层构件")
		by_key[part.key]=part; excluded[part.id]=true
	for edge in data.roads.edges+data.roads.nodes:
		if edge.get("hidden",false) or edge.get("locked",false): return Data.fail("生成前请显示并解锁道路骨架")
	_profile_next("intersection_split")
	if settings.kerb_enabled:
		var connected:=preload("res://scripts/world3d/road_intersections.gd").split(data.roads)
		if not connected.ok:return connected
		data=data.duplicate(true);data.roads=connected.graph
	_profile_next("bridge_bindings")
	var binding:=preload("res://scripts/world3d/road_bridges.gd").resolve(data)
	if not binding.ok: return binding
	for portal in binding.portals:
		if portal.get("road_stone",false):
			var bound_lift:float=data.get("road_surface",{}).get("settings",{}).get("lift",.025)
			if absf(settings.lift-bound_lift)>.000001:return Data.fail("已绑定桥梁的道路铺面偏移不能单独改变，请先撤销桥梁转换")
			var checked: Dictionary=preload("res://scripts/world_editor/bridge_road_tools.gd").verify(editor,portal)
			if not checked.ok: return checked
			continue
		if absf(settings.lift-.025)>.000001: return Data.fail("河道配方接桥道路须使用 0.025 米铺面偏移以保持桥头齐平")
		for region in data.get("waterways",[]):
			if region.settings.id==portal.reference.waterway_id:
				var owner: Dictionary=editor._waterways.owned(region)
				if not owner.ok: return owner
	_profile_next("road_build")
	var result:=Plan.build(data.roads,settings,binding.portals)
	if not result.ok: return result
	_profile_next("terrain_fit")
	if settings.follow_terrain:
		var terrains:Array=editor._doc.records.filter(func(r):return r.has("terrain_mesh"))
		var fitted:=preload("res://scripts/world3d/road_terrain_fit.gd").fit(result.records,terrains,settings.lift,Paint.MAX_OVERRIDES if not settings.material_id.is_empty() else 0)
		if not fitted.ok:return fitted
		result.records=fitted.records;result.chunks=fitted.chunks
	_profile_next("material_lookup")
	var material_ids: Array=[]
	if not settings.material_id.is_empty():material_ids.append(settings.material_id)
	if settings.kerb_enabled:material_ids.append(settings.kerb_material_id)
	var materials: Dictionary=editor._material_tool.library.find_many(material_ids)
	var material: Dictionary={}
	if not settings.material_id.is_empty():
		material=materials.get(settings.material_id,{})
		if material.is_empty(): return Data.fail("所选铺路材质不存在")
	var kerb_material:Dictionary={}
	if settings.kerb_enabled:
		kerb_material=materials.get(settings.kerb_material_id,{})
		if kerb_material.is_empty() or not Paint.material_valid(kerb_material) or kerb_material.color[3]!=1 or not Paint.missing([{"road_kerb_material":kerb_material}]).is_empty():return Data.fail("路缘材质不存在或贴图依赖缺失")
	_profile_next("record_preservation")
	var manifest:={"version":1,"settings":settings,"graph_token":Data.token(data.roads),"parts":[]}
	var seen:={}; var added:=0; var updated:=0; var unchanged:=0
	for record_index in result.records.size():
		var record:Dictionary=result.records[record_index]
		if not editor._authoring.Settings.contains(record,editor._authoring.settings): return Data.fail("道路铺面落在当前隔离楼层外")
		var key: String=record.road_source; seen[key]=true
		record.uuid=by_key[key].id if by_key.has(key) else "pavement_"+key.sha256_text().left(20)
		if not by_key.has(key) and editor._doc.has_uuid(record.uuid): return Data.fail("道路构件 ID 已被其他物件占用")
		if record.road_mesh.has("kerbs"):record.road_kerb_material=kerb_material.duplicate(true)
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
			if _same(record,previous):
				# Preserve exact author bytes, including JSON numeric types and
				# dictionary order, without aliasing the live editable document.
				result.records[record_index]=previous.duplicate(true)
				unchanged+=1
			else: updated+=1
		else: added+=1
		manifest.parts.append({"key":key,"id":record.uuid,"signature":Surface.signature(record),"paint_signature":automatic})
	for key in by_key:
		if seen.has(key): continue
		var part: Dictionary=by_key[key]; var record: Dictionary=editor._doc._find(part.id)
		if record.has("event_template") or record.has("event") or Data.token(record.get("surface_paint",[]))!=part.paint_signature: return Data.fail("将移除的道路构件上有手刷材质或事件")
	_profile_next("obstacle_shapes")
	if profile_enabled:last_profile.counts={"source_records":editor._doc.records.size(),"road_records":result.records.size(),"obstacle_records_expanded":0,"terrain_records_skipped":0}
	# Avoid expanding only terrain that every road can safely exclude. Keep
	# original document/shape conflict order and no cache across author edits.
	var terrain_road_bounds:Dictionary={}
	# Actual convex occupied patches, not cell AABBs, protect courtyards and empty corners.
	var obstacles: Array=[]
	for record in editor._doc.records:
		if excluded.has(record.uuid): continue
		if record.has("fortification") and record.has("fixture"): continue # A gate controls road traffic; its open/closed pose is intentional.
		if record.has("terrain_mesh") and _terrain_unneeded(record,result.records,terrain_road_bounds):
			if profile_enabled:last_profile.counts.terrain_records_skipped+=1
			continue
		if profile_enabled:last_profile.counts.obstacle_records_expanded+=1
		for shape in Footprint.record_shapes(record): obstacles.append({"record":record,"shape":shape})
	if profile_enabled:
		last_profile.counts.obstacle_shapes=obstacles.size()
		last_profile.counts.potential_shape_pairs=obstacles.size()*result.records.size()
	_profile_next("collision")
	var bridge_collision_cache:Dictionary={}
	var asset_contact_cache:Dictionary={}
	for record in result.records:
		var occupancy:=Footprint.record_shapes(record)
		var occupied_bounds:AABB=occupancy[0].bounds
		for shape:Dictionary in occupancy:occupied_bounds=occupied_bounds.merge(shape.bounds)
		var occupied_xz:=Rect2(occupied_bounds.position.x,occupied_bounds.position.z,occupied_bounds.size.x,occupied_bounds.size.z).grow(.001)
		for obstacle in obstacles:
			# Projection already validated this exact supporting heightfield.
			# This was previously checked after O(road faces * terrain cells)
			# clipping; move the identical exemption before those intersections.
			if record.has("terrain_follow") and obstacle.record.uuid in record.terrain_follow.terrain_ids:continue
			var obstacle_bounds:AABB=obstacle.shape.bounds
			if not occupied_xz.intersects(Rect2(obstacle_bounds.position.x,obstacle_bounds.position.z,obstacle_bounds.size.x,obstacle_bounds.size.z),true):continue
			var support:=false
			for shape in occupancy:
				var overlap:=Plan.intersection(Array(shape.polygon).slice(0,-1),Array(obstacle.shape.polygon).slice(0,-1))
				if overlap.is_empty(): continue
				var foot:=INF; var grade: Array=record.road_mesh.get("grade",[0,0])
				for p in overlap: foot=minf(foot,record.position[1]+record.size[1]*.5-settings.lift+grade[0]*(p.x-record.position[0])+grade[1]*(p.y-record.position[2]))
				support=Footprint.supporting_ground(obstacle.record,obstacle.shape.bounds.end.y,foot)
				if not support: break
			if support: continue
			if Footprint.batches_overlap(occupancy,[obstacle.shape]):
				if obstacle.record.has("house_prefab") and not preload("res://scripts/world3d/frozen_road_contact.gd").intersects(record,obstacle.record,occupancy,obstacle.shape,asset_contact_cache):continue
				if obstacle.record.get("kind")=="asset" and not preload("res://scripts/world3d/asset_road_contact.gd").intersects(record,obstacle.record,occupancy,obstacle.shape,asset_contact_cache):continue
				if obstacle.record.has("bridge_mesh") and not preload("res://scripts/world3d/road_bridge_approach.gd").intersects(record,obstacle.record,occupancy,obstacle.shape,bridge_collision_cache):continue
				return {"ok":false,"error":"路面或通行净空与现有物件重叠","conflicts":[obstacle.record.uuid]}
	_profile_next("finalize")
	if editor._doc.records.size()-excluded.size()+result.records.size()>100000: return Data.fail("生成后超过地图物件上限")
	result.manifest=manifest; result.excluded=excluded;result.graph=data.roads
	result.diff={"added":added,"updated":updated,"unchanged":unchanged,"removed":by_key.size()+added-result.records.size()}
	# IDs alone do not identify externally editable material descriptors.
	result.plan_token=JSON.stringify([settings,data.roads,editor._doc.records,old,material,kerb_material]).sha256_text()
	return result

func paint_default(record: Dictionary, material: Dictionary) -> Dictionary:
	# Preparation needs author face IDs, not a renderable mesh or materials.
	# Keep the exact generator arrays for every slot and all paint validation.
	var cpu:=preload("res://scripts/world3d/ground_cpu_mesh.gd").new()
	_profile_next("paint_arrays")
	cpu.surfaces=Surface.arrays(record)
	var node:=MeshInstance3D.new();node.set_meta("paint_source",cpu)
	_profile_next("paint_geometry")
	var geometry:=Paint.geometry(node,true); node.free()
	_profile_next("paint_entries")
	if not geometry.ok: return geometry
	var surface: Dictionary=geometry.surfaces[0]; var entries: Array=[]; var tile: Array=material.get("tile_size",[1,1])
	if surface.faces.size()>Paint.MAX_OVERRIDES:return {"ok":false,"code":"road_paint_face_limit","error":"单块路面需要 %d 个刷面，超过 %d 个预算"%[surface.faces.size(),Paint.MAX_OVERRIDES]}
	for face in surface.faces:
		entries.append({"mesh":".","surface":0,"face":face,"geometry":surface.signature,"material":material.duplicate(true),"mapping":"uv","scale":[1.0/tile[0],1.0/tile[1]],"offset":[0,0],"rotation":0.0})
	record.surface_paint=entries
	_profile_next("paint_validation")
	var valid:=Paint.valid(record)
	_profile_next("paint_dependencies")
	var missing:=Paint.missing([record]) if valid else []
	_profile_next("record_preservation")
	return {"ok":true} if valid and missing.is_empty() else Data.fail("路面材质无效或贴图依赖缺失")

func summary(args: Dictionary) -> Dictionary:
	var result:=prepare(args)
	if not result.ok: return result
	return {"ok":true,"chunks":result.chunks,"area":result.area,"kerb_length":result.kerb_length,"diff":result.diff,"plan_token":result.plan_token,"graph_token":result.manifest.graph_token}

func generate(args: Dictionary) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var result:=prepare(args)
	if not result.ok: return result
	if args.has("plan_token") and args.plan_token!=result.plan_token: return Data.fail("道路方案或现有物件已改变，请重新预览")
	if result.diff.added==0 and result.diff.updated==0 and result.diff.removed==0 and _same(Data.resolve(editor._doc.map_meta).get("road_surface",{}),result.manifest): return {"ok":true,"changed":false,"diff":result.diff}
	editor._doc.checkpoint_recovery()
	var data:=Data.resolve(editor._doc.map_meta)
	apply_prepared(result,data)
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

func apply_prepared(result:Dictionary,data:Dictionary)->void:
	var changed:Array[String]=[]
	for record in result.records:
		if record!=editor._doc._find(record.uuid):changed.append(record.uuid)
	var present:Dictionary={}
	for record in result.records:present[record.uuid]=true
	for id in result.excluded:
		if not present.has(id):changed.append(id)
	editor._doc.records=editor._doc.records.filter(func(r):return not result.excluded.has(r.uuid))
	editor._doc.records.append_array(result.records)
	data.roads=result.graph;data.road_surface=result.manifest;editor._doc.map_meta.editor_layout=data
	editor._dirty=true;editor._refresh_records(changed)
	editor._selection_tools.invalidate_pivot();editor._refresh_selection(false)
	editor._object_list.refresh();editor._city.refresh()

func geometry_token(graph:Dictionary)->String:
	var copy:=graph.duplicate(true)
	for item in copy.nodes+copy.edges:
		for field in ["name","locked","hidden"]:item.erase(field)
	return Data.token(copy)
