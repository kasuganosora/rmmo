extends RefCounted
## Preview first, then replace the complete batch in one recovery transaction.
const Blueprint = preload("res://scripts/world3d/building_blueprint.gd")
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
const Schema = preload("res://scripts/world3d/document_schema.gd")
const Footprint = preload("res://scripts/world_editor/building_footprint.gd")
const Street = preload("res://scripts/world_editor/building_street.gd")
const Region = preload("res://scripts/world_editor/building_region.gd")
var editor: Node3D

static func placement_schema() -> Dictionary:
	return {"type":"object","properties":{"position":Schema.vector(-100000,100000),"yaw":Schema.number(-180,180),"seed_offset":{"type":"integer","minimum":0,"maximum":100000},"parameters":Blueprint.schema()},"required":["position"],"additionalProperties":false}

static func batch_schema() -> Dictionary:
	return {"type":"object","properties":{"parameters":Blueprint.schema(),"placements":{"type":"array","items":placement_schema(),"minItems":1,"maxItems":16}},"required":["placements"],"additionalProperties":false}

func instances() -> Dictionary: return editor._doc.map_meta.get("building_instances",{})
func templates() -> Dictionary:
	var rows: Array = []
	for id in Blueprint.LABELS:
		var value := Blueprint.defaults(); value.template = id
		if id=="inn": value.rooms_per_floor = 3
		rows.append({"id":id,"name":Blueprint.LABELS[id],"parameters":value})
	return {"ok":true,"templates":rows,"presets":Blueprint.medieval_presets(),"urban_presets":Blueprint.urban_presets(),"parameters_schema":Blueprint.schema(),"region_schema":Region.schema(),"max_batch":16}

func list_buildings() -> Dictionary:
	var rows: Array = []
	for id in instances():
		var value: Dictionary = instances()[id]
		rows.append({"id":id,"parameters":value.parameters,"position":value.position,"yaw":value.yaw,"part_count":value.parts.size(),"conflicts":conflicts(id)})
	return {"ok":true,"buildings":rows}

func conflicts(id: String) -> Array:
	var result: Array = []
	if not instances().has(id): return ["建筑不存在"]
	var value: Dictionary = instances()[id]
	for part in value.parts:
		var record: Dictionary = editor._doc._find(value.parts[part])
		if record.is_empty(): result.append({"part":part,"reason":"构件已被删除"}); continue
		if record.get("building",{}).get("id")!=id or Blueprint.geometry_signature(record)!=value.signatures[part]: result.append({"id":record.uuid,"part":part,"reason":"构件已手工改动"})
		elif not editor._record_editable(record): result.append({"id":record.uuid,"part":part,"reason":"构件被锁定、隐藏或不在当前楼层"})
	return result

func prepare(args: Dictionary, replacing := "") -> Dictionary:
	var issue := Schema.validate(args,batch_schema())
	if not issue.is_empty(): return Blueprint.fail(issue)
	if replacing.is_empty() and instances().size()+args.placements.size()>4096: return Blueprint.fail("地图最多包含 4096 栋生成建筑")
	var prepared: Array = []; var excluded: Array = []
	var occupied_shapes := {}
	if not replacing.is_empty():
		if args.placements.size()!=1: return Blueprint.fail("更新预览只能包含一栋建筑")
		if not instances().has(replacing): return Blueprint.fail("建筑不存在")
		var blocked := conflicts(replacing)
		if not blocked.is_empty(): return {"ok":false,"error":"建筑存在修改或保护冲突；请先解决，或解除生成关联后手工编辑","conflicts":blocked}
		excluded = instances()[replacing].parts.values()
	for index in args.placements.size():
		var placement: Dictionary = args.placements[index]
		var parameters: Dictionary = instances()[replacing].parameters.duplicate(true) if not replacing.is_empty() else {}
		parameters.merge(args.get("parameters",{}),true)
		parameters.merge(placement.get("parameters",{}),true)
		parameters.seed = int(parameters.get("seed",1))+int(placement.get("seed_offset",0))
		var plan := Blueprint.generate(parameters)
		if not plan.ok: return plan
		if plan.records.size()>2000: return Blueprint.fail("单栋建筑超过 2000 个构件，请减少层数或装饰")
		var origin := Blueprint.vec(placement.position); var yaw := float(placement.get("yaw",0))
		var basis := Basis(Vector3.UP,deg_to_rad(yaw))
		plan.occupancy = Footprint.components(plan.records,origin,basis)
		for record in plan.records:
			record.position = Blueprint.arr(origin+basis*Blueprint.vec(record.position))
			var orientation := basis*Basis.from_euler(Blueprint.vec(record.rotation)*PI/180)
			record.rotation = Blueprint.arr(orientation.get_euler()*180/PI)
			record.building.floor_y += origin.y
		plan.position = placement.position.duplicate(); plan.yaw = yaw
		plan.entrance = Blueprint.arr(origin+basis*Blueprint.vec(plan.entrance))
		var box := Geometry.bounds(plan.records)
		plan.bounds = {"position":Blueprint.arr(box.position),"size":Blueprint.arr(box.size)}
		for previous in prepared:
			if Footprint.batches_overlap(plan.occupancy,previous.occupancy): return Blueprint.fail("本批第 %d 栋建筑与另一栋建筑占地重叠"%(index+1))
		for record in editor._doc.records:
			if excluded.has(str(record.uuid)): continue
			if not occupied_shapes.has(record.uuid): occupied_shapes[record.uuid]=Footprint.record_shape(record)
			var occupied: AABB = occupied_shapes[record.uuid].bounds
			# Existing terrain below the specified foot plane supports the building.
			if occupied.end.y<=origin.y+.005: continue
			if Footprint.batches_overlap(plan.occupancy,[occupied_shapes[record.uuid]]): return {"ok":false,"error":"第 %d 栋建筑占地与现有物件重叠"%(index+1),"conflicts":[str(record.uuid)]}
		if not replacing.is_empty():
			var old: Dictionary = instances()[replacing]
			var new_parts := {}
			for record in plan.records: new_parts[record.building.part] = record
			for part in old.parts:
				var record: Dictionary = editor._doc._find(old.parts[part])
				var decorated: bool = record.has("surface_paint") or record.has("event_template") or record.has("event")
				if decorated and (not new_parts.has(part) or Blueprint.geometry_signature(new_parts[part])!=old.signatures[part]): return {"ok":false,"error":"修改会影响已绘制材质或挂载事件的构件，原建筑已保留","conflicts":[record.uuid]}
		prepared.append(plan)
	var total: int = editor._doc.records.size()-excluded.size()
	for plan in prepared: total += plan.records.size()
	if total>100000: return Blueprint.fail("生成后超过地图 100000 个物件限制，请拆分地图")
	return {"ok":true,"plans":prepared}

func summary(result: Dictionary) -> Dictionary:
	if not result.ok: return result
	var rows: Array = []
	for plan in result.plans:
		rows.append({"parameters":plan.parameters,"position":plan.position,"yaw":plan.yaw,"bounds":plan.bounds,"part_count":plan.records.size(),"entrance":plan.entrance,"rooms":plan.rooms,"openings":plan.openings,"stairs":plan.stairs,"courtyards":plan.get("courtyards",[]),"connections":plan.get("connections",[]),"terraces":plan.get("terraces",[]),"service_zones":plan.get("service_zones",[])})
	var response := {"ok":true,"buildings":rows,"layout_coordinates":"rooms/openings/stairs/courtyards/terraces/service_zones are building-local meters; position/yaw transform them to world space; entrance/bounds are world space"}
	if result.has("street"): response.street=result.street
	if result.has("region"): response.region=result.region; response.plan_token=result.plan_token
	return response

func prepare_region(args: Dictionary) -> Dictionary:
	var result := Region.plan(args,editor._doc.records)
	if not result.ok: return result
	if args.has("plan_token") and args.plan_token!=result.plan_token: return Blueprint.fail("区域或已有物体已改变，原预览方案不能直接应用，请重新预览")
	var prepared := prepare(result.request)
	if prepared.ok: prepared.region=result.region; prepared.plan_token=result.plan_token
	return prepared

func generate_region(args: Dictionary) -> Dictionary:
	var ready: Dictionary=editor._gameplay.guard()
	if not ready.ok: return ready
	var prepared := prepare_region(args)
	if not prepared.ok: return prepared
	var result := commit(prepared.plans)
	result.region=prepared.region; result.plan_token=prepared.plan_token
	return result

func prepare_street(args: Dictionary) -> Dictionary:
	var result := Street.plan(args)
	if not result.ok: return result
	var prepared := prepare(result.request)
	if prepared.ok: prepared.street=result.street
	return prepared

func generate_street(args: Dictionary) -> Dictionary:
	var ready: Dictionary = editor._gameplay.guard()
	if not ready.ok: return ready
	var prepared := prepare_street(args)
	if not prepared.ok: return prepared
	var result := commit(prepared.plans); result.street=prepared.street
	return result

func generate(args: Dictionary) -> Dictionary:
	var ready: Dictionary = editor._gameplay.guard()
	if not ready.ok: return ready
	var result := prepare(args)
	if not result.ok: return result
	return commit(result.plans)

func update(id: String, changes: Dictionary, position: Variant = null, yaw: Variant = null) -> Dictionary:
	var ready: Dictionary = editor._gameplay.guard()
	if not ready.ok: return ready
	if not instances().has(id): return Blueprint.fail("建筑不存在")
	var old: Dictionary = instances()[id]
	var parameters: Dictionary = old.parameters.duplicate(true); parameters.merge(changes,true)
	var placement := {"position":old.position if position==null else position,"yaw":old.yaw if yaw==null else yaw}
	var result := prepare({"parameters":parameters,"placements":[placement]},id)
	if not result.ok: return result
	if parameters==old.parameters and placement.position==old.position and placement.yaw==old.yaw: return {"ok":true,"changed":false,"building_ids":[id]}
	return commit(result.plans,id)

func commit(plans: Array, replacing := "") -> Dictionary:
	var doc = editor._doc
	doc.checkpoint_recovery()
	var registry: Dictionary = instances().duplicate(true)
	var old: Dictionary = registry.get(replacing,{})
	var previous := {}
	for id in old.get("parts",{}).values(): previous[id] = doc._find(id).duplicate(true)
	if not replacing.is_empty(): doc.records = doc.records.filter(func(r): return not previous.has(r.uuid))
	var ids: Array = []
	for plan in plans:
		var id: String = replacing if not replacing.is_empty() else "building_"+Crypto.new().generate_random_bytes(10).hex_encode()
		var value := {"version":Blueprint.VERSION,"parameters":plan.parameters,"position":plan.position,"yaw":plan.yaw,"parts":{},"signatures":{}}
		for generated in plan.records:
			var record: Dictionary = generated.duplicate(true); var part: String = record.building.part
			var previous_id: String = old.get("parts",{}).get(part,"")
			if previous_id.is_empty():
				record.uuid = "obj_%d"%doc._next; doc._next += 1
			else:
				record.uuid = previous_id
				for key in ["surface_paint","event_template","event","editor_name"]:
					if previous[previous_id].has(key): record[key] = previous[previous_id][key]
			record.building.id = id; record.editor_group = id; record.editor_group_name = Blueprint.LABELS[plan.parameters.template]
			value.parts[part] = record.uuid; value.signatures[part] = Blueprint.geometry_signature(record)
			doc.records.append(record)
		registry[id] = value; ids.append(id)
	doc.map_meta.building_instances = registry
	editor._dirty = true; editor._rebuild()
	if editor._building_panel!=null: editor._building_panel.refresh_list(ids[0])
	return {"ok":true,"changed":true,"building_ids":ids,"object_count":doc.records.size()}

func remove(id: String, detach := false) -> Dictionary:
	var ready: Dictionary = editor._gameplay.guard()
	if not ready.ok: return ready
	if not instances().has(id): return Blueprint.fail("建筑不存在")
	var owned: Array = instances()[id].parts.values()
	for record in editor._doc.records:
		if not owned.has(record.uuid): continue
		if record.get("building",{}).get("id")!=id: return Blueprint.fail("建筑构件归属不一致，未修改地图")
		if not editor._record_editable(record): return Blueprint.fail("建筑中有锁定、隐藏或当前楼层之外的构件")
	editor._doc.checkpoint_recovery()
	if detach:
		for record in editor._doc.records:
			if owned.has(record.uuid): record.erase("building")
	else: editor._doc.records = editor._doc.records.filter(func(r): return not owned.has(r.uuid))
	editor._doc.map_meta.building_instances.erase(id)
	editor._dirty = true; editor._rebuild()
	if editor._building_panel!=null: editor._building_panel.refresh_list()
	return {"ok":true,"changed":true,"building_id":id,"detached":detach}
