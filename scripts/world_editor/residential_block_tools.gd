extends "res://scripts/world_editor/residential_site_tools.gd"
## Ordered, bounded final-state candidate. Never applies child tools to live state.
const Relocation=preload("res://scripts/world_editor/residential_relocation_tools.gd")
const Binding=preload("res://scripts/world_editor/residential_access_binding.gd")
const MAX_HOMES:=16

static func block_schema()->Dictionary:
	var residential:=Placement.request_schema().duplicate(true)
	residential.required.erase("asset_id")
	residential.properties.building_id=Data.text()
	residential.properties.old_access=Data.choice(["keep","remove_owned"])
	return Data.object({"homes":Data.array(Data.object({"id":Data.text(),"residential":residential},["id","residential"]),MAX_HOMES,1),"terrain":schema().properties.terrain},["homes"])

static func row_failure(result:Dictionary,row:Dictionary,index:int,stage:String)->Dictionary:
	return stage_failure(result,stage).merged({"home_id":row.id,"home_index":index,"requested_position":row.residential.position,"position":result.get("position",row.residential.position)})

func preview(args:Dictionary)->Dictionary:
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	if _publishing:return fail("busy","正在发布街区候选")
	var issue:=Data.S.validate(args,block_schema())
	if not issue.is_empty():return fail("invalid_arguments",issue,"block_request")
	var version:=_version();var request_id:=Data.token(args)
	if not _candidate.is_empty() and _candidate.request_id==request_id and _candidate.summary.base_version==version and _dependencies_current(_candidate.dependencies):return _candidate.summary.duplicate(true)
	_candidate={}
	var baseline:=Context.new();baseline.setup(editor)
	var stage:=Context.new()
	var result:=prepare(args,baseline,stage)
	stage.free();baseline.free()
	if not result.ok:return result
	if _version()!=version or not _dependencies_current(result.dependencies):return fail("base_changed","地图或资源变化，请重新预览")
	result.summary.base_version=version
	_candidate={"summary":result.summary,"request_id":request_id,"dependencies":result.dependencies,"after":result.after,"integrity":Data.token(result.after),"visual":result.visual}
	return result.summary.duplicate(true)

func prepare(args:Dictionary,baseline:Node3D,stage:Node3D)->Dictionary:
	var data:=Data.resolve(editor._doc.map_meta)
	if not Data.valid(editor._doc.map_meta) or editor._doc.validate_save()!=OK:return fail("candidate_invalid","原地图关联或保存校验失败")
	if not data.has("road_surface") or data.road_surface.graph_token!=Data.token(data.roads):return fail("stale_road_surface","请先完成已有道路铺面")
	var terrain:Dictionary=args.get("terrain",{}).duplicate(true)
	var strokes:Array=terrain.get("strokes",[]);var steps:int=strokes.size()+(1 if terrain.has("ramp") else 0)
	if args.has("terrain") and (steps<1 or steps>MAX_STEPS):return fail("invalid_arguments","可选整地需要 1–64 项操作")
	if not terrain.get("road_nodes",[]).is_empty() and terrain.get("expected_road_token","")!=Data.token(data.roads):return fail("stale_road_surface","道路草案已变化，请重新读取 road_token")
	var bridges:=BridgeContext.capture(editor,data)
	if not bridges.ok:return bridges
	var dependencies:Dictionary={};var issue:=_dependencies(editor._doc.records,dependencies)
	if not issue.is_empty():return fail("resource_missing",issue,"resource")
	var units:Dictionary={};var row_ids:Dictionary={};var removed_edges:Array=[];var removed_nodes:Array=[];var removed_parts:Array=[];var old_access:Dictionary={}
	var registry:Dictionary=editor._doc.map_meta.get("building_instances",{})
	# Inspect every source and receipt against the original graph before removing
	# ANY moving house. This permits swaps without waiving other participants.
	for i in args.homes.size():
		var row:Dictionary=args.homes[i];var p:Dictionary=row.residential
		if row.id.strip_edges().is_empty() or row_ids.has(row.id):return row_failure(fail("invalid_arguments","每户 id 必须非空且唯一"),row,i,"block_request")
		row_ids[row.id]=true
		if p.has("asset_id")==p.has("building_id") or (p.has("asset_id") and p.has("old_access")):return row_failure(fail("invalid_arguments","每户必须且只能指定 asset_id 或 building_id；old_access 仅适用于迁移"),row,i,"block_request")
		var target:=_target(data.roads,p.road_edge_id)
		if not target.ok:return row_failure(target,row,i,"road_target")
		if not p.has("building_id"):continue
		if units.has(p.building_id):return row_failure(fail("invalid_arguments","同一建筑不能在候选中重复迁移"),row,i,"block_request")
		var inspected:=Relocation.inspect_unit(editor,p.building_id)
		if not inspected.ok:return row_failure(inspected,row,i,"relocation_source")
		units[p.building_id]=inspected.unit;removed_parts.append_array(inspected.unit.value.parts.values())
		var policy:String=p.get("old_access","keep")
		old_access[p.building_id]={"policy":policy,"removed_edge_ids":[],"removed_node_ids":[],"terrain":"preserved_unless_explicitly_graded"}
		if policy=="remove_owned":
			var removal:=Binding.removal(data.roads,inspected.unit.value,registry)
			if not removal.ok:return row_failure(removal,row,i,"old_access")
			removed_edges.append(removal.edge_id);removed_nodes.append(removal.node_id)
			old_access[p.building_id].merge({"removed_edge_ids":[removal.edge_id],"removed_node_ids":[removal.node_id],"retained_join_id":removal.retained_join_id},true)
		else:old_access[p.building_id].notice="全部旧路保留；原入户路解除住宅归属"
	for i in args.homes.size():
		if args.homes[i].residential.road_edge_id in removed_edges:return row_failure(fail("invalid_arguments","接路目标属于本组将移除的旧支路"),args.homes[i],i,"old_access")
	baseline._doc.records=baseline._doc.records.filter(func(r):return r.uuid not in removed_parts)
	for id:String in units:baseline._doc.map_meta.building_instances.erase(id)
	if not removed_edges.is_empty():
		data.roads.edges=data.roads.edges.filter(func(e):return e.id not in removed_edges)
		data.roads.nodes=data.roads.nodes.filter(func(n):return n.id not in removed_nodes)
		var roads:Dictionary=baseline._roads.prepare({},data)
		if not roads.ok:return stage_failure(roads,"old_access")
		if Data.token(roads.graph)!=Data.token(data.roads):return fail("scope_conflict","旧路移除会改变其他路网连接")
		baseline._doc.records=baseline._doc.records.filter(func(r):return not roads.excluded.has(r.uuid));baseline._doc.records.append_array(roads.records)
		data.road_surface=roads.manifest;baseline._doc.map_meta.editor_layout=data
	stage.setup(baseline)
	var prepared:Dictionary={"ok":true,"terrain_ids":[]}
	if steps>0:
		var recipe:Dictionary={}
		if terrain.has("ramp"):
			recipe=Ramp.recipe(baseline,terrain.ramp)
			if not recipe.ok:return stage_failure(recipe,"terrain_ramp")
			strokes.append(recipe.stroke)
		var layout_args:=terrain.duplicate(true);layout_args.erase("ramp");layout_args.strokes=strokes
		if not layout_args.get("road_nodes",[]).is_empty():layout_args.expected_road_token=Data.token(Data.resolve(baseline._doc.map_meta).roads)
		prepared=Layout.prepare_stage(baseline,stage,layout_args)
		if not prepared.ok:return stage_failure(prepared,"terrain")
		if not recipe.is_empty():
			var proof:=Ramp.prove(baseline._doc,stage._doc,terrain.ramp,recipe,prepared.terrain_ids)
			if not proof.ok:return stage_failure(proof,"terrain_ramp")
			prepared.ramp=proof
	var earthwork:=Ramp.earthwork(editor._doc,stage._doc,prepared.terrain_ids)
	var lineage:Dictionary={};var homes:Array=[];var house_ids:Array=[];var building_ids:Array=[]
	for edge:Dictionary in Data.resolve(stage._doc.map_meta).roads.edges:lineage[edge.id]=[edge.id]
	for i in args.homes.size():
		var row:Dictionary=args.homes[i];var p:Dictionary=row.residential.duplicate(true)
		var core:Placement=Placement.new()
		if p.has("building_id"):
			var unit:Dictionary=units[p.building_id]
			core=Relocation.ExistingPlacement.new();core.unit=unit
			var local_value:Dictionary=unit.value.duplicate(true);local_value.position=[0.,0.,0.];local_value.erase("residential_access")
			core.loaded={"ok":true,"records":_translated(unit.records,-Data.vec(unit.value.position)),"building_instances":{unit.id:local_value}}
			p.asset_id=p.building_id;p.erase("building_id");p.erase("old_access")
		core.editor=stage;core.target_edges=lineage.get(p.road_edge_id,[]).duplicate()
		if core.target_edges.is_empty():return row_failure(fail("road_not_found","共享整地后目标道路已变化，请重新指定"),row,i,"road_target")
		var house:=core.preview(p)
		if not house.ok:return row_failure(house,row,i,"residential")
		for path:String in core._candidate.dependencies:
			if dependencies.has(path) and dependencies[path]!=core._candidate.dependencies[path]:return fail("source_changed","准备期间资源变化")
			dependencies[path]=core._candidate.dependencies[path]
		stage._doc.apply_recovery(core._candidate.after)
		var connection:Dictionary=house.road_connection
		# Update only this original edge's descendants, in parameter order.
		if connection.split:
			var family:Array=lineage[p.road_edge_id];var index:=family.find(connection.edge_id)
			family.insert(index+1,connection.child_edge_ids[1])
		house.erase("plan_token");house.erase("base_version")
		house.id=row.id;house.requested_road_edge_id=p.road_edge_id
		house.operation="relocate" if row.residential.has("building_id") else "place"
		if house.operation=="relocate":house.relocation={"building_id":house.building_id,"from_position":units[house.building_id].value.position,"from_yaw":units[house.building_id].value.yaw,"old_access":old_access[house.building_id],"identity_preserved":true}
		homes.append(house);house_ids.append_array(house.house_ids);building_ids.append(house.building_id)
	var final:=verify_final(stage,homes,args.homes)
	if not final.ok:return final
	var preserved:=BridgeContext.verify(stage._doc,Data.resolve(stage._doc.map_meta),bridges)
	if not preserved.ok:return preserved
	if stage._doc.validate_save()!=OK:return fail("candidate_invalid","街区最终候选保存校验失败")
	var changes:=delta(editor._doc,stage._doc);var changed:Array=changes.added+changes.updated+changes.removed
	var visual:Array=stage._doc.records.filter(func(r):return r.uuid in changed)
	var final_dependencies:Dictionary={};issue=_dependencies(visual,final_dependencies)
	if not issue.is_empty():return fail("resource_missing",issue,"resource")
	for path:String in final_dependencies:
		if dependencies.has(path) and dependencies[path]!=final_dependencies[path]:return fail("source_changed","准备期间资源变化")
		dependencies[path]=final_dependencies[path]
	var bounds:=Geometry.bounds(visual+editor._doc.records.filter(func(r):return r.uuid in removed_parts))
	var summary:Dictionary={"ok":true,"plan_token":Crypto.new().generate_random_bytes(24).hex_encode(),"homes":homes,"building_ids":building_ids,"house_ids":house_ids,"changed_ids":changed,"changes":changes,"earthwork":earthwork,"terrain":Layout.public_result(prepared),"terrain_operation_count":steps,"road_lineage":lineage,"bridges":bridges.summary,"bounds":{"position":Data.xyz(bounds.position),"size":Data.xyz(bounds.size)},"checks":{"final_house_geometry":true,"final_per_house_access":true,"final_combined_save":true,"bridge_context":true,"runtime_traversal":"requires_runtime_verification"},"publication":{"authoring":"single_synchronous_transaction","derived":"native_refresh_and_shared_batches"}}
	return {"ok":true,"summary":summary,"after":stage._doc.recovery_snapshot(),"dependencies":dependencies,"visual":visual}

static func verify_final(stage:Node3D,homes:Array,rows:Array)->Dictionary:
	var graph:Dictionary=Data.resolve(stage._doc.map_meta).roads
	var registry:Dictionary=stage._doc.map_meta.building_instances
	var road_records:Array=stage._doc.records.filter(func(r):return r.has("road_source"))
	for i in homes.size():
		var house:Dictionary=homes[i];var value:Dictionary=registry[house.building_id]
		var members:Array=stage._doc.records.filter(func(r):return r.uuid in house.house_ids)
		var without:=Doc.new();without.apply_recovery(stage._doc.recovery_snapshot());without.records=without.records.filter(func(r):return r.uuid not in house.house_ids)
		var geometry:=Prefabs.check_buildings(without,members,registry,[house.building_id])
		if not geometry.ok:return row_failure(geometry.merged({"code":"placement_conflict"}),rows[i],i,"final_geometry")
		var receipt:=Binding.removal(graph,value,registry)
		if not receipt.ok:return row_failure(receipt,rows[i],i,"final_connection")
		var entry:=Access.entrance(members,float(value.yaw))
		if not entry.ok:return row_failure(entry,rows[i],i,"final_entrance")
		var access:=Access.check(stage._doc,members,entry,Data.vec(house.road_points[0]),house.width)
		if not access.ok:return row_failure(access,rows[i],i,"final_entrance")
		# Later road splits regenerate kerbs. Check all final kerbs both against
		# the house envelope and its whole door-to-road walking corridor.
		# Native low kerbs are traversable steps, not full-height blockers. The
		# corridor uses the minimum terrain height plus the conservative step
		# limit; house/fixture clearance below retains the full kerb volume.
		var occupied:=Foot.components(members,Vector3.ZERO,Basis.IDENTITY)
		var corridor:=Access._polygon(entry,0.,house.setback)
		var ground:=Support.terrain_region(stage._doc,corridor)
		if not ground.ok:return row_failure(ground,rows[i],i,"final_entrance")
		var points:Array[Vector3]=[]
		for point:Vector2 in corridor:
			points.append(Vector3(point.x,ground.height_range[0]+Access.STEP_LIMIT,point.y));points.append(Vector3(point.x,maxf(ground.height_range[1],entry.floor_y)+1.8,point.y))
		occupied.append(Foot.from_points(points))
		# Recheck this block against every final kerb. Unchanged, distant
		# road/object pairs are outside this final per-house proof; changed
		# roads already passed the shared native preparation against all objects.
		for road:Dictionary in road_records:
			for kerb:Dictionary in _kerb_shapes(road):
				if Foot.batches_overlap([kerb],occupied):return row_failure(fail("kerb_conflict","最终路缘侵入本户住宅、门窗或超过通行台阶上限").merged({"conflicts":[road.uuid]}),rows[i],i,"final_road_clearance")
		var connector:=_connector_ground(stage._doc,{"points":house.road_points},house.width)
		if not connector.ok:return row_failure(connector,rows[i],i,"final_connection")
		access.connector_ground=connector
		house.access=access;house.checks.final_block=true
	return {"ok":true}
