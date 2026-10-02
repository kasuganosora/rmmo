extends RefCounted
const Data=preload("res://scripts/world3d/city_layout.gd")
const Blocks=preload("res://scripts/world3d/city_blocks.gd")
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const Footprint=preload("res://scripts/world_editor/building_footprint.gd")
const Region=preload("res://scripts/world_editor/building_region.gd")
const Zones=preload("res://scripts/world3d/planning_zones.gd")
var editor: Node3D
var overlay_plan: Dictionary={}

func catalog() -> Dictionary:
	var data:=Data.resolve(editor._doc.map_meta); var result:=Blocks.extract(data.roads)
	if not result.ok: return result
	result.bindings=data.get("block_layout",{}).get("lots",[])
	result.settings=data.get("block_layout",{}).get("settings",Blocks.defaults())
	var ids: Array=result.blocks.map(func(b):return b.id)
	result.orphaned_blocks=[]
	for binding in result.bindings:
		if not ids.has(binding.block_id) and not result.orphaned_blocks.has(binding.block_id): result.orphaned_blocks.append(binding.block_id)
	return result

static func volume(poly: Array, low: float, high: float) -> Dictionary:
	var points: Array[Vector3]=[]
	for p in poly: points.append(Vector3(p[0],low,p[1])); points.append(Vector3(p[0],high,p[1]))
	return Footprint.from_points(points)

func prepare(args: Dictionary) -> Dictionary:
	var issue:=Data.S.validate(args,Blocks.request_schema())
	if not issue.is_empty(): return Data.fail(issue)
	var data:=Data.resolve(editor._doc.map_meta); var catalog_:=catalog()
	if not catalog_.ok: return catalog_
	var settings:=Blocks.defaults(); settings.merge(catalog_.settings,true)
	for key in settings:
		if args.has(key): settings[key]=args[key]
	var selected: Array=args.get("block_ids",catalog_.blocks.map(func(b):return b.id))
	if selected.is_empty(): return Data.fail("没有闭合街区；请绘制环路并拆分路口")
	var ids:={}
	for block in catalog_.blocks: ids[block.id]=block
	var seen:={}
	for id in selected:
		if not ids.has(id) or seen.has(id): return Data.fail("街区不存在或重复，请重新识别街区")
		if ids[id].protected: return Data.fail("街区边界包含隐藏或锁定的道路，请先显示并解锁")
		seen[id]=true
	var bindings: Array=catalog_.bindings.duplicate(true); var by_lot:={}
	for binding in bindings:
		by_lot[binding.lot_id]=binding
		if selected.has(binding.block_id) and binding.source_token!=Blocks.source_token(ids[binding.block_id],settings):
			return Data.fail("道路边界或地块尺寸已改变；先解除该街区的地块关联，现有房屋会保留")
	var plans: Array=[]; var lots: Array=[]; var skipped:=0; var obstacles: Array=[]
	for record in editor._doc.records:
		for shape in Footprint.record_shapes(record): obstacles.append({"record":record,"shape":shape})
	var zones:=Zones.obstacles(editor._doc.map_meta); var occupied: Array=[]
	var selected_blocks: Array=[]
	for id in selected:
		var block: Dictionary=ids[id]; selected_blocks.append(block)
		var parcels:=Blocks.lots(block,catalog_.blocks,data.roads,settings)
		if not parcels.ok: return parcels
		skipped+=parcels.skipped_corners
		for lot in parcels.lots:
			lots.append(lot)
			if lots.size()>1024: return Data.fail("预览超过 1024 地块，请选择较少街区")
			if by_lot.has(lot.id):
				lot.building_id=by_lot[lot.id].building_id
				lot.status="retained" if editor._buildings.instances().has(lot.building_id) else "missing"
				continue
			var reservation:=volume(lot.polygon,block.height-1.2,block.height+40)
			if Footprint.batches_overlap([reservation],zones): lot.status="reserved"; continue
			if blocked([reservation],obstacles,block.height,false) or Footprint.batches_overlap([reservation],occupied): lot.status="occupied"; continue
			if plans.size()>=settings.max_buildings: lot.status="pending"; continue
			var rng:=RandomNumberGenerator.new(); rng.seed=(lot.id+str(settings.seed)).sha256_text().left(15).hex_to_int()
			var accepted:=false
			for attempt in 8:
				var parameters:=Region.variant(settings.style,Vector2(settings.lot_width-.4,settings.lot_depth-.4),rng,attempt==7)
				var building:=Blueprint.generate(parameters)
				if not building.ok: continue
				var bounds:=Footprint.local_bounds(building.records).expand(Blueprint.vec(building.entrance))
				if bounds.size.x>settings.lot_width-.4 or bounds.size.z>settings.lot_depth-.4: continue
				var basis:=Basis(Vector3.UP,deg_to_rad(lot.yaw))
				var origin:=Data.vec(lot.position)+basis*Vector3(-bounds.get_center().x,0,.2-bounds.position.z)
				var entrance:=origin+basis*Blueprint.vec(building.entrance)
				var street:=Data.vec(lot.street); var nearest:=INF
				for front in block.frontages:
					if front.edge_id!=lot.edge_id: continue
					for i in front.path.size()-1:
						var a:=Data.vec(front.path[i]); var b:=Data.vec(front.path[i+1])
						var point:=Geometry2D.get_closest_point_to_segment(Vector2(entrance.x,entrance.z),Vector2(a.x,a.z),Vector2(b.x,b.z))
						var distance_:=point.distance_squared_to(Vector2(entrance.x,entrance.z))
						if distance_<nearest: nearest=distance_; street=Vector3(point.x,block.height,point.y)
				var delta:=entrance-street; var side:=Vector3(-delta.z,0,delta.x).normalized()*1.05
				var access_poly: Array=[]
				for p in [street-side,entrance-side,entrance+side,street+side]: access_poly.append([p.x,p.z])
				var access:=volume(access_poly,block.height+.06,block.height+3)
				# Road pavement is allowed beneath the connection, all props and zones remain blockers.
				if blocked([access],obstacles,block.height,true) or Footprint.batches_overlap([access],zones) or Footprint.batches_overlap([access],occupied): lot.status="access_blocked"; continue
				var placement:={"parameters":building.parameters,"position":Data.xyz(origin),"yaw":lot.yaw}
				var prepared: Dictionary=editor._buildings.prepare({"placements":[placement]})
				if not prepared.ok: lot.status="occupied"; continue
				var plan: Dictionary=prepared.plans[0]
				if Footprint.batches_overlap(plan.occupancy,occupied): continue
				plan.instance_id="building_"+lot.id.trim_prefix("lot_")
				var suffix:=2
				while editor._buildings.instances().has(plan.instance_id):
					plan.instance_id="building_"+lot.id.trim_prefix("lot_")+"_"+str(suffix); suffix+=1
				plans.append(plan); occupied.append(reservation); occupied.append(access)
				lot.status="ready"; lot.building_id=plan.instance_id; lot.entrance=Data.xyz(entrance); lot.access=[Data.xyz(street),Data.xyz(entrance)]
				lot.building_bounds=plan.bounds
				lot.building_position=plan.position; lot.parameters=plan.parameters
				lot.building_polygon=[]
				for point in [Vector3(bounds.position.x,0,bounds.position.z),Vector3(bounds.end.x,0,bounds.position.z),Vector3(bounds.end.x,0,bounds.end.z),Vector3(bounds.position.x,0,bounds.end.z)]:
					var world: Vector3=origin+basis*point; lot.building_polygon.append([world.x,world.z])
				bindings.append({"lot_id":lot.id,"block_id":block.id,"building_id":plan.instance_id,"source_token":Blocks.source_token(block,settings)})
				accepted=true; break
			if not accepted and lot.status=="vacant": lot.status="too_small"
	if bindings.size()>4096 or editor._buildings.instances().size()+plans.size()>4096: return Data.fail("地块关联或建筑数量超过 4096")
	var total: int=editor._doc.records.size()
	for plan in plans: total+=plan.records.size()
	if total>100000: return Data.fail("生成后超过地图物件上限")
	var token:=Data.token([settings,selected,data,editor._doc.records,editor._doc.map_meta.get("building_instances",{})])
	if args.has("plan_token") and args.plan_token!=token: return Data.fail("预览后地图或参数已变化，请重新预览")
	return {"ok":true,"plans":plans,"lots":lots,"blocks":selected_blocks,"skipped_corners":skipped,"settings":settings,"plan_token":token,"manifest":{"version":1,"settings":settings,"lots":bindings},"orphaned_blocks":catalog_.orphaned_blocks}

func blocked(shapes: Array, obstacles: Array, foot: float, access: bool) -> bool:
	for obstacle in obstacles:
		if access and obstacle.record.has("road_mesh") and Footprint.Geometry.bounds([obstacle.record]).end.y<=foot+.06: continue
		if Footprint.supporting_ground(obstacle.record,obstacle.shape.bounds.end.y,foot): continue
		if Footprint.batches_overlap(shapes,[obstacle.shape]): return true
	return false

func summary(args: Dictionary) -> Dictionary:
	var result:=prepare(args)
	if not result.ok: return result
	result.building_count=result.plans.size(); result.erase("plans"); result.erase("manifest")
	return result

func generate(args: Dictionary) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var result:=prepare(args)
	if not result.ok: return result
	if result.plans.is_empty(): return {"ok":true,"changed":false,"building_ids":[],"lots":result.lots}
	var data:=Data.resolve(editor._doc.map_meta); data.block_layout=result.manifest
	if not Data.valid({"editor_layout":data}): return Data.fail("地块生成记录无效")
	var committed: Dictionary=editor._buildings.commit(result.plans,"",data)
	committed.lots=result.lots; overlay_plan={}
	return committed

func detach(block_ids: Array) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var data:=Data.resolve(editor._doc.map_meta); var manifest: Dictionary=data.get("block_layout",{})
	var known:={}
	for binding in manifest.get("lots",[]): known[binding.block_id]=true
	var seen:={}
	for id in block_ids:
		if not known.has(id) or seen.has(id): return Data.fail("街区没有地块关联或 ID 重复")
		seen[id]=true
	for binding in manifest.get("lots",[]):
		if not seen.has(binding.block_id): continue
		var instance: Dictionary=editor._buildings.instances().get(binding.building_id,{})
		for id in instance.get("parts",{}).values():
			var record: Dictionary=editor._doc._find(id)
			if not record.is_empty() and not editor._record_editable(record): return Data.fail("请先显示并解锁该街区的关联房屋")
	manifest.lots=manifest.get("lots",[]).filter(func(lot):return not seen.has(lot.block_id))
	data.block_layout=manifest; overlay_plan={}
	return editor._city.commit(data)
