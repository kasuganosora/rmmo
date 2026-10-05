extends RefCounted
## Rigid building edits keep the recipe, geometry, ownership and undo in one transaction.
const Blueprint = preload("res://scripts/world3d/building_blueprint.gd")
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
const Footprint = preload("res://scripts/world_editor/building_footprint.gd")
var editor: Node3D

func fail(message: String) -> Dictionary:
	editor._status.text = message
	return {"ok":false,"error":message}

func registry() -> Dictionary: return editor._doc.map_meta.get("building_instances",{})

func expand(values: Array, allow_protected := false, skip_unavailable := false) -> Dictionary:
	var by_id := {}; var result: Array = []; var seen := {}; var buildings := {}
	for record in editor._doc.records: by_id[str(record.uuid)] = record
	for value in values:
		var id := str(value)
		if not by_id.has(id):
			if skip_unavailable: continue
			return fail("物件不存在："+id)
		var building: String = by_id[id].get("building",{}).get("id","")
		var members: Array = [id]
		if not building.is_empty() and (not editor._selection_tools.component_edit or registry().get(building,{}).get("baked",false)):
			if buildings.has(building): continue
			buildings[building] = true
			if not registry().has(building):
				if skip_unavailable: continue
				return fail("建筑登记缺失，请先修复建筑关联")
			members = registry()[building].parts.values()
		var valid := true
		for member in members:
			if not by_id.has(member) or (not allow_protected and not editor._record_editable(by_id[member])): valid=false; break
		if not valid:
			if skip_unavailable: continue
			return fail("建筑或物件包含缺失、锁定、隐藏或当前楼层之外的构件，请先显示并解锁")
		for member in members:
			if not seen.has(member): result.append(member); seen[member]=true
	return {"ok":true,"ids":result}

func selection_limit(values: Array) -> bool:
	var wanted := {}; var buildings := {}; var loose := 0
	for id in values: wanted[id] = true
	for record in editor._doc.records:
		if not wanted.has(record.uuid): continue
		var id: String = record.get("building",{}).get("id","")
		if registry().has(id) and (not editor._selection_tools.component_edit or registry()[id].get("baked",false)): buildings[id] = true
		else: loose += 1
	return loose <= 256 and buildings.size() <= 16

func units() -> Dictionary:
	var expanded := expand(editor._selection_tools.ids)
	if not expanded.ok: return expanded
	if expanded.ids.size()!=editor._selection_tools.ids.size(): return fail("请选择整栋建筑")
	var rows := {}; var selected: Array = editor._selection_tools.records()
	for record in selected:
		var id: String = record.get("building",{}).get("id","")
		if not registry().has(id): return fail("请分别操作建筑与普通物件；整栋建筑可多选")
		if not rows.has(id): rows[id] = {"id":id,"value":registry()[id],"records":[]}
		rows[id].records.append(record)
	if rows.size()>16: return fail("一次最多操作 16 栋建筑")
	return {"ok":true,"units":rows.values()}

func proposal(rows: Array, delta: Vector3, rotation: Basis, center: Vector3) -> Dictionary:
	var plans: Array = []
	var angle := rad_to_deg(atan2(rotation.z.x,rotation.z.z))
	for unit in rows:
		var old: Dictionary = unit.value
		var value: Dictionary = old.duplicate(true)
		var origin := center+rotation*(Blueprint.vec(old.position)-center)+delta
		if not origin.is_finite() or origin.abs()[origin.abs().max_axis_index()]>100000: return fail("建筑位置超出支持范围")
		value.position = Blueprint.arr(origin); value.yaw = wrapf(float(old.yaw)+angle,-180,180)
		var basis := Basis(Vector3.UP,deg_to_rad(value.yaw)); var local: Array = []; var records: Array = []
		for previous in unit.records:
			var record: Dictionary = previous.duplicate(true)
			record.position = Blueprint.arr(center+rotation*(Blueprint.vec(previous.position)-center)+delta)
			if not rotation.is_equal_approx(Basis.IDENTITY): record.rotation = Blueprint.arr((rotation*Basis.from_euler(Blueprint.vec(previous.rotation)*PI/180)).get_euler()*180/PI)
			record.building.floor_y += delta.y
			var part: String = record.building.part
			# Preserve existing hand-edit conflicts; a rigid move must not bless them.
			if Blueprint.geometry_signature(previous)==old.signatures[part]: value.signatures[part]=Blueprint.geometry_signature(record)
			records.append(record)
			var relative: Dictionary = record.duplicate(true)
			relative.position = Blueprint.arr(basis.inverse()*(Blueprint.vec(record.position)-origin))
			relative.rotation = Blueprint.arr((basis.inverse()*Basis.from_euler(Blueprint.vec(record.rotation)*PI/180)).get_euler()*180/PI)
			local.append(relative)
		plans.append({"id":unit.id,"value":value,"records":records,"occupancy":Footprint.components(local,origin,basis)})
	return {"ok":true,"plans":plans}

func clearance(plans: Array, excluded: Dictionary) -> Dictionary:
	var obstacles: Array = []
	for record in editor._doc.records:
		if not excluded.has(record.uuid):
			for shape in Footprint.record_shapes(record): obstacles.append({"id":record.uuid,"record":record,"shape":shape})
	for index in plans.size():
		var plan: Dictionary = plans[index]
		if Footprint.batches_overlap(plan.occupancy,preload("res://scripts/world3d/planning_zones.gd").obstacles(editor._doc.map_meta)): return {"ok":false,"error":"建筑进入禁建区或保留通道，已保留原位"}
		for previous in plans.slice(0,index):
			if Footprint.batches_overlap(plan.occupancy,previous.occupancy): return {"ok":false,"error":"移动后的建筑占地相互重叠"}
		for obstacle in obstacles:
			if Footprint.supporting_ground(obstacle.record,obstacle.shape.bounds.end.y,float(plan.value.position[1])): continue
			if Footprint.batches_overlap(plan.occupancy,[obstacle.shape]): return {"ok":false,"error":"建筑与现有物件重叠，已保留原位","conflicts":[obstacle.id]}
	return {"ok":true}

func move(delta: Vector3, rotation: Basis, factor: float, center: Vector3) -> Dictionary:
	if not is_equal_approx(factor,1.0) or not rotation.y.is_equal_approx(Vector3.UP): return fail("整栋建筑支持 XYZ 移动和绕 Y 轴旋转；尺寸请在建筑参数中修改，单个构件请开启构件编辑")
	var ready := units()
	if not ready.ok: return ready
	if delta.is_zero_approx() and rotation.is_equal_approx(Basis.IDENTITY): return {"ok":true,"changed":false}
	var prepared := proposal(ready.units,delta,rotation,center)
	if not prepared.ok: return prepared
	var excluded := {}
	for id in editor._selection_tools.ids: excluded[id] = true
	var checked := clearance(prepared.plans,excluded)
	if not checked.ok: editor._status.text=checked.error; return checked
	return commit(prepared.plans,false)

func duplicate_selected() -> Dictionary:
	var ready := units()
	if not ready.ok: return ready
	if registry().size()+ready.units.size()>4096: return fail("地图最多包含 4096 栋生成建筑")
	if editor._doc.records.size()+editor._selection_tools.ids.size()>100000: return fail("复制后超过地图 100000 个物件限制")
	var bounds := Geometry.bounds(editor._selection_tools.records())
	# Find a nearby clear location instead of creating a copy inside the source house.
	for ring in range(1,5):
		for axis in [Vector3.RIGHT,Vector3.LEFT,Vector3.BACK,Vector3.FORWARD]:
			var distance := (bounds.size.x if axis.x!=0 else bounds.size.z)+2.0
			var prepared := proposal(ready.units,axis*distance*ring,Basis.IDENTITY,Vector3.ZERO)
			if prepared.ok and clearance(prepared.plans,{}).ok: return commit(prepared.plans,true)
	return fail("附近没有能放下整栋副本的空地；请腾出空间后再复制")

func commit(plans: Array, copy: bool) -> Dictionary:
	var doc = editor._doc; doc.checkpoint_recovery()
	var next_registry: Dictionary = registry().duplicate(true); var replacements := {}; var selected: Array = []; var remap := {}
	for plan in plans:
		var id: String = "building_"+Crypto.new().generate_random_bytes(10).hex_encode() if copy else plan.id
		for record in plan.records:
			if copy:
				var previous: String = record.uuid; record.uuid="obj_%d"%doc._next; doc._next+=1; remap[previous]=record.uuid
			record.building.id=id; record.editor_group=id
			plan.value.parts[record.building.part]=record.uuid
			selected.append(record.uuid); replacements[record.uuid]=record
		next_registry[id]=plan.value
	if copy:
		for record in replacements.values():
			if record.has("event"): Geometry._remap_references(record.event,remap)
		doc.records.append_array(replacements.values())
	else:
		for index in doc.records.size():
			if replacements.has(doc.records[index].uuid): doc.records[index]=replacements[doc.records[index].uuid]
	doc.map_meta.building_instances=next_registry
	editor._dirty=true; editor._rebuild(); editor._selection_tools.set_ids(selected)
	if editor._building_panel!=null: editor._building_panel.refresh_list()
	return {"ok":true,"changed":true,"changed_ids":selected}

func remove() -> Dictionary:
	var ready := units()
	if not ready.ok: return ready
	var removed := {}
	for id in editor._selection_tools.ids: removed[id]=true
	editor._doc.checkpoint_recovery()
	editor._doc.records=editor._doc.records.filter(func(r): return not removed.has(r.uuid))
	for unit in ready.units: editor._doc.map_meta.building_instances.erase(unit.id)
	editor._selection_tools.ids.clear(); editor._dirty=true; editor._rebuild()
	if editor._building_panel!=null: editor._building_panel.refresh_list()
	return {"ok":true,"changed":true}
