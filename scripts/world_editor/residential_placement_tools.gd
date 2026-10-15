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
const STEP=.05
const MAX_CANDIDATES=157
var editor:Node3D
var _candidate:Dictionary={}
var _publishing:=false
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
	var source:Node3D
	func _record_editable(record:Dictionary)->bool:return source._record_editable(record)

static func defaults()->Dictionary:
	return {"yaw":0.0,"elevation_min":-.5,"elevation_max":.5,"setback_min":.8,"setback_max":3.0,"width":1.6}

static func request_schema()->Dictionary:
	return Data.object({"asset_id":Data.text(2048),"position":Data.S.vector(-100000,100000),"road_edge_id":Data.text(),"yaw":Data.S.number(-180,180),"elevation_min":Data.S.number(-3,0),"elevation_max":Data.S.number(0,3),"setback_min":Data.S.number(.2,8),"setback_max":Data.S.number(.2,8),"width":Data.S.number(1,4)},["asset_id","position","road_edge_id"])

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
	var entries:Array=editor.asset_items().filter(func(e):return Thumbnails.key_for(e)==p.asset_id and e.has("prefab_path"))
	if entries.size()!=1:return fail("asset_not_found","请选择资源库中的冻结住宅预制件")
	var entry:Dictionary=entries[0]
	if not Paths.allowed(entry.prefab_path) or not FileAccess.file_exists(entry.prefab_path):return fail("resource_missing","住宅资源超出资源根或不存在")
	var source_sha:=FileAccess.get_sha256(entry.prefab_path)
	var base_version:=_version()
	var request_id:=Data.token(p)
	if not _candidate.is_empty() and _candidate.request_id==request_id and _candidate.summary.base_version==base_version and _candidate.summary.source_sha256==source_sha and _dependencies_current(_candidate.dependencies):
		_profile_end("lookup_identity",phase)
		if profile_enabled:last_profile.cached=true
		return _candidate.summary.duplicate(true)
	_profile_end("lookup_identity",phase);phase=_profile_start()
	_candidate={}
	var started:=Time.get_ticks_usec()
	var loaded:=Prefabs.read(entry)
	if not loaded.ok:return loaded.merged({"code":"invalid_prefab","stage":"resource"})
	if loaded.building_instances.size()!=1:return fail("unsupported","当前闭环需要恰好一栋冻结住宅")
	var instance:Dictionary=loaded.building_instances.values()[0]
	if not instance.get("baked",false) or instance.parameters.get("layout") not in ["townhouse","hall"] or instance.parameters.get("template")!="house":return fail("unsupported","当前支持 townhouse / hall 的单栋冻结住宅；请选择住宅模板")
	if loaded.records.any(func(r):return not r.has("building") or not r.get("prefab_locked",false)):return fail("unsupported","住宅包含未冻结或无归属构件")
	var dependencies:Dictionary={entry.prefab_path:source_sha}
	var dependency_issue:=_dependencies(loaded.records,dependencies)
	if not dependency_issue.is_empty():return fail("resource_missing",dependency_issue,"resource")
	var data:=Data.resolve(editor._doc.map_meta)
	if not data.has("road_surface") or not data.road_surface.settings.get("follow_terrain",false):return fail("unsupported","请先生成沿地形的已有道路铺面，再连接住宅")
	if data.road_surface.graph_token!=Data.token(data.roads):return fail("stale_road_surface","道路草案与铺面不一致，请先完成已有道路生成")
	if data.roads.edges.any(func(e):return e.has("bridge_ref") or e.has("stone_bridge")):return fail("unsupported","此版本不在含桥梁绑定的道路图中求解住宅接路")
	var road_check:=_target(data.roads,p.road_edge_id)
	if not road_check.ok:return road_check
	var local:=_oriented(loaded,float(p.yaw))
	var input:=Data.vec(p.position)
	_profile_end("source_and_target",phase);phase=_profile_start()
	var solved:=Support.solve(editor._doc,loaded.records,input,float(p.yaw),instance.parameters,{"min_y":input.y+p.elevation_min,"max_y":input.y+p.elevation_max,"input_version":base_version})
	_profile_end("support",phase);phase=_profile_start()
	if not solved.ok:return solved
	var position:Vector3=solved.position
	var initial_records:=_translated(local.records,position)
	var initial_entry:=Access.entrance(initial_records,float(instance.yaw)+float(p.yaw))
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
	var placed:=Prefabs.place_buildings(staged,local,position,str(entry.get("label","住宅")))
	if not placed.ok:return placed.merged({"code":"placement_conflict","stage":"house_geometry"})
	var house_records:Array=[]
	for id:String in placed.ids:house_records.append(staged._find(id))
	for r:Dictionary in house_records:
		if not editor._authoring.Settings.contains(r,editor._authoring.settings):return fail("protected_scope","住宅落在当前隔离楼层外")
	var entry_info:=Access.entrance(house_records,float(instance.yaw)+float(p.yaw))
	_profile_end("native_house_placement",phase);phase=_profile_start()
	if not entry_info.ok:return entry_info
	var context:=PreparationContext.new();context.source=editor;context._doc=staged;context._authoring=editor._authoring;context._material_tool=editor._material_tool
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
		linked=_connect(data,road_check,entry_info,setback,p.width,request_id.left(14))
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
	scope=scope.grow(maxf(maxf(road_check.edge.width_start,road_check.edge.width_end),p.width)+32.)
	for r:Dictionary in before.records:
		if r.has("road_source") and changed.has(r.uuid):
			var bounds_:AABB=Geometry.bounds([r])
			if not scope.intersects(Rect2(bounds_.position.x,bounds_.position.z,bounds_.size.x,bounds_.size.z),true):return fail("scope_conflict","候选会改变接路范围以外的道路铺面，已保留原地图")
	var bounds:=Geometry.bounds(house_records)
	var token:=Crypto.new().generate_random_bytes(24).hex_encode()
	var summary:Dictionary={"ok":true,"plan_token":token,"source_sha256":source_sha,"base_version":base_version,"position":Data.xyz(position),"adjustment":Data.xyz(position-input),"road_points":linked.points,"setback":linked.setback,"width":p.width,"building_id":house_records[0].building.id,"building_ids":[house_records[0].building.id],"house_ids":placed.ids,"changed_ids":changed,"support":solved.support,"access":access,"bounds":{"position":Data.xyz(bounds.position),"size":Data.xyz(bounds.size)},"checks":{"continuous_support":true,"native_house_geometry":true,"full_road_graph":true,"entrance_corridor":true,"native_save":true,"runtime_traversal":"requires_runtime_verification"},"search":{"attempts":attempts,"full_graph_checks":full_graph_checks,"budget":count,"step":STEP,"prepare_ms":(Time.get_ticks_usec()-started)/1000.}}
	_profile_end("result",phase);phase=_profile_start()
	var current:=base_version==_version() and _dependencies_current(dependencies)
	_profile_end("final_identity",phase);phase=_profile_start()
	if not current:return fail("base_changed","输入或资源已变化，请重新预览")
	_candidate={"summary":summary,"request_id":request_id,"dependencies":dependencies,"after":staged.recovery_snapshot(),"visual":visual}
	_profile_end("candidate_snapshot",phase)
	return summary.duplicate(true)

func apply(args:Dictionary)->Dictionary:
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	if _publishing:return fail("busy","正在发布住宅候选")
	if args.size()!=1 or not args.get("plan_token") is String:return fail("invalid_arguments","应用只接受预览返回的 plan_token")
	if _candidate.is_empty() or args.plan_token!=_candidate.summary.plan_token:return fail("candidate_missing","候选已放弃或不存在，请重新预览")
	if not _dependencies_current(_candidate.dependencies):_candidate={};return fail("source_changed","住宅或材质资源已变化，请重新预览")
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

static func _target(graph:Dictionary,id:String)->Dictionary:
	var rows:Array=graph.edges.filter(func(e):return e.id==id)
	if rows.size()!=1:return fail("road_not_found","目标道路不存在")
	var edge:Dictionary=rows[0]
	if edge.kind!="ground" or edge.has("controls"):return fail("unsupported","当前接路目标需要普通直线地面道路")
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
	if Vector2(end.x-start.x,end.z-start.z).length()<1 or (end-start).dot(out)<.1:return fail("access_direction","目标道路位于入口背后或退距超过接路位置")
	var prefix:="home_"+key;var join:String=prefix+"_join"
	if t<.001:join=target.edge.from;end=a
	elif t>.999:join=target.edge.to;end=b
	else:
		var old_to:String=target.edge.to;var mid_width:float=lerpf(target.edge.width_start,target.edge.width_end,t)
		for e:Dictionary in graph.edges:
			if e.id==target.edge.id:e.to=join;e.width_end=mid_width
		var tail:Dictionary=target.edge.duplicate(true);tail.id=prefix+"_tail";tail.from=join;tail.to=old_to;tail.width_start=mid_width
		graph.edges.append(tail);graph.nodes.append({"id":join,"position":Data.xyz(end)})
	for edge:Dictionary in original.roads.edges:
		if join in [edge.from,edge.to] and (edge.get("locked",false) or edge.get("hidden",false)):return fail("protected_scope","接驳节点关联了受保护道路")
	# Terrain-following pavement uses the true heightfield, not this guide's Y.
	start.y=end.y
	graph.nodes.append({"id":prefix+"_door","position":Data.xyz(start)})
	graph.edges.append({"id":prefix+"_access","from":prefix+"_door","to":join,"name":"住宅入户路","kind":"ground","width_start":width,"width_end":width})
	var checked:=Data.analyze(graph)
	if not checked.ok:return checked
	return {"ok":true,"data":data,"points":[Data.xyz(start),Data.xyz(end)],"setback":setback}

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

static func _candidate_clearance(prepared:Dictionary,doc,house_shapes:Array)->Dictionary:
	var zones_meta:Dictionary={"editor_layout":{"zones":doc.map_meta.get("editor_layout",{}).get("zones",[]).filter(func(z):return z.purpose=="no_build")}}
	var zones:Array=preload("res://scripts/world3d/planning_zones.gd").obstacles(zones_meta)
	var poly=preload("res://scripts/world3d/roof_plan.gd")
	for record:Dictionary in prepared.records:
		var previous:Dictionary=doc._find(record.uuid)
		if _same(record,previous):continue
		var kerbs:=_kerb_shapes(record)
		for kerb:Dictionary in kerbs:
			if Foot.batches_overlap([kerb],house_shapes):return fail("kerb_conflict","连续路缘与住宅或门窗开合包络重叠")
			for obstacle:Dictionary in doc.records:
				if prepared.excluded.has(obstacle.uuid) or obstacle.has("terrain_mesh"):continue
				var shapes:Array=Foot.components([obstacle],Vector3.ZERO,Basis.IDENTITY) if obstacle.has("building") else Foot.record_shapes(obstacle)
				if Foot.batches_overlap([kerb],shapes):return fail("kerb_conflict","连续路缘与已有物件重叠").merged({"conflicts":[obstacle.uuid]})
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
