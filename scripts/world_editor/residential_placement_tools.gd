extends RefCounted
## Private authoring candidates. Nothing below swaps the editor's live document
## during preparation; publication is one synchronous native recovery transaction.
const Data=preload("res://scripts/world3d/city_layout.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Prefabs=preload("res://scripts/world_editor/prefab_library.gd")
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const Support=preload("res://scripts/world_editor/residential_support.gd")
const Access=preload("res://scripts/world_editor/residential_access.gd")
const Roads=preload("res://scripts/world_editor/road_tools.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Thumbnails=preload("res://scripts/world_editor/asset_thumbnails.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const BridgeContext=preload("res://scripts/world_editor/residential_bridge_context.gd")
const Waterways=preload("res://scripts/world_editor/waterway_tools.gd")
const BridgeApproach=preload("res://scripts/world3d/road_bridge_approach.gd")
const CurveConnection=preload("res://scripts/world_editor/residential_curve_connection.gd")
const STEP=.05
const MAX_CANDIDATES=157
var editor:Node3D
var _candidate:Dictionary={}
var _publishing:=false
## Private block orchestration may resolve descendants of ONE requested edge.
var target_edges:Array=[]
## Opt-in diagnostics for controlled editor benchmarks. Never authoring state.
var profile_enabled:=false
var last_profile:Dictionary={}

func _profile_start()->int:
	return Time.get_ticks_usec() if profile_enabled else 0

func _profile_end(stage:String,started:int)->void:
	if profile_enabled:
		last_profile.stages_ms[stage]=float(last_profile.stages_ms.get(stage,0.))+(Time.get_ticks_usec()-started)/1000.

class PreparationContext extends Node3D:
	var _doc
	var _authoring
	var _material_tool
	var _waterways
	var source:Node3D
	func _record_editable(record:Dictionary)->bool:return source._record_editable(record)

static func defaults()->Dictionary:
	return {"yaw":0.0,"elevation_min":-.5,"elevation_max":.5,"setback_min":.8,"setback_max":3.0,"width":1.6}

static func request_schema()->Dictionary:
	return Data.object({"asset_id":Data.text(2048),"position":Data.S.vector(-100000,100000),"road_edge_id":Data.text(),"entrance_id":Data.text(180),"support_mode":Data.choice(["continuous","piers"]),"yaw":Data.S.number(-180,180),"elevation_min":Data.S.number(-3,0),"elevation_max":Data.S.number(0,3),"setback_min":Data.S.number(.2,8),"setback_max":Data.S.number(.2,8),"width":Data.S.number(1,4)},["asset_id","position","road_edge_id"])

static func fail(code:String,message:String,stage:String="residential_placement")->Dictionary:
	return {"ok":false,"code":code,"error":message,"stage":stage}

func _version()->String:
	# Monotonic session revision prevents undo/redo ABA without serializing all
	# 32 retained recovery snapshots. Content also detects direct document edits.
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes([editor._path,editor._doc.get_instance_id(),editor._doc.authoring_revision,editor._doc.recovery_snapshot(),editor._authoring.settings]))
	return hash.finish().hex_encode()

func discard(token:String)->Dictionary:
	if not _candidate.is_empty() and _candidate.summary.plan_token==token:_candidate={}
	return {"ok":true}

func preview_visual(token:String)->Array:
	if _candidate.is_empty() or _candidate.summary.plan_token!=token:return []
	return _candidate.visual.duplicate(true)

func source(p:Dictionary)->Dictionary:
	var entries:Array=editor.asset_items().filter(func(e):return Thumbnails.key_for(e)==p.asset_id and e.has("prefab_path"))
	if entries.size()!=1:return fail("asset_not_found","请选择资源库中的冻结住宅预制件")
	var entry:Dictionary=entries[0]
	if not Paths.allowed(entry.prefab_path) or not FileAccess.file_exists(entry.prefab_path):return fail("resource_missing","住宅资源超出资源根或不存在")
	var sha:=FileAccess.get_sha256(entry.prefab_path)
	return {"ok":true,"entry":entry,"sha":sha,"dependencies":{entry.prefab_path:sha}}

func load_source(value:Dictionary)->Dictionary:return Prefabs.read(value.entry)

static func inspection_schema()->Dictionary:
	return Data.object({"asset_id":Data.text(2048),"building_id":Data.text(),"support_mode":Data.choice(["continuous","piers"])},[])

func inspect_entrances(args:Dictionary)->Dictionary:
	var issue:=Data.S.validate(args,inspection_schema())
	if not issue.is_empty() or args.has("asset_id")==args.has("building_id"):return fail("invalid_arguments","请且仅指定 asset_id 或 building_id")
	var records:Array=[];var value:Dictionary={}
	if args.has("building_id"):
		value=editor._doc.map_meta.get("building_instances",{}).get(args.building_id,{})
		if value.is_empty():return fail("building_not_found","建筑不存在")
		records=editor._doc.records.filter(func(r):return r.get("building",{}).get("id")==args.building_id)
	else:
		var found:=source(args)
		if not found.ok:return found
		var loaded:=load_source(found)
		if not loaded.ok:return loaded
		if loaded.building_instances.size()!=1:return fail("unsupported","需要恰好一栋冻结住宅")
		records=loaded.records;value=loaded.building_instances.values()[0]
	if not value.get("baked",false) or value.parameters.get("template")!="house":return fail("unsupported","请选择冻结住宅")
	var rows:Array=[]
	for choice:Dictionary in Access.entrances(records,float(value.yaw)):
		var checked:=Access.entrance(records,float(value.yaw),choice.id)
		var row:Dictionary={"id":choice.id,"kind":"passage" if choice.has("portal") else "door","record_id":choice.record.uuid,"outward":Data.xyz(choice.outward),"ok":checked.ok}
		if checked.ok:row.position=Data.xyz(checked.position)
		else:row.failure=checked
		rows.append(row)
	var support:=Support.support_components(records,0.,value.parameters,args.get("support_mode",value.get("residential_support_mode","continuous")))
	return {"ok":true,"entrances":rows,"requires_selection":rows.size()!=1,"coordinate_space":"world" if args.has("building_id") else "prefab","support":support,"base_version":_version()}

func place(doc,local:Dictionary,position:Vector3,label:String)->Dictionary:
	return Prefabs.place_buildings(doc,local,position,label)

func preview(args:Dictionary)->Dictionary:
	last_profile={"cached":false,"stages_ms":{}} if profile_enabled else {}
	var phase:=_profile_start()
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	if _publishing:return fail("busy","正在发布住宅候选")
	var issue:=Data.S.validate(args,request_schema())
	if not issue.is_empty():return fail("invalid_arguments",issue)
	var p:=defaults().merged(args,true)
	if p.setback_min>p.setback_max:return fail("invalid_arguments","最小退距不能超过最大退距")
	var source_info:=source(p)
	if not source_info.ok:return source_info
	var entry:Dictionary=source_info.entry
	var source_sha:String=source_info.sha
	var base_version:=_version()
	var request_id:=Data.token(p)
	if not _candidate.is_empty() and _candidate.request_id==request_id and _candidate.summary.base_version==base_version and _candidate.summary.source_sha256==source_sha and _dependencies_current(_candidate.dependencies):
		_profile_end("lookup_identity",phase)
		if profile_enabled:last_profile.cached=true
		return _candidate.summary.duplicate(true)
	_profile_end("lookup_identity",phase);phase=_profile_start()
	_candidate={}
	var started:=Time.get_ticks_usec()
	var loaded:=load_source(source_info)
	if not loaded.ok:return loaded.merged({"code":"invalid_prefab","stage":"resource"})
	if loaded.building_instances.size()!=1:return fail("unsupported","当前闭环需要恰好一栋冻结住宅")
	var instance:Dictionary=loaded.building_instances.values()[0]
	if not instance.get("baked",false) or instance.parameters.get("layout") not in ["townhouse","hall"] or instance.parameters.get("template")!="house":return fail("unsupported","当前支持 townhouse / hall 的单栋冻结住宅；请选择住宅模板")
	if loaded.records.any(func(r):return not r.has("building") or not r.get("prefab_locked",false)):return fail("unsupported","住宅包含未冻结或无归属构件")
	var dependencies:Dictionary=source_info.dependencies.duplicate(true)
	var dependency_issue:=_dependencies(loaded.records,dependencies)
	if not dependency_issue.is_empty():return fail("resource_missing",dependency_issue,"resource")
	var data:=Data.resolve(editor._doc.map_meta)
	if not data.has("road_surface") or not data.road_surface.settings.get("follow_terrain",false):return fail("unsupported","请先生成沿地形的已有道路铺面，再连接住宅")
	if data.road_surface.graph_token!=Data.token(data.roads):return fail("stale_road_surface","道路草案与铺面不一致，请先完成已有道路生成")
	var road_check:=_target(data.roads,p.road_edge_id)
	if not road_check.ok:return road_check
	var bridges:=BridgeContext.capture(editor,data)
	if not bridges.ok:return bridges
	dependency_issue=_dependencies(bridges.records,dependencies)
	if not dependency_issue.is_empty():return fail("resource_missing",dependency_issue,"resource")
	var local:=_oriented(loaded,float(p.yaw))
	var input:=Data.vec(p.position)
	_profile_end("source_and_target",phase);phase=_profile_start()
	var solved:=Support.solve(editor._doc,loaded.records,input,float(p.yaw),instance.parameters,{"min_y":input.y+p.elevation_min,"max_y":input.y+p.elevation_max,"input_version":base_version,"support_mode":p.get("support_mode",instance.get("residential_support_mode","continuous"))})
	_profile_end("support",phase);phase=_profile_start()
	if not solved.ok:return solved
	var position:Vector3=solved.position
	var initial_records:=_translated(local.records,position)
	var initial_entry:=Access.entrance(initial_records,float(instance.yaw)+float(p.yaw),p.get("entrance_id",""))
	if not initial_entry.ok:return initial_entry
	var entrance_limit:=Access.elevation_limit(editor._doc,initial_records,initial_entry)
	if not entrance_limit.ok:return entrance_limit
	var maximum_y:float=position.y+entrance_limit.maximum_shift
	if maximum_y<float(solved.support.interval[0]):return fail("entrance_height_interval","基础承托与真实入口台阶没有共同可行标高").merged({"support_interval":solved.support.interval,"maximum_entrance_y":maximum_y,"position":Data.xyz(initial_entry.position)})
	position.y=minf(position.y,maximum_y)
	solved.support.entrance_maximum_y=maximum_y
	_profile_end("entrance_elevation",phase);phase=_profile_start()
	var before:Dictionary=editor._doc.recovery_snapshot()
	var staged=Doc.new();staged.apply_recovery(before)
	var placed:=place(staged,local,position,str(entry.get("label","住宅")))
	if not placed.ok:return placed.merged({"code":"placement_conflict","stage":"house_geometry"})
	var house_records:Array=[]
	for id:String in placed.ids:house_records.append(staged._find(id))
	for r:Dictionary in house_records:
		if not editor._authoring.Settings.contains(r,editor._authoring.settings):return fail("protected_scope","住宅落在当前隔离楼层外")
	var entry_info:=Access.entrance(house_records,float(instance.yaw)+float(p.yaw),p.get("entrance_id",""))
	_profile_end("native_house_placement",phase);phase=_profile_start()
	if not entry_info.ok:return entry_info
	var context:=PreparationContext.new();context.source=editor;context._doc=staged;context._authoring=editor._authoring;context._material_tool=editor._material_tool
	context._waterways=Waterways.new();context._waterways.editor=context
	var roads:=Roads.new();roads.editor=context
	var last:Dictionary={};var prepared:Dictionary={};var linked:Dictionary={};var access:Dictionary={};var attempts:=0
	var full_graph_checks:=0
	var occupancy:=Foot.components(house_records,Vector3.ZERO,Basis.IDENTITY)
	var count:=mini(MAX_CANDIDATES,ceili((p.setback_max-p.setback_min)/STEP)+1)
	_profile_end("search_setup",phase)
	for i in count:
		phase=_profile_start()
		var setback:float=minf(p.setback_max,p.setback_min+i*STEP)
		attempts+=1
		var chosen:=_nearest_target(data.roads,target_edges,entry_info.position+entry_info.outward*setback) if not target_edges.is_empty() else road_check
		linked=_connect(data,chosen,entry_info,setback,p.width,request_id.left(14)) if chosen.ok else chosen
		_profile_end("connect",phase);phase=_profile_start()
		if not linked.ok:last=linked;continue
		var quick:=_connector_clearance(linked,data.road_surface.settings,occupancy,editor._doc.map_meta)
		_profile_end("quick_clearance",phase);phase=_profile_start()
		if not quick.ok:last=quick;prepared={};continue
		var connector_ground:=_connector_ground(staged,linked,p.width)
		_profile_end("connector_ground",phase);phase=_profile_start()
		if not connector_ground.ok:last=connector_ground;prepared={};continue
		full_graph_checks+=1
		prepared=roads.prepare({},linked.data)
		_profile_end("full_road",phase);phase=_profile_start()
		if not prepared.ok:last=prepared;continue
		# JSON reload produces float zero rotations where the generator uses int
		# zero. Preserve equal authored records verbatim; do not dirty distant
		# chunks merely because nested Dictionary equality is type-sensitive.
		for record_index in prepared.records.size():
			var record:Dictionary=prepared.records[record_index]
			var previous:Dictionary=staged._find(record.uuid)
			if _same(record,previous):prepared.records[record_index]=previous.duplicate(true)
		if Data.token(prepared.graph)!=Data.token(linked.data.roads):last=fail("scope_conflict","完整路网检查还需要拆分其他道路，请先处理道路交叉");continue
		_profile_end("preserve_records",phase);phase=_profile_start()
		var extra:=_candidate_clearance(prepared,staged,occupancy)
		_profile_end("candidate_clearance",phase);phase=_profile_start()
		if not extra.ok:last=extra;prepared={};continue
		access=Access.check(staged,house_records,entry_info,Data.vec(linked.points[0]),p.width)
		_profile_end("entrance_access",phase)
		if not access.ok:last=access;continue
		access.connector_ground=connector_ground
		break
	context.free()
	if prepared.is_empty() or not prepared.get("ok",false) or not access.get("ok",false) or not linked.get("ok",false) or Data.token(prepared.get("graph",{}))!=Data.token(linked.get("data",{}).get("roads",{})):
		return fail("search_exhausted","允许退距内未找到通过全部检查的候选；可调整位置或范围后重试").merged({"attempts":attempts,"last_failure":last,"position":Data.xyz(position),"search_complete":false})
	# Road generation is pure until here. Preserve every untouched record verbatim.
	phase=_profile_start()
	staged.records=staged.records.filter(func(r):return not prepared.excluded.has(r.uuid))
	staged.records.append_array(prepared.records)
	linked.data.roads=prepared.graph;linked.data.road_surface=prepared.manifest;staged.map_meta.editor_layout=linked.data
	var binding:=preload("res://scripts/world_editor/residential_access_binding.gd").capture(linked.data.roads,request_id.left(14),staged.map_meta.building_instances[house_records[0].building.id])
	staged.map_meta.building_instances[house_records[0].building.id].residential_access=binding
	if solved.support.support_mode=="piers":staged.map_meta.building_instances[house_records[0].building.id].residential_support_mode="piers"
	var preserved:=BridgeContext.verify(staged,linked.data,bridges)
	if not preserved.ok:return preserved
	dependency_issue=_dependencies(prepared.records,dependencies)
	if not dependency_issue.is_empty():return fail("resource_missing",dependency_issue,"resource")
	if staged.validate_save()!=OK:return fail("candidate_invalid","组合候选未通过原生保存校验","save_validation")
	_profile_end("final_validation",phase);phase=_profile_start()
	var changed:Array[String]=[];var visual:Array=[];var old:Dictionary={}
	for r:Dictionary in before.records:old[r.uuid]=r
	for r:Dictionary in staged.records:
		if not old.has(r.uuid) or not _same(old[r.uuid],r):changed.append(r.uuid);visual.append(r)
		old.erase(r.uuid)
	for id:String in old:changed.append(id)
	var a:=Data.vec(road_check.a.position);var b:=Data.vec(road_check.b.position);var start:=Data.vec(linked.points[0])
	var scope:=Rect2(Vector2(a.x,a.z),Vector2.ZERO).expand(Vector2(b.x,b.z)).expand(Vector2(start.x,start.z))
	# Exact cubic geometry is contained by its control hull, including bends
	# outside the endpoint rectangle. Authoring outside this edge stays intact.
	for handle:Array in road_check.edge.get("controls",[]):scope=scope.expand(Vector2(handle[0],handle[2]))
	for id:String in target_edges:
		var related:=_target(data.roads,id)
		if not related.ok:return related
		for point:Array in [related.a.position,related.b.position]+related.edge.get("controls",[]):scope=scope.expand(Vector2(point[0],point[2]))
	scope=scope.grow(maxf(maxf(road_check.edge.width_start,road_check.edge.width_end),p.width)+32.)
	for r:Dictionary in before.records:
		if r.has("road_source") and changed.has(r.uuid):
			var bounds_:AABB=Geometry.bounds([r])
			if not scope.intersects(Rect2(bounds_.position.x,bounds_.position.z,bounds_.size.x,bounds_.size.z),true):return fail("scope_conflict","候选会改变接路范围以外的道路铺面，已保留原地图")
	var bounds:=Geometry.bounds(house_records)
	var token:=Crypto.new().generate_random_bytes(24).hex_encode()
	var summary:Dictionary={"ok":true,"plan_token":token,"source_sha256":source_sha,"base_version":base_version,"position":Data.xyz(position),"adjustment":Data.xyz(position-input),"road_points":linked.points,"road_connection":linked.road_connection,"setback":linked.setback,"width":p.width,"building_id":house_records[0].building.id,"building_ids":[house_records[0].building.id],"house_ids":placed.ids,"changed_ids":changed,"support":solved.support,"access":access,"bridges":bridges.summary,"bounds":{"position":Data.xyz(bounds.position),"size":Data.xyz(bounds.size)},"checks":{"continuous_support":true,"native_house_geometry":true,"full_road_graph":true,"bridge_context":true,"entrance_corridor":true,"native_save":true,"runtime_traversal":"requires_runtime_verification"},"search":{"attempts":attempts,"full_graph_checks":full_graph_checks,"budget":count,"step":STEP,"prepare_ms":(Time.get_ticks_usec()-started)/1000.}}
	_profile_end("result",phase);phase=_profile_start()
	var current:=base_version==_version() and _dependencies_current(dependencies)
	_profile_end("final_identity",phase);phase=_profile_start()
	if not current:return fail("base_changed","输入或资源已变化，请重新预览")
	summary.access_binding=binding.duplicate(true)
	summary.building_position=staged.map_meta.building_instances[summary.building_id].position.duplicate()
	_candidate={"summary":summary,"request_id":request_id,"dependencies":dependencies,"after":staged.recovery_snapshot(),"visual":visual}
	_profile_end("candidate_snapshot",phase)
	return summary.duplicate(true)

func apply(args:Dictionary)->Dictionary:
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	if _publishing:return fail("busy","正在发布住宅候选")
	if args.size()!=1 or not args.get("plan_token") is String:return fail("invalid_arguments","应用只接受预览返回的 plan_token")
	if _candidate.is_empty() or args.plan_token!=_candidate.summary.plan_token:return fail("candidate_missing","候选已放弃或不存在，请重新预览")
	if not _dependencies_current(_candidate.dependencies):_candidate={};return fail("source_changed","住宅、桥梁或材质资源已变化，请重新预览")
	if _version()!=_candidate.summary.base_version:_candidate={};return fail("base_changed","地图、撤销历史或隔离范围已变化，请重新预览")
	_publishing=true
	var before:Dictionary=editor._doc.recovery_snapshot()
	var result:Dictionary=_candidate.summary.duplicate(true)
	# No await/event dispatch between final identity check and author publication.
	editor._doc.apply_recovery(_candidate.after)
	editor._doc.commit_recovery_change(before)
	_candidate={}
	editor._commit_records(result.changed_ids)
	editor._selection_tools.set_ids(result.house_ids)
	editor._city.refresh()
	_publishing=false
	result.changed=true
	return result

static func _oriented(loaded:Dictionary,yaw:float)->Dictionary:
	var copy:=loaded.duplicate(true);var basis:=Basis(Vector3.UP,deg_to_rad(yaw))
	for r:Dictionary in copy.records:
		r.position=Data.xyz(basis*Data.vec(r.position));r.rotation=Data.xyz((basis*Basis.from_euler(Data.vec(r.rotation)*PI/180)).get_euler()*180/PI)
	for value:Dictionary in copy.building_instances.values():
		value.position=Data.xyz(basis*Data.vec(value.position));value.yaw=wrapf(float(value.yaw)+yaw,-180,180)
	return copy

static func _translated(records:Array,position:Vector3)->Array:
	var copy:=records.duplicate(true)
	for r:Dictionary in copy:
		r.position=Data.xyz(Data.vec(r.position)+position);r.building.floor_y+=position.y
	return copy

static func _dependencies(value:Variant,result:Dictionary)->String:
	if value is Array:
		for item:Variant in value:
			var error:=_dependencies(item,result)
			if not error.is_empty():return error
	elif value is Dictionary:
		for key:Variant in value:
			var item:Variant=value[key]
			if item is String and str(key).ends_with("_path") and not item.is_empty():
				if not Paths.allowed(item) or not FileAccess.file_exists(item):return "资源依赖缺失或超出资源根："+item
				result[item]=FileAccess.get_sha256(item)
			elif item is Array or item is Dictionary:
				var error:=_dependencies(item,result)
				if not error.is_empty():return error
	return ""

static func _dependencies_current(dependencies:Dictionary)->bool:
	for path:String in dependencies:
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=dependencies[path]:return false
	return true

static func _same(left:Variant,right:Variant)->bool:
	# Exact numeric equality, without rounding or widening geometric tolerances.
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
	return left==right

static func supports_target(edge:Dictionary)->bool:
	return edge.get("kind")=="ground" and not edge.has("bridge_ref") and not edge.has("stone_bridge")

static func _target(graph:Dictionary,id:String)->Dictionary:
	var rows:Array=graph.edges.filter(func(e):return e.id==id)
	if rows.size()!=1:return fail("road_not_found","目标道路不存在")
	var edge:Dictionary=rows[0]
	if not supports_target(edge):return fail("unsupported","当前接路目标需要普通直线或三次贝塞尔地面道路")
	var nodes:Dictionary={}
	for n:Dictionary in graph.nodes:nodes[n.id]=n
	for item:Dictionary in [edge,nodes[edge.from],nodes[edge.to]]:
		if item.get("locked",false) or item.get("hidden",false):return fail("protected_scope","目标道路或连接节点被锁定或隐藏")
	return {"ok":true,"edge":edge,"a":nodes[edge.from],"b":nodes[edge.to]}

static func _connect(original:Dictionary,target:Dictionary,entry:Dictionary,setback:float,width:float,key:String)->Dictionary:
	var data:=original.duplicate(true);var graph:Dictionary=data.roads
	var door:Vector3=entry.position;var out:Vector3=entry.outward;var start:=door+out*setback
	var a:=Data.vec(target.a.position);var b:=Data.vec(target.b.position)
	var ab:=Vector2(b.x-a.x,b.z-a.z)
	if ab.length_squared()<.01:return fail("invalid_road","目标道路过短")
	var t:=clampf(Vector2(start.x-a.x,start.z-a.z).dot(ab)/ab.length_squared(),0,1)
	var end:=a.lerp(b,t)
	var curve:bool=target.edge.has("controls");var nodes:Dictionary={target.edge.from:target.a,target.edge.to:target.b};var projection:Dictionary={}
	if curve:
		projection=CurveConnection.nearest(target.edge,nodes,start)
		if not projection.ok:return projection
		t=projection.t;end=projection.point
		projection.nearest_parameter=t;projection.nearest_position=projection.position.duplicate();projection.endpoint_adjustment_m=0.
		# Reconnecting at a saved junction can project a few millimetres inside
		# its child curve. Reuse that endpoint within 5 cm instead of creating
		# a forbidden tiny segment. No control point or existing node moves.
		var from_gap:=Vector2(end.x-a.x,end.z-a.z).length();var to_gap:=Vector2(end.x-b.x,end.z-b.z).length()
		if t>0. and t<1. and minf(from_gap,to_gap)<.05:
			t=0. if from_gap<=to_gap else 1.
			end=a if t==0. else b
			projection.endpoint_adjustment_m=minf(from_gap,to_gap)
			projection.position=target.a.position.duplicate() if t==0. else target.b.position.duplicate()
			projection.tangent=CurveConnection.Split.derivative(target.edge,nodes,t)
			if Vector2(projection.tangent.x,projection.tangent.z).length()<.0001:return fail("curve_tangent_degenerate","端点切向退化，请调整道路控制点")
	if Vector2(end.x-start.x,end.z-start.z).length()<1 or (end-start).dot(out)<.1:return fail("access_direction","目标道路位于入口背后或退距超过接路位置")
	var prefix:="home_"+key;var join:String=prefix+"_join"
	if (curve and t==0.) or (not curve and t<.001):join=target.edge.from;end=a;t=0.
	elif (curve and t==1.) or (not curve and t>.999):join=target.edge.to;end=b;t=1.
	else:
		var old_to:String=target.edge.to;var mid_width:float=lerpf(target.edge.width_start,target.edge.width_end,t)
		var subcurves:Array=CurveConnection.controls(target.edge,nodes,t) if curve else []
		for e:Dictionary in graph.edges:
			if e.id==target.edge.id:
				e.to=join;e.width_end=mid_width
				e.erase("cap_end")
				if curve:e.controls=subcurves[0]
		var tail:Dictionary=target.edge.duplicate(true);tail.id=prefix+"_tail";tail.from=join;tail.to=old_to;tail.width_start=mid_width
		tail.erase("cap_start")
		if curve:tail.controls=subcurves[1]
		graph.edges.append(tail);graph.nodes.append({"id":join,"position":projection.position if curve else Data.xyz(end)})
	for edge:Dictionary in original.roads.edges:
		if join in [edge.from,edge.to] and (edge.has("bridge_ref") or edge.has("stone_bridge")):return fail("bridgehead_target","住宅入户路不能直接接入桥头节点，请选择桥外普通地面道路的内部位置","bridge_context")
		if join in [edge.from,edge.to] and (edge.get("locked",false) or edge.get("hidden",false)):return fail("protected_scope","接驳节点关联了受保护道路")
	# Terrain-following pavement uses the true heightfield, not this guide's Y.
	start.y=end.y
	graph.nodes.append({"id":prefix+"_door","position":Data.xyz(start)})
	graph.edges.append({"id":prefix+"_access","from":prefix+"_door","to":join,"name":"住宅入户路","kind":"ground","width_start":width,"width_end":width})
	var checked:=Data.analyze(graph)
	if not checked.ok:return checked
	var split:bool=join==prefix+"_join"
	var connection:Dictionary={"edge_id":target.edge.id,"kind":"cubic" if curve else "straight","parameter":t,"position":projection.position if curve else Data.xyz(end),"tangent":Data.xyz(projection.tangent if curve else b-a),"width":lerpf(target.edge.width_start,target.edge.width_end,t),"split":split,"join_node_id":join,"child_edge_ids":[target.edge.id,prefix+"_tail"] if split else [target.edge.id]}
	if curve:connection.projection={"distance_error_bound_m":projection.distance_error_bound_m,"visits":projection.visits,"nearest_parameter":projection.nearest_parameter,"nearest_position":projection.nearest_position,"endpoint_adjustment_m":projection.endpoint_adjustment_m}
	return {"ok":true,"data":data,"points":[Data.xyz(start),Data.xyz(end)],"setback":setback,"road_connection":connection}

static func _connector_ground(doc,linked:Dictionary,width:float)->Dictionary:
	var start:=Data.vec(linked.points[0]);var finish:=Data.vec(linked.points[1])
	var a:=Vector2(start.x,start.z);var b:=Vector2(finish.x,finish.z)
	if a.distance_squared_to(b)<.000001 or width<=0.:return fail("access_direction","入户路通行走廊退化","connector_ground")
	var direction:Vector2=(b-a).normalized();var side:=Vector2(-direction.y,direction.x)*width*.5
	var ground:Dictionary=Support.terrain_region(doc,[a-side,b-side,b+side,a+side])
	if not ground.ok:return ground.merged({"stage":"connector_ground"},true)
	# Projection checks each triangle's road grade later, but cannot prove a
	# traversable jump between distinct heightfields. Cover the entire new link.
	if ground.get("max_grade",INF)>1.0 or ground.get("max_seam_step",INF)>Access.STEP_LIMIT:
		return fail("connector_slope","入户路地面坡度或地块接缝超过玩家通行范围","connector_ground").merged({"max_grade":ground.get("max_grade",INF),"max_seam_step":ground.get("max_seam_step",INF),"grade_witness":ground.get("grade_witness",{}),"seam_witness":ground.get("seam_witness",{}),"terrain_ids":ground.get("terrain_ids",[])})
	return ground

static func _connector_clearance(linked:Dictionary,settings:Dictionary,occupied:Array,_meta:Dictionary)->Dictionary:
	var edge:Dictionary=linked.data.roads.edges.back()
	var graph:Dictionary={"nodes":linked.data.roads.nodes.filter(func(n):return n.id in [edge.from,edge.to]),"edges":[edge]}
	var built:=Plan.build(graph,settings)
	if not built.ok:return built
	# A conservative XZ rejection is cheap; successful candidates still undergo
	# the full native graph/terrain/clearance pass. It cannot grant acceptance.
	# Zone height ranges require the fitted road, not the guide's Y or this
	# deliberately infinite-height house broad phase. _candidate_clearance
	# checks their actual new occupied volume after full terrain projection.
	for record:Dictionary in built.records:
		for shape:Dictionary in Foot.record_shapes(record)+_kerb_shapes(record):
			shape.bounds.position.y=-100000.;shape.bounds.size.y=200000.
			for obstacle:Dictionary in occupied:
				if Foot.overlaps(shape,obstacle,0.):return fail("road_house_clearance","入户路端帽或通行范围尚未退出住宅及门窗开合包络")
	return {"ok":true}

static func _kerb_shapes(record:Dictionary)->Array:
	var result:Array=[]
	var pose:=Transform3D(Basis.from_euler(Data.vec(record.rotation)*PI/180),Data.vec(record.position))
	for kerb:Dictionary in record.get("road_mesh",{}).get("kerbs",[]):
		var points:Array[Vector3]=[]
		for point:Array in kerb.a+kerb.b:points.append(pose*Data.vec(point))
		result.append(Foot.from_points(points))
	return result

static func _kerb_bridge_intersects(kerb:Dictionary,bridge:Dictionary,cache:Dictionary)->bool:
	# Use the complete kerb's conservative vertical prism as a temporary road
	# volume. The shared frozen-triangle refinement only opens outside-deck
	# approach space; bridge bodies and unknown collision payloads stay blocked.
	var bounds_:AABB=kerb.bounds
	var polygon:Array=[]
	for point:Vector2 in kerb.polygon:polygon.append([point.x,point.y])
	if polygon.size()>1 and polygon[0]==polygon[-1]:polygon.pop_back()
	var volume:Dictionary={"rotation":[0,0,0],"position":[0,bounds_.get_center().y,0],"size":[1,bounds_.size.y,1],"road_mesh":{"polygons":[polygon]},"road_clearance":0.}
	return BridgeApproach.intersects(volume,bridge,[kerb],Foot.record_shape(bridge),cache)

static func _candidate_clearance(prepared:Dictionary,doc,house_shapes:Array)->Dictionary:
	var zones_meta:Dictionary={"editor_layout":{"zones":doc.map_meta.get("editor_layout",{}).get("zones",[]).filter(func(z):return z.purpose=="no_build")}}
	var zones:Array=preload("res://scripts/world3d/planning_zones.gd").obstacles(zones_meta)
	var poly=preload("res://scripts/world3d/roof_plan.gd")
	var bridge_cache:Dictionary={}
	for record:Dictionary in prepared.records:
		var previous:Dictionary=doc._find(record.uuid)
		if _same(record,previous):continue
		var kerbs:=_kerb_shapes(record)
		for kerb:Dictionary in kerbs:
			if Foot.batches_overlap([kerb],house_shapes):return fail("kerb_conflict","连续路缘与住宅或门窗开合包络重叠")
			for obstacle:Dictionary in doc.records:
				if prepared.excluded.has(obstacle.uuid) or obstacle.has("terrain_mesh"):continue
				var shapes:Array=Foot.components([obstacle],Vector3.ZERO,Basis.IDENTITY) if obstacle.has("building") else Foot.record_shapes(obstacle)
				if not Foot.batches_overlap([kerb],shapes):continue
				if obstacle.has("bridge_mesh") and not _kerb_bridge_intersects(kerb,obstacle,bridge_cache):continue
				return fail("kerb_conflict","连续路缘与已有物件重叠").merged({"conflicts":[obstacle.uuid]})
		var prior_shapes:Array=[] if previous.is_empty() else Foot.record_shapes(previous)+_kerb_shapes(previous)
		for shape:Dictionary in Foot.record_shapes(record)+kerbs:
			for zone:Dictionary in zones:
				if not Foot.overlaps(shape,zone,0.):continue
				var cut:=Plan.intersection(Array(shape.polygon).slice(0,-1),Array(zone.polygon).slice(0,-1))
				var fresh:Array=[cut] if not cut.is_empty() else []
				for prior:Dictionary in prior_shapes:
					var remaining:Array=[]
					for piece:Array in fresh:remaining.append_array(poly.subtract(piece,Array(prior.polygon).slice(0,-1)))
					fresh=remaining
				var area:=0.
				for piece:Array in fresh:area+=poly.area(piece)
				if area>.000001:return fail("reserved_zone","新增道路或路缘进入禁止自动建设的保留区").merged({"conflicts":[zone.zone_id]})
	return {"ok":true}

static func _nearest_target(graph:Dictionary,ids:Array,point:Vector3)->Dictionary:
	var best:Dictionary={};var distance:=INF
	for id:String in ids:
		var target:=_target(graph,id)
		if not target.ok:return target
		var a:=Data.vec(target.a.position);var b:=Data.vec(target.b.position)
		var ab:=Vector2(b.x-a.x,b.z-a.z)
		if ab.length_squared()<.01:return fail("invalid_road","目标道路过短")
		var t:=clampf(Vector2(point.x-a.x,point.z-a.z).dot(ab)/ab.length_squared(),0.,1.)
		var projected:=a.lerp(b,t)
		if target.edge.has("controls"):
			var projection:=CurveConnection.nearest(target.edge,{target.edge.from:target.a,target.edge.to:target.b},point)
			if not projection.ok:return projection
			projected=projection.point
		var gap:=Vector2(point.x-projected.x,point.z-projected.z).length()
		if gap<distance:distance=gap;best=target
	return best if not best.is_empty() else fail("road_not_found","目标道路及其本批次拆分路段不存在")
