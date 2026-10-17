extends "res://scripts/world_editor/residential_site_tools.gd"
## Explicit native operations, staged in order; never arbitrary MCP dispatch.
const NativeSchema=preload("res://scripts/world_editor/mcp_schema.gd")
const Stage=preload("res://scripts/world_editor/joint_candidate_context.gd")
const ResidentialBlock=preload("res://scripts/world_editor/residential_block_tools.gd")
const LIMIT_BYTES:=268435456
const LIMIT_OBJECTS:=8192
const OPERATIONS={
	"apply_terrain_layout":"联合整地", "apply_terrain_ramp":"两端定高坡道",
	"update_road_graph":"道路节点与线段", "create_road_path":"新道路路径",
	"generate_road_surface":"道路铺面", "update_planning_zones":"保留区",
	"preview_residential_placement":"住宅与入户路", "preview_residential_site":"整地与住宅",
	"preview_residential_relocation":"已有住宅迁移", "preview_residential_block":"多户联合安放",
	"generate_block_buildings":"沿街地块住宅", "preview_block_update":"已有街区更新",
	"generate_waterway":"河道与河岸", "generate_bridge":"桥梁",
	"connect_waterway_bridge":"河道桥梁接路", "generate_fortification":"城防",
	"generate_vegetation_scatter":"区域植被"
}

static func catalog()->Array:
	var result:Array=[]
	for tool:Dictionary in NativeSchema.native_tools():
		if not OPERATIONS.has(tool.name):continue
		var spec:Dictionary=tool.inputSchema.duplicate(true)
		# Standalone preview tokens identify another document. The outer token
		# pins this entire request; explicit graph tokens still pin the base.
		spec.properties.erase("plan_token")
		if tool.name=="apply_terrain_ramp":spec.properties.erase("expected_token")
		result.append({"operation":tool.name,"title":OPERATIONS[tool.name],"input_schema":spec})
	return result

static func joint_schema()->Dictionary:
	var fields:Dictionary={"id":Data.text(80)}
	for item:Dictionary in catalog():fields[item.operation]=item.input_schema
	return Data.object({"steps":Data.array(Data.object(fields,["id"]),MAX_STEPS,1)},["steps"])

static func operation(step:Dictionary)->String:
	# Dot assignments in native UI create StringName keys; JSON uses String.
	# Array.erase("id") does not remove &"id" on current Godot versions.
	var keys:Array[String]=[]
	for key:Variant in step:
		if str(key)!="id":keys.append(str(key))
	return keys[0] if keys.size()==1 and OPERATIONS.has(keys[0]) else ""

static func step_failure(result:Dictionary,step:Dictionary,index:int)->Dictionary:
	return stage_failure(result,"joint_step").merged({"step_id":step.id,"step_index":index,"operation":operation(step),"completed_steps":index})

func _pin(args:Dictionary,base:Dictionary,current:Dictionary,zones:bool=false)->String:
	# Compare all caller tokens with the ORIGINAL graph, then bind the checked
	# operation to its predecessor's private result. Never silently drop a token.
	for key:String in args:
		if key in ["expected_token","expected_road_token"]:
			var before:String=JSON.stringify(base.get("zones",[])).sha256_text() if zones else Data.token(base.roads)
			if args[key]!=before:return "步骤的道路或保留区版本已过期，请重新读取后预览"
			args[key]=JSON.stringify(current.get("zones",[])).sha256_text() if zones else Data.token(current.roads)
		elif args[key] is Dictionary:
			var error:=_pin(args[key],base,current)
			if not error.is_empty():return error
	return ""

func _run(stage:Node3D,name:String,args:Dictionary)->Dictionary:
	match name:
		"apply_terrain_layout":return Layout.apply(stage,args)
		"apply_terrain_ramp":return Ramp.apply(stage,args)
		"update_road_graph":return stage._city.update_roads(args)
		"create_road_path":return stage._city.add_path(args.points,args.get("width",8.),args.get("kind","ground"))
		"generate_road_surface":return stage._roads.generate(args)
		"update_planning_zones":return stage._roads.zones(args)
		"generate_block_buildings":return stage._blocks.generate(args)
		"generate_waterway":return stage._waterways.generate(args)
		"generate_bridge":return stage._bridges.generate(args)
		"connect_waterway_bridge":return stage._connections.connect_bridge(args.waterway_id,args.bridge_id)
		"generate_fortification":return stage._fortifications.generate(args)
		"generate_vegetation_scatter":return stage._scatter.generate(args)
	var service:RefCounted
	match name:
		"preview_residential_placement":service=Placement.new()
		"preview_residential_site":service=load("res://scripts/world_editor/residential_site_tools.gd").new()
		"preview_residential_relocation":service=preload("res://scripts/world_editor/residential_relocation_tools.gd").new()
		"preview_residential_block":service=ResidentialBlock.new()
		"preview_block_update":service=stage._block_update
		_:return fail("unsupported_operation","不支持此联合步骤")
	service.editor=stage
	var result:Dictionary=service.preview(args)
	if result.ok:
		stage._doc.apply_recovery(service._candidate.after)
		result["_dependencies"]=service._candidate.dependencies.duplicate(true)
	return result

static func merge_dependencies(source:Dictionary,target:Dictionary)->String:
	for path:String in source:
		if target.has(path) and target[path]!=source[path]:return "准备期间资源发生变化："+path
		target[path]=source[path]
	return ""

func preview(args:Dictionary)->Dictionary:
	var ready:Dictionary=editor._city.guard()
	if not ready.ok:return ready
	if _publishing:return fail("busy","正在发布联合候选")
	var error:=NativeSchema.validate(args,joint_schema())
	if not error.is_empty():return fail("invalid_arguments",error)
	var version:=_version();var request_id:=Data.token(args)
	if not _candidate.is_empty() and _candidate.request_id==request_id and _candidate.summary.base_version==version and _dependencies_current(_candidate.dependencies):return _candidate.summary.duplicate(true)
	_candidate={}
	if var_to_bytes(editor._doc.recovery_snapshot()).size()>LIMIT_BYTES:return fail("budget_exceeded","地图超过联合候选的 256 MiB 私有快照上限，请分区")
	var stage:=Stage.new();stage.setup(editor)
	var result:=_prepare(stage,args)
	stage.free()
	if not result.ok:return result
	if version!=_version() or not _dependencies_current(result.dependencies):return fail("base_changed","地图或资源已变化，请重新预览")
	result.summary.base_version=version
	_candidate={"request_id":request_id,"summary":result.summary,"after":result.after,"integrity":Data.token(result.after),"dependencies":result.dependencies,"visual":result.visual}
	return result.summary.duplicate(true)

func _prepare(stage:Node3D,args:Dictionary)->Dictionary:
	if editor._doc.validate_save()!=OK:return fail("invalid_document","原地图未通过保存校验")
	var dependencies:Dictionary={};var error:=_dependencies(editor._doc.records,dependencies)
	if not error.is_empty():return fail("resource_missing",error)
	var base:=Data.resolve(editor._doc.map_meta);var seen:Dictionary={};var reports:Array=[]
	var homes:Array=[];var rows:Array=[];var ramps:Array=[];var work:=0;var cells:=0;var terrain_count:=0;var home_count:=0
	for i:int in args.steps.size():
		var step:Dictionary=args.steps[i];var name:=operation(step)
		if step.id.strip_edges().is_empty() or seen.has(step.id) or name.is_empty():return step_failure(fail("invalid_arguments","每步需要唯一非空 id，且恰好一个受支持操作"),step,i)
		seen[step.id]=true
		var values:Dictionary=step[name].duplicate(true)
		error=_pin(values,base,Data.resolve(stage._doc.map_meta),name=="update_planning_zones")
		if not error.is_empty():return step_failure(fail("stale_input",error),step,i)
		var terrain:Dictionary=values if name=="apply_terrain_layout" else values.get("terrain",{})
		var strokes:Array=terrain.get("strokes",[]).duplicate()
		if terrain.has("ramp"):strokes.append(terrain.ramp)
		if name=="apply_terrain_ramp":strokes.append(values)
		if name=="apply_terrain_ramp":ramps.append({"id":step.id,"request":values})
		elif terrain.has("ramp"):ramps.append({"id":step.id,"request":terrain.ramp})
		terrain_count+=strokes.size()
		for stroke:Dictionary in strokes:
			for record:Dictionary in stage._doc.records:
				if not record.has("terrain_mesh") or (record.uuid!=stroke.id and not stroke.get("cross_tiles",true)):continue
				var t:Dictionary=record.terrain_mesh
				work+=(int(t.columns)+1)*(int(t.rows)+1)
		if terrain_count>64 or work>Layout.MAX_WORK_VERTICES:return step_failure(fail("budget_exceeded","整组最多 64 次整地、200 万主地形采样预算"),step,i)
		var before:=Doc.new();before.apply_recovery(stage._doc.recovery_snapshot())
		var result:=_run(stage,name,values)
		if not result.ok:return step_failure(result,step,i)
		cells+=int(result.get("changed_cells",result.get("terrain",{}).get("changed_cells",0)))
		if cells>Layout.MAX_CHANGED_CELLS:return step_failure(fail("budget_exceeded","整组变化格超过 262144"),step,i)
		error=merge_dependencies(result.get("_dependencies",{}),dependencies)
		if not error.is_empty():return step_failure(fail("source_changed",error),step,i)
		var resource:Dictionary={};error=_dependencies(stage._doc.records,resource)
		if not error.is_empty():return step_failure(fail("resource_missing",error),step,i)
		error=merge_dependencies(resource,dependencies)
		if not error.is_empty():return step_failure(fail("source_changed",error),step,i)
		result.erase("_dependencies")
		var change:=delta(before,stage._doc)
		var count:int=change.added.size()+change.updated.size()+change.removed.size()
		if count>LIMIT_OBJECTS or var_to_bytes(stage._doc.recovery_snapshot()).size()>LIMIT_BYTES:return step_failure(fail("budget_exceeded","联合候选超过 8192 个变化构件或 256 MiB 快照上限"),step,i)
		home_count+=result.get("building_ids",result.get("updated_building_ids",[])).size()
		if home_count>16:return step_failure(fail("budget_exceeded","整组最多生成或迁移 16 栋住宅"),step,i)
		if name=="preview_residential_block":
			for h in result.homes.size():remember_home(homes,rows,result.homes[h],values.homes[h])
		elif name in ["preview_residential_placement","preview_residential_site","preview_residential_relocation"]:
			remember_home(homes,rows,result,{"id":step.id,"residential":values.get("residential",values)})
		reports.append({"id":step.id,"operation":name,"title":OPERATIONS[name],"changes":change,"result":result})
		# A native operation may checkpoint. Its private history must not retain
		# 32 full maps, nor can it evict the live outer undo baseline.
		stage._doc._undo.clear();stage._doc._redo.clear();stage._city.refresh()
	var before_final:=Doc.new();before_final.apply_recovery(stage._doc.recovery_snapshot())
	var final:=_validate_final(stage,homes,rows,ramps)
	if not final.ok:return stage_failure(final,"joint_final").merged({"steps":reports})
	var finalization_changes:=delta(before_final,stage._doc)
	# Keep the order and exact records of untouched author objects.
	var remaining:Dictionary={};var ordered:Array=[]
	for record:Dictionary in stage._doc.records:remaining[record.uuid]=record
	for record:Dictionary in editor._doc.records:
		if remaining.has(record.uuid):ordered.append(remaining[record.uuid]);remaining.erase(record.uuid)
	ordered.append_array(remaining.values());stage._doc.records=ordered
	if stage._doc.validate_save()!=OK:return fail("candidate_invalid","最终联合候选未通过原生保存校验","joint_final")
	var changes:=delta(editor._doc,stage._doc);var changed:Array=changes.added+changes.updated+changes.removed
	if changed.size()>LIMIT_OBJECTS:return fail("budget_exceeded","整组变化构件超过 8192 个")
	var visual:Array=stage._doc.records.filter(func(r):return r.uuid in changed)
	var resources:Dictionary={};error=_dependencies(stage._doc.records,resources)
	if not error.is_empty():return fail("resource_missing",error)
	error=merge_dependencies(resources,dependencies)
	if not error.is_empty():return fail("source_changed",error)
	if var_to_bytes(stage._doc.recovery_snapshot()).size()>LIMIT_BYTES:return fail("budget_exceeded","最终快照超过 256 MiB")
	var bounds:=Geometry.bounds(visual+editor._doc.records.filter(func(r):return r.uuid in changes.removed))
	var summary:Dictionary={"ok":true,"plan_token":Crypto.new().generate_random_bytes(24).hex_encode(),"steps":reports,"step_count":reports.size(),"changed_ids":changed,"changes":changes,"house_ids":visual.filter(func(r):return r.has("building")).map(func(r):return r.uuid),"changed":not changed.is_empty() or not _same(editor._doc.map_meta,stage._doc.map_meta),"bounds":{"position":Data.xyz(bounds.position),"size":Data.xyz(bounds.size)},"checks":final,"terrain_operation_count":terrain_count,"publication":{"authoring":"single_synchronous_transaction","derived":"native_refresh_and_shared_batches","runtime":"requires_runtime_verification"}}
	summary.finalization_changes=finalization_changes
	return {"ok":true,"summary":summary,"dependencies":dependencies,"after":stage._doc.recovery_snapshot(),"visual":visual}

static func remember_home(homes:Array,rows:Array,home:Dictionary,row:Dictionary)->void:
	for i in homes.size():
		if homes[i].building_id==home.building_id:homes[i]=home;rows[i]=row;return
	homes.append(home);rows.append(row)

func _validate_final(stage:Node3D,homes:Array,rows:Array,ramps:Array=[])->Dictionary:
	var data:=Data.resolve(stage._doc.map_meta)
	for ramp:Dictionary in ramps:
		var recipe:=Ramp.recipe(stage,ramp.request)
		if not recipe.ok:return recipe.merged({"invalidated_step_id":ramp.id})
		var proof:=Ramp.prove(stage._doc,stage._doc,ramp.request,recipe,[])
		if not proof.ok:return proof.merged({"invalidated_step_id":ramp.id})
	# Rebuild the COMPLETE graph against final geometry, including later tools.
	if data.has("road_surface") or not data.roads.edges.is_empty():
		var roads:Dictionary=stage._roads.generate({})
		if not roads.ok:return roads
	var bridges:=BridgeContext.capture(stage,Data.resolve(stage._doc.map_meta))
	if not bridges.ok:return bridges
	for region:Dictionary in data.get("vegetation",[]):
		var vegetation:Dictionary=stage._scatter.prepare(region.settings)
		if not vegetation.ok:return vegetation
		if not _same(vegetation.manifest,region):return fail("vegetation_invalidated","后续操作改变植被承托或避让结果，请将该区域植被更新排在相关操作之后").merged({"region_id":region.settings.id,"conflicts":region.parts.map(func(p):return p.id)})
	var changes:=delta(editor._doc,stage._doc)
	var affected:Array=changes.added+changes.updated+changes.removed
	var volumes:Array=[]
	for doc in [editor._doc,stage._doc]:
		for r:Dictionary in doc.records:
			if r.uuid in affected:volumes.append(Geometry.bounds([r]).grow(.01))
	var zones_changed:bool=not _same(Data.resolve(editor._doc.map_meta).get("zones",[]),data.get("zones",[]))
	var registry:Dictionary=stage._doc.map_meta.get("building_instances",{})
	var affected_buildings:Array=[]
	for id:String in registry:
		var members:Array=stage._doc.records.filter(func(r):return r.get("building",{}).get("id","")==id)
		var bounds:=Geometry.bounds(members).grow(8.)
		if zones_changed or volumes.any(func(volume):return volume.intersects(bounds)) or members.any(func(r):return r.uuid in affected):affected_buildings.append(id)
		else:continue
		# Previously guaranteed entrances also participate when a later tool
		# touches them. Match their saved door endpoint to actual entrance axes,
		# never assume the first doorway of a multi-entrance/arcade building.
		var value:Dictionary=registry[id]
		if not value.has("residential_access") or homes.any(func(h):return h.building_id==id):continue
		var receipt:Dictionary=value.residential_access;var matches:Array=[]
		for choice:Dictionary in Access.entrances(members,value.yaw):
			var entry:=Access.entrance(members,value.yaw,choice.id)
			if not entry.ok:continue
			var offset:Vector3=Data.vec(receipt.door.position)-entry.position
			var setback:float=offset.dot(entry.outward)
			if setback>.19 and setback<=8.01 and absf(offset.dot(entry.side))<.02:matches.append({"entry":entry,"setback":setback})
		if matches.size()!=1:return fail("entrance_unresolved","受影响住宅的既有入口无法唯一恢复，请将住宅重新接路纳入联合候选").merged({"building_id":id})
		homes.append({"building_id":id,"house_ids":members.map(func(r):return r.uuid),"road_points":[receipt.door.position,receipt.join.position],"width":receipt.edge.width_start,"setback":matches[0].setback,"checks":{}})
		rows.append({"id":id,"residential":{"position":value.position,"entrance_id":matches[0].entry.entrance_id}})
	# Recheck every staged residential receipt after all later operations.
	if not homes.is_empty():
		var proof:=ResidentialBlock.verify_final(stage,homes,rows)
		if not proof.ok:return proof
	# A later reservation/river/structure may invalidate an earlier block. A
	# native no-motion reflow validates all retained lots, access and support.
	if not data.get("block_layout",{}).get("lots",[]).is_empty():
		var block:Dictionary=stage._block_update.preview({})
		if not block.ok:return block
		if not block.updated_building_ids.is_empty():return fail("stale_block","最终道路仍需移动街区，请加入已有街区更新步骤")
		# A no-motion refresh may still update a legacy anchor or source token.
		# Keep that derived metadata together with the verified final graph.
		if block.changed:stage._doc.apply_recovery(stage._block_update._candidate.after)
	for id:String in affected_buildings:
		var members:Array=stage._doc.records.filter(func(r):return r.get("building",{}).get("id","")==id)
		var without:=Doc.new();without.apply_recovery(stage._doc.recovery_snapshot());without.records=without.records.filter(func(r):return r.get("building",{}).get("id","")!=id)
		var clear:=Prefabs.check_buildings(without,members,registry,[id])
		if not clear.ok:return clear.merged({"building_id":id})
	return {"ok":true,"final_road_graph":true,"final_building_geometry":true,"final_residential_access":true,"final_block_reservations":true,"final_ramps":true,"final_vegetation":true,"bridge_context":true,"native_save":true}

func apply(args:Dictionary)->Dictionary:
	# Metadata-only candidates still dirty the document; no-op candidates must
	# not add history. Keep validation identical to native candidate apply.
	if _publishing:return fail("busy","正在发布联合候选")
	var no_change:bool=not _candidate.is_empty() and not _candidate.summary.changed
	if no_change and args.size()==1 and args.get("plan_token")==_candidate.summary.plan_token:
		var ready:Dictionary=editor._city.guard()
		if not ready.ok:return ready
		if _version()!=_candidate.summary.base_version or not _dependencies_current(_candidate.dependencies):_candidate={};return fail("base_changed","地图或资源已变化，请重新预览")
		if Data.token(_candidate.after)!=_candidate.integrity:_candidate={};return fail("candidate_invalid","候选完整性校验失败")
		var result:Dictionary=_candidate.summary.duplicate(true);_candidate={};return result
	var result:=super.apply(args)
	if result.ok:editor._dirty=true
	return result
