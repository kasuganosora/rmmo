extends RefCounted
## Closed record transforms remain authoritative. Hinges are local to each member,
## so moving, rotating and copying the complete house cannot leave pivots behind.
const Schema = preload("res://scripts/world3d/document_schema.gd")

static func vec(a: Array) -> Vector3: return Vector3(a[0],a[1],a[2])
static func arr(v: Vector3) -> Array: return [v.x,v.y,v.z]

static func valid(record: Dictionary) -> bool:
	if not record.has("fixture"): return true
	var schema := {"type":"object","properties":{
		"id":{"type":"string","minLength":1,"maxLength":180},
		"kind":{"type":"string","enum":["door","window","shutter"]},
		"pivot":Schema.vector(-100,100),"angle":Schema.number(-180,180),
		"open":Schema.number(0,1)},"required":["id","kind","pivot","angle","open"],"additionalProperties":false}
	return record.get("kind")=="box" and Schema.validate(record.fixture,schema).is_empty() and not str(record.fixture.id).is_empty()

static func pose(closed: Transform3D, fixture: Dictionary, amount: float) -> Transform3D:
	var pivot := vec(fixture.pivot)
	var turn := Basis(Vector3.UP,deg_to_rad(float(fixture.angle)*amount))
	return closed*Transform3D(turn,pivot-turn*pivot)

static func transform(record: Dictionary) -> Transform3D:
	var closed := Transform3D(Basis.from_euler(vec(record.rotation)*PI/180),vec(record.position))
	return pose(closed,record.fixture,float(record.fixture.open)) if record.has("fixture") else closed

static func attach(plan: Dictionary, first: int, id: String, kind: String, pivot: Vector3, angle: float, amount: float) -> void:
	for i in range(first,plan.records.size()):
		var record: Dictionary=plan.records[i]
		var basis:=Basis.from_euler(vec(record.rotation)*PI/180)
		record.fixture={"id":id,"kind":kind,"pivot":arr(basis.inverse()*(pivot-vec(record.position))),"angle":angle,"open":amount}

static func rows(records: Array, building_id: String) -> Array:
	if building_id.is_empty(): return []
	var groups := {}
	for record in records:
		if owner_id(record)!=building_id or not record.has("fixture"): continue
		var f: Dictionary=record.fixture
		if not groups.has(f.id): groups[f.id]={"id":f.id,"kind":f.kind,"open":f.open,"angle":f.angle,"floor":record.get("building",{}).get("floor",0),"members":[]}
		groups[f.id].members.append(record.uuid)
	return groups.values()

static func owner_id(record: Dictionary) -> String:
	if record.has("fortification"): return "fortification:"+str(record.fortification.id)
	return str(record.get("building",{}).get("id",""))

static func list_runtime(map_root: Node, building_id: String) -> Array:
	var records: Array=[]
	for spec in map_root.get_meta("stream_library",[]):
		var extra: Dictionary=spec.extras
		if extra.has("fixture"): records.append(extra)
	return rows(records,building_id)

static func set_runtime(map_root: Node, building_id: String, id: String, amount: float, duration := .35) -> Dictionary:
	if building_id.is_empty(): return {"ok":false,"error":"建筑编号不能为空"}
	if not is_finite(amount) or amount<0 or amount>1 or not is_finite(duration) or duration<0 or duration>10:
		return {"ok":false,"error":"开合值必须为 0～1，动画时长必须为 0～10 秒"}
	var members: Array=[]
	for spec in map_root.get_meta("stream_library",[]):
		if owner_id(spec.extras)==building_id and spec.extras.get("fixture",{}).get("id","")==id: members.append(spec)
	if members.is_empty(): return {"ok":false,"error":"门窗组件不存在（请先完成地图流式索引）"}
	var key:=building_id+":"+id
	var tweens: Dictionary=map_root.get_meta("fixture_tweens",{})
	if tweens.has(key) and is_instance_valid(tweens[key]): tweens[key].kill()
	var from: float=members[0].extras.fixture.open
	if duration==0 or is_equal_approx(from,amount): _apply_runtime(map_root,members,amount)
	else:
		var tween:=map_root.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tweens[key]=tween
		tween.tween_method(func(value): _apply_runtime(map_root,members,value),from,amount,duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	map_root.set_meta("fixture_tweens",tweens)
	return {"ok":true,"building_id":building_id,"id":id,"open":amount}

static func _apply_runtime(map_root: Node, members: Array, amount: float) -> void:
	for spec in members:
		var f: Dictionary=spec.extras.fixture
		f.open=amount
		spec.transform=pose(spec.closed_transform,f,amount)
		spec.position=spec.transform.origin
		for bag in ["stream_meshes","stream_bodies"]:
			var node: Node3D=map_root.get_meta(bag,{}).get(spec.uuid)
			if is_instance_valid(node):
				node.global_transform=spec.transform
				if bag=="stream_bodies": node.set_meta("center",spec.position)

static func prepare_spec(spec: Dictionary) -> void:
	if not spec.extras.has("fixture"): return
	var f: Dictionary=spec.extras.fixture
	# Undo the current pose to recover the closed transform from an exported node.
	spec.closed_transform=spec.transform*pose(Transform3D.IDENTITY,f,float(f.open)).affine_inverse()
	# Every possible hinge angle is indexed, including when a leaf crosses a chunk.
	var pivot: Vector3=spec.closed_transform*vec(f.pivot)
	var radius:=0.0
	for i in 8: radius=maxf(radius,(spec.closed_transform*spec.mesh.get_aabb().get_endpoint(i)).distance_to(pivot))
	var Stream=load("res://scripts/world3d/world_stream.gd")
	spec.chunk_min=Stream.chunk_key(pivot-Vector3.ONE*radius)
	spec.chunk_max=Stream.chunk_key(pivot+Vector3.ONE*radius)

static func bake_snapshot(record: Dictionary) -> void:
	record.erase("fortification")
	if not record.has("fixture"): return
	var current:=transform(record)
	record.position=arr(current.origin); record.rotation=arr(current.basis.get_euler()*180/PI)
	record.erase("fixture")
