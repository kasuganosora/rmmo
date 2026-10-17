extends "res://scripts/world_editor/residential_site_tools.gd"
## Move existing identities through a private final terrain/road candidate.
const Binding=preload("res://scripts/world_editor/residential_access_binding.gd")
const Motion=preload("res://scripts/world_editor/building_motion.gd")

class ExistingPlacement extends Placement:
	var unit:Dictionary
	var loaded:Dictionary
	func source(_p:Dictionary)->Dictionary:
		return {"ok":true,"entry":{"label":"迁移住宅"},"sha":Data.token(unit),"dependencies":{}}
	func load_source(_value:Dictionary)->Dictionary:return loaded.duplicate(true)
	func place(doc,local:Dictionary,position:Vector3,_label:String)->Dictionary:
		var origin:=Data.vec(unit.value.position)
		var angle:float=wrapf(float(local.building_instances[unit.id].yaw)-float(unit.value.yaw),-180.,180.)
		if position.abs()[position.abs().max_axis_index()]>100000:return fail("invalid_arguments","最终建筑位置超出支持范围")
		var motion:=Motion.new()
		var proposal:=motion.proposal([unit],position-origin,Basis(Vector3.UP,deg_to_rad(angle)),origin)
		if not proposal.ok:return proposal
		var plan:Dictionary=proposal.plans[0]
		var registry:Dictionary=doc.map_meta.get("building_instances",{}).duplicate(true);registry[unit.id]=plan.value
		var checked:=Prefabs.check_buildings(doc,plan.records,registry,[unit.id])
		if not checked.ok:return checked
		doc.records.append_array(plan.records);doc.map_meta.building_instances=registry
		return {"ok":true,"ids":unit.value.parts.values()}

static func relocation_schema()->Dictionary:
	var residential:=Placement.request_schema().duplicate(true)
	residential.properties.erase("asset_id");residential.required.erase("asset_id")
	residential.properties.building_id=Data.text();residential.required.append("building_id")
	residential.properties.old_access=Data.choice(["keep","remove_owned"])
	return Data.object({"residential":residential,"terrain":schema().properties.terrain},["residential"])

func preview(args:Dictionary)->Dictionary:
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	if _publishing:return fail("busy","正在发布迁移候选")
	var issue:=Data.S.validate(args,relocation_schema())
	if not issue.is_empty():return fail("invalid_arguments",issue,"relocation_request")
	var version:=_version();var request_id:=Data.token(args)
	if not _candidate.is_empty() and _candidate.request_id==request_id and _candidate.summary.base_version==version and _dependencies_current(_candidate.dependencies):return _candidate.summary.duplicate(true)
	_candidate={}
	var id:String=args.residential.building_id
	var registry:Dictionary=editor._doc.map_meta.get("building_instances",{})
	if not registry.has(id):return fail("building_not_found","已有建筑不存在")
	var value:Dictionary=registry[id];var members:Array=[]
	if not value.get("baked",false) or value.parameters.get("template")!="house" or value.parameters.get("layout") not in ["townhouse","hall"]:return fail("unsupported","当前可靠迁移支持单栋冻结 townhouse／hall 住宅")
	for part:String in value.parts:
		var record:Dictionary=editor._doc._find(value.parts[part])
		if record.is_empty() or record.get("building",{}).get("id")!=id or Blueprint.geometry_signature(record)!=value.signatures[part]:return fail("building_modified","建筑构件缺失或几何已手改，请先修复关联").merged({"conflicts":[value.parts[part]]})
		if not editor._record_editable(record):return fail("protected_scope","建筑包含锁定、隐藏或隔层构件").merged({"conflicts":[record.uuid]})
		members.append(record.duplicate(true))
	if members.is_empty():return fail("building_modified","建筑没有构件")
	var data:=Data.resolve(editor._doc.map_meta)
	if not Data.valid(editor._doc.map_meta) or editor._doc.validate_save()!=OK:return fail("candidate_invalid","原地图关联或保存校验失败")
	if data.get("block_layout",{}).get("lots",[]).any(func(l):return l.building_id==id):return fail("unsupported","自动街区管理的建筑请先解除街区归属再单栋迁移")
	if not data.has("road_surface") or data.road_surface.graph_token!=Data.token(data.roads):return fail("stale_road_surface","请先完成已有道路铺面")
	var requested_terrain:Dictionary=args.get("terrain",{})
	if not requested_terrain.get("road_nodes",[]).is_empty() and requested_terrain.get("expected_road_token","")!=Data.token(data.roads):return fail("stale_road_surface","道路草案已变化，请重新读取 road_token")
	var bridges:=BridgeContext.capture(editor,data)
	if not bridges.ok:return bridges
	var dependencies:Dictionary={};issue=_dependencies(editor._doc.records,dependencies)
	if not issue.is_empty():return fail("resource_missing",issue,"resource")
	var policy:String=args.residential.get("old_access","keep")
	var old_access:Dictionary={"policy":policy,"removed_edge_ids":[],"removed_node_ids":[],"terrain":"preserved_unless_explicitly_graded"}
	if policy=="remove_owned":
		var removal:=Binding.removal(data.roads,value,registry)
		if not removal.ok:return removal
		if removal.edge_id==args.residential.road_edge_id:return fail("invalid_arguments","新接路目标不能是将被移除的旧支路")
		data.roads.edges=data.roads.edges.filter(func(e):return e.id!=removal.edge_id)
		data.roads.nodes=data.roads.nodes.filter(func(n):return n.id!=removal.node_id)
		old_access.merge({"removed_edge_ids":[removal.edge_id],"removed_node_ids":[removal.node_id],"retained_join_id":removal.retained_join_id})
	else:old_access.notice="保留全部旧道路及旧地块；原入户路不再归属迁移后的住宅"
	# Exclude only the explicitly selected building in private staging. All
	# other buildings and followers remain native terrain/collision participants.
	var baseline:=Context.new();baseline.setup(editor)
	baseline._doc.records=baseline._doc.records.filter(func(r):return r.uuid not in value.parts.values())
	baseline._doc.map_meta.building_instances.erase(id)
	if policy=="remove_owned":
		var roads:Dictionary=baseline._roads.prepare({},data)
		if not roads.ok:baseline.free();return stage_failure(roads,"old_access")
		if Data.token(roads.graph)!=Data.token(data.roads):baseline.free();return fail("scope_conflict","旧路移除会改变其他路网连接")
		baseline._doc.records=baseline._doc.records.filter(func(r):return not roads.excluded.has(r.uuid));baseline._doc.records.append_array(roads.records)
		data.road_surface=roads.manifest;baseline._doc.map_meta.editor_layout=data
	var stage:=Context.new();stage.setup(baseline)
	var terrain:Dictionary=args.get("terrain",{}).duplicate(true);var strokes:Array=terrain.get("strokes",[])
	var steps:int=strokes.size()+(1 if terrain.has("ramp") else 0)
	if args.has("terrain") and (steps<1 or steps>MAX_STEPS):stage.free();baseline.free();return fail("invalid_arguments","可选整地需要 1–64 项操作")
	var prepared:Dictionary={"ok":true,"terrain_ids":[]};var ramp_recipe:Dictionary={}
	if steps>0:
		if terrain.has("ramp"):
			ramp_recipe=Ramp.recipe(baseline,terrain.ramp)
			if not ramp_recipe.ok:stage.free();baseline.free();return stage_failure(ramp_recipe,"terrain_ramp")
			strokes.append(ramp_recipe.stroke)
		var layout_args:=terrain.duplicate(true);layout_args.erase("ramp");layout_args.strokes=strokes
		# The public token identifies the original graph. Only after that check
		# may our private terminal removal rebase the native node-edit request.
		if not layout_args.get("road_nodes",[]).is_empty():layout_args.expected_road_token=Data.token(Data.resolve(baseline._doc.map_meta).roads)
		prepared=Layout.prepare_stage(baseline,stage,layout_args)
		if not prepared.ok:stage.free();baseline.free();return stage_failure(prepared,"terrain")
		if not ramp_recipe.is_empty():
			var proof:=Ramp.prove(baseline._doc,stage._doc,terrain.ramp,ramp_recipe,prepared.terrain_ids)
			if not proof.ok:stage.free();baseline.free();return stage_failure(proof,"terrain_ramp")
			prepared.ramp=proof
	var earthwork:=Ramp.earthwork(editor._doc,stage._doc,prepared.terrain_ids)
	var core:=ExistingPlacement.new();core.editor=stage;core.unit={"id":id,"value":value.duplicate(true),"records":members}
	var local_value:=value.duplicate(true);local_value.position=[0.,0.,0.];local_value.erase("residential_access")
	core.loaded={"ok":true,"records":_translated(members,-Data.vec(value.position)),"building_instances":{id:local_value}}
	var request:Dictionary=args.residential.duplicate(true);request.erase("building_id");request.erase("old_access");request.asset_id=id
	var house:=core.preview(request)
	if not house.ok:stage.free();baseline.free();return stage_failure(house,"relocation")
	stage._doc.apply_recovery(core._candidate.after)
	var preserved:=BridgeContext.verify(stage._doc,Data.resolve(stage._doc.map_meta),bridges)
	if not preserved.ok:stage.free();baseline.free();return preserved
	if stage._doc.validate_save()!=OK:stage.free();baseline.free();return fail("candidate_invalid","迁移最终候选保存校验失败")
	for path:String in core._candidate.dependencies:
		if dependencies.has(path) and dependencies[path]!=core._candidate.dependencies[path]:stage.free();baseline.free();return fail("source_changed","准备期间资源变化")
		dependencies[path]=core._candidate.dependencies[path]
	var changes:=delta(editor._doc,stage._doc);var changed:Array=changes.added+changes.updated+changes.removed
	var visual:Array=stage._doc.records.filter(func(r):return r.uuid in changed)
	var final_dependencies:Dictionary={};issue=_dependencies(visual,final_dependencies)
	if not issue.is_empty():stage.free();baseline.free();return fail("resource_missing",issue,"resource")
	for path:String in final_dependencies:
		if dependencies.has(path) and dependencies[path]!=final_dependencies[path]:stage.free();baseline.free();return fail("source_changed","准备期间资源变化")
		dependencies[path]=final_dependencies[path]
	var old_bounds:=Geometry.bounds(members);var bounds:=Geometry.bounds(visual).merge(old_bounds)
	var summary:=house.duplicate(true)
	summary.merge({"plan_token":Crypto.new().generate_random_bytes(24).hex_encode(),"base_version":version,"changed_ids":changed,"changes":changes,"earthwork":earthwork,"terrain":Layout.public_result(prepared),"terrain_operation_count":steps,"relocation":{"building_id":id,"from_position":value.position,"from_yaw":value.yaw,"old_access":old_access,"identity_preserved":true},"bounds":{"position":Data.xyz(bounds.position),"size":Data.xyz(bounds.size)}},true)
	summary.checks.final_combined_save=true;summary.checks.existing_identity=true
	var after:Dictionary=stage._doc.recovery_snapshot();stage.free();baseline.free()
	if _version()!=version or not _dependencies_current(dependencies):return fail("base_changed","地图或资源变化，请重新预览")
	_candidate={"summary":summary,"request_id":request_id,"dependencies":dependencies,"after":after,"integrity":Data.token(after),"visual":visual}
	return summary.duplicate(true)
