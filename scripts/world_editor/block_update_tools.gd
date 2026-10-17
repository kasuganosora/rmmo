extends "res://scripts/world_editor/residential_site_tools.gd"
## Reflow existing identities in one private final-state candidate; never regenerate a house.
const Blocks=preload("res://scripts/world3d/city_blocks.gd")
const Motion=preload("res://scripts/world_editor/building_motion.gd")
const Constraints=preload("res://scripts/world_editor/block_constraints.gd")

static func issue(code:String,message:String,binding:Dictionary={})->Dictionary:
	return fail(code,message,"block_update").merged({"lot_id":binding.get("lot_id",""),"building_id":binding.get("building_id",""),"block_id":binding.get("block_id","")})

func preview(args:Dictionary)->Dictionary:
	var ready:Dictionary=editor._city.guard()
	if not ready.ok:return ready
	if _publishing:return issue("busy","正在发布街区更新")
	var error:=Data.S.validate(args,Blocks.update_schema())
	if not error.is_empty():return issue("invalid_arguments",error)
	var version:=_version();var request_id:=Data.token(args)
	if not _candidate.is_empty() and _candidate.request_id==request_id and _candidate.summary.base_version==version and _dependencies_current(_candidate.dependencies):return _candidate.summary.duplicate(true)
	_candidate={}
	if editor._doc.validate_save()!=OK:return issue("invalid_document","原地图未通过保存校验")
	var dependencies:Dictionary={};error=_dependencies(editor._doc.records,dependencies)
	if not error.is_empty():return issue("resource_missing",error)
	var stage:=Context.new();stage.setup(editor)
	var result:=prepare_update(args,stage)
	if not result.ok:stage.free();return result
	if stage._doc.validate_save()!=OK:stage.free();return issue("invalid_candidate","最终街区未通过保存校验")
	var final_dependencies:Dictionary={};error=_dependencies(stage._doc.records,final_dependencies)
	if not error.is_empty():stage.free();return issue("resource_missing",error)
	for path:String in final_dependencies:
		if dependencies.has(path) and dependencies[path]!=final_dependencies[path]:stage.free();return issue("source_changed","准备期间资源变化，请重新预览")
		dependencies[path]=final_dependencies[path]
	var changes:=delta(editor._doc,stage._doc);var changed:Array=changes.added+changes.updated+changes.removed
	var after:Dictionary=stage._doc.recovery_snapshot()
	var visual:Array=stage._doc.records.filter(func(r):return r.uuid in changed)
	result.merge({"plan_token":Crypto.new().generate_random_bytes(24).hex_encode(),"base_version":version,"changed_ids":changed,"house_ids":result.house_ids,"changes":changes,"road_token":Data.token(Data.resolve(stage._doc.map_meta).roads),"changed":not _same(editor._doc.records,stage._doc.records) or not _same(editor._doc.map_meta,stage._doc.map_meta)})
	stage.free()
	if version!=_version() or not _dependencies_current(dependencies):return issue("base_changed","地图或资源已变化，请重新预览")
	_candidate={"request_id":request_id,"summary":result,"after":after,"integrity":Data.token(after),"dependencies":dependencies,"visual":visual}
	return result.duplicate(true)

func prepare_update(args:Dictionary,stage:Node3D)->Dictionary:
	var previous:=Data.resolve(editor._doc.map_meta);var data:=previous.duplicate(true)
	if args.has("road_changes"):
		var road:Dictionary=editor._city.prepare_roads(args.road_changes)
		if not road.ok:return road
		data=road.value
	var catalog:=Blocks.extract(data.roads)
	if not catalog.ok:return catalog
	var source_catalog:=Blocks.extract(previous.roads)
	if not source_catalog.ok:return source_catalog
	var manifest:Dictionary=data.get("block_layout",{})
	if manifest.get("lots",[]).is_empty():return issue("no_bindings","没有已关联的街区房屋")
	var settings:Dictionary=manifest.settings.duplicate(true)
	for key:String in Blocks.defaults():
		if args.has(key):settings[key]=args[key]
	var selected:Array=args.get("block_ids",[]).duplicate()
	if not args.has("block_ids"):
		for binding:Dictionary in manifest.lots:
			if binding.block_id not in selected:selected.append(binding.block_id)
	var blocks:Dictionary={};var old_blocks:Dictionary={};var lots:Dictionary={};var seen:Dictionary={}
	for block:Dictionary in catalog.blocks:blocks[block.id]=block
	for block:Dictionary in source_catalog.blocks:old_blocks[block.id]=block
	for id:String in selected:
		if seen.has(id) or not blocks.has(id):return issue("unmapped_block","街区不存在、重复或拓扑已改变，不能猜测旧房屋的新归属")
		seen[id]=true
		if blocks[id].protected:return issue("protected_scope","请先解锁并显示所选街区边界")
		var parcels:=Blocks.lots(blocks[id],catalog.blocks,data.roads,settings)
		if not parcels.ok:return parcels
		for lot:Dictionary in parcels.lots:lots[lot.id]=lot
		if lots.size()>1024:return issue("budget_exceeded","更新预览超过 1024 地块，请分区")
	var units:Array=[];var plans:Array=[];var house_ids:Array=[];var updated:Array=[];var retained:Array=[];var missing:Array=[];var changed_parts:Dictionary={}
	var registry:Dictionary=stage._doc.map_meta.get("building_instances",{});var index:Dictionary={}
	for record:Dictionary in stage._doc.records:index[record.uuid]=record
	var motion:=Motion.new();motion.editor=stage
	for binding:Dictionary in manifest.lots:
		if not seen.has(binding.block_id):
			if args.has("road_changes") and (not blocks.has(binding.block_id) or (old_blocks.has(binding.block_id) and Blocks.source_token(blocks[binding.block_id],manifest.settings)!=Blocks.source_token(old_blocks[binding.block_id],manifest.settings))):return issue("scope_conflict","道路还影响其他已关联街区，请将它们一并纳入更新",binding)
			continue
		if not lots.has(binding.lot_id):return issue("unmapped_lot","旧地块已消失或无法一一对应；保留房屋，需显式处理关联",binding)
		var lot:Dictionary=lots[binding.lot_id];lot.building_id=binding.building_id
		if not registry.has(binding.building_id):
			lot.status="missing";missing.append(binding.building_id)
			# Deleted buildings remain tombstones, never recreated by reflow.
			binding.source_token=Blocks.source_token(blocks[binding.block_id],settings)
			continue
		var value:Dictionary=registry[binding.building_id];var members:Array=[]
		for part:String in value.parts:
			var r:Dictionary=index.get(value.parts[part],{})
			if r.is_empty() or r.get("building",{}).get("id")!=binding.building_id or Blueprint.geometry_signature(r)!=value.signatures[part]:return issue("building_modified","构件缺失或几何手改无法可靠映射；整批保持原状",binding)
			members.append(r)
		var anchor:Dictionary=binding.get("anchor",{}).duplicate(true)
		if anchor.is_empty():
			if not old_blocks.has(binding.block_id) or binding.source_token!=Blocks.source_token(old_blocks[binding.block_id],manifest.settings):return issue("legacy_anchor_missing","旧关联缺少更新基线，且原道路已变化；不能推测旧地块位置",binding)
			var original:=Blocks.lots(old_blocks[binding.block_id],source_catalog.blocks,previous.roads,manifest.settings)
			if not original.ok:return original
			var old_lots:Array=original.lots.filter(func(l):return l.id==binding.lot_id)
			if old_lots.size()!=1:return issue("legacy_anchor_missing","旧地块无法恢复，未改动房屋",binding)
			var forward:=Basis(Vector3.UP,deg_to_rad(float(value.yaw)))*Vector3.FORWARD
			var entrances:Array=Access.entrances(members,value.yaw).filter(func(e):return e.outward.dot(forward)>.999)
			if entrances.size()!=1:return issue("legacy_anchor_missing","旧建筑正面入口不唯一，无法建立更新基线",binding)
			var entry:=Access.entrance(members,value.yaw,entrances[0].id)
			if not entry.ok:return entry
			anchor={"position":old_lots[0].position,"yaw":old_lots[0].yaw,"entrance_local":Data.xyz(Basis(Vector3.UP,deg_to_rad(float(value.yaw))).inverse()*(entry.position-Data.vec(value.position)))}
		var angle:float=wrapf(float(lot.yaw)-float(anchor.yaw),-180.,180.)
		var movement:Vector3=Data.vec(lot.position)-Data.vec(anchor.position)
		var moved:bool=not movement.is_zero_approx() or absf(angle)>.00001
		if moved and members.any(func(r):return not editor._record_editable(r)):return issue("protected_scope","受影响建筑包含锁定、隐藏或隔层构件",binding)
		var unit:Dictionary={"id":binding.building_id,"value":value,"records":members}
		var proposed:=motion.proposal([unit],movement,Basis(Vector3.UP,deg_to_rad(angle)),Data.vec(anchor.position))
		if not proposed.ok:return proposed
		var plan:Dictionary=proposed.plans[0]
		if not moved:plan.records=members;plan.value=value
		var entrance:Vector3=Data.vec(plan.value.position)+Basis(Vector3.UP,deg_to_rad(float(plan.value.yaw)))*Data.vec(anchor.entrance_local)
		lot.access=[lot.street,Data.xyz(entrance)];lot.status="updated" if moved else "retained"
		var footprint:Array=[]
		for r:Dictionary in plan.records:
			for p:Vector3 in Geometry.corners(r):footprint.append(Vector2(p.x,p.z))
		var hull:=Array(Geometry2D.convex_hull(PackedVector2Array(footprint)))
		if hull.size()>1:hull.pop_back()
		if not Blocks.inside(hull,Blocks.unpack(lot.polygon)):return issue("lot_fit","原建筑及手工偏移超出新地块，不能自动缩放或重建",binding)
		lot.building_polygon=Blocks.serialize(hull);lot.parameters=value.parameters
		units.append({"binding":binding,"lot":lot,"plan":plan})
		if moved:
			if updated.size()>=16:return issue("budget_exceeded","一次最多更新 16 栋，请缩小范围")
			updated.append(binding.building_id);plans.append(plan)
			for r:Dictionary in plan.records:changed_parts[r.uuid]=r;house_ids.append(r.uuid)
			registry[binding.building_id]=plan.value
		else:retained.append(binding.building_id)
		anchor.position=lot.position.duplicate();anchor.yaw=lot.yaw;binding.anchor=anchor
		binding.source_token=Blocks.source_token(blocks[binding.block_id],settings)
	for i in stage._doc.records.size():
		if changed_parts.has(stage._doc.records[i].uuid):stage._doc.records[i]=changed_parts[stage._doc.records[i].uuid]
	manifest.settings=settings;data.block_layout=manifest;stage._doc.map_meta.editor_layout=data
	# Prepare the road against final building poses, never an unsafe intermediate state.
	if data.has("road_surface"):
		var roads:Dictionary=stage._roads.prepare({},data)
		if not roads.ok:return stage_failure(roads,"block_update_roads")
		if Data.token(roads.graph)!=Data.token(data.roads):return issue("unmapped_block","道路预处理会改变拓扑，请先明确拆分及地块对应关系")
		var replacements:Dictionary={};var next:Array=[]
		for r:Dictionary in roads.records:replacements[r.uuid]=r
		for r:Dictionary in stage._doc.records:
			if replacements.has(r.uuid):next.append(replacements[r.uuid]);replacements.erase(r.uuid)
			elif not roads.excluded.has(r.uuid):next.append(r)
		next.append_array(replacements.values());stage._doc.records=next
		data.road_surface=roads.manifest;stage._doc.map_meta.editor_layout=data
	var clear:=motion.clearance(plans,changed_parts)
	if not clear.ok:return clear
	var constraints:=Constraints.collect(stage._doc)
	if not constraints.ok:return constraints
	for unit:Dictionary in units:
		var lot:Dictionary=unit.lot;var level:float=lot.position[1]
		if not Constraints.flat_ground(stage._doc,lot.polygon,level):return issue("ground_unavailable","新地块缺少完整同高实地，不能自动填沟或悬空安放",unit.binding)
		var conflict:=Constraints.conflict(lot.polygon,level-1.2,level+40,constraints.reservations)
		if not conflict.is_empty():return issue("reservation_conflict","更新后的地块占用河流、桥头或城门通道",unit.binding).merged({"reservation":conflict,"conflicts":conflict.source_ids})
		var a:=Data.vec(lot.access[0]);var b:=Data.vec(lot.access[1]);var side:=Vector3(-(b-a).z,0,(b-a).x).normalized()*1.05
		var polygon:Array=[]
		for p:Vector3 in [a-side,b-side,b+side,a+side]:polygon.append([p.x,p.z])
		if not Constraints.flat_ground(stage._doc,polygon,level):return issue("ground_unavailable","新入口连接缺少连续同高实地",unit.binding)
		conflict=Constraints.conflict(polygon,level+.06,level+3.,constraints.reservations)
		if not conflict.is_empty():return issue("reservation_conflict","更新后的入口连接占用保留通道",unit.binding).merged({"reservation":conflict,"conflicts":conflict.source_ids})
		var access:=Foot.from_points([a-side+Vector3.UP*.06,b-side+Vector3.UP*.06,b+side+Vector3.UP*3.,a+side+Vector3.UP*3.])
		if Foot.batches_overlap([access],preload("res://scripts/world3d/planning_zones.gd").obstacles(stage._doc.map_meta)):return issue("access_blocked","更新后的入口连接侵入保留区",unit.binding)
		for r:Dictionary in stage._doc.records:
			if r.uuid in unit.plan.value.parts.values():continue
			for shape:Dictionary in Foot.record_shapes(r):
				if r.has("road_mesh") and Geometry.bounds([r]).end.y<=level+.06:continue
				if Foot.supporting_ground(r,shape.bounds.end.y,level):continue
				if Foot.batches_overlap([access],[shape]):return issue("access_blocked","更新后的入口连接被物件阻挡",unit.binding).merged({"conflicts":[r.uuid]})
	return {"ok":true,"blocks":catalog.blocks.filter(func(b):return seen.has(b.id)),"lots":lots.values(),"reservations":constraints.reservations,"updated_building_ids":updated,"retained_building_ids":retained,"missing_building_ids":missing,"house_ids":house_ids,"building_count":0,"settings":settings,"checks":{"identity_preserved":true,"final_road_validation":data.has("road_surface"),"automatic_reservations":true,"final_save":true}}

func apply(args:Dictionary)->Dictionary:
	var ready:Dictionary=editor._city.guard()
	if not ready.ok:return ready
	if args.size()!=1 or not args.get("plan_token") is String:return issue("invalid_arguments","应用只接受预览返回的 plan_token")
	if not _candidate.is_empty() and args.get("plan_token")==_candidate.summary.plan_token and not _candidate.summary.changed:
		if _version()!=_candidate.summary.base_version or not _dependencies_current(_candidate.dependencies):_candidate={};return issue("base_changed","地图或资源已变化，请重新预览")
		var result:Dictionary=_candidate.summary.duplicate(true);_candidate={};return result
	return super.apply(args)
