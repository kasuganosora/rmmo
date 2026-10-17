extends "res://scripts/world_editor/residential_placement_tools.gd"
## One bounded authoring candidate: final terrain, one frozen house, access road.
## No live tool application, intermediate undo, event dispatch or async rollback.
const Placement=preload("res://scripts/world_editor/residential_placement_tools.gd")
const Layout=preload("res://scripts/world_editor/terrain_layout_tools.gd")
const Ramp=preload("res://scripts/world_editor/terrain_ramp_tools.gd")
const MAX_STEPS:=64

class Context extends Layout.Stage:
	var _path:String
	var _city
	var _gameplay
	func setup(value:Node3D)->void:
		super.setup(value);_path=value._path;_city=value._city;_gameplay=value._gameplay
	func asset_items(query:String="",category:String="")->Array:return source.asset_items(query,category)

static func schema()->Dictionary:
	var terrain:=Layout.schema().duplicate(true)
	terrain.required=[];terrain.properties.strokes.minItems=0;terrain.properties.strokes.maxItems=MAX_STEPS
	for key:String in ["radius","hardness","iterations","talus_angle","erosion_seed"]:terrain.properties.strokes.items.properties.erase(key)
	var ramp:=Ramp.schema().duplicate(true);ramp.properties.erase("expected_token")
	terrain.properties.ramp=ramp
	return Data.object({"residential":Placement.request_schema(),"terrain":terrain},["residential","terrain"])

static func stage_failure(result:Dictionary,stage:String)->Dictionary:
	return fail(str(result.get("code","site_constraint")),str(result.get("error","联合候选未通过")),stage).merged({"last_failure":result})

static func delta(before,after)->Dictionary:
	var added:Array=[];var updated:Array=[];var removed:Array=[];var terrain:Array=[];var roads:Array=[];var followers:Array=[]
	var prior:Dictionary={};var current:Dictionary={}
	for record:Dictionary in before.records:prior[record.uuid]=record
	for record:Dictionary in after.records:
		current[record.uuid]=record
		if not prior.has(record.uuid):added.append(record.uuid)
		elif not Placement._same(record,prior[record.uuid]):updated.append(record.uuid)
	for id:String in prior:
		if not current.has(id):removed.append(id)
	for id:String in added+updated+removed:
		var record:Dictionary=current.get(id,prior.get(id,{}))
		if record.has("terrain_mesh"):terrain.append(id)
		elif record.has("road_source"):roads.append(id)
		elif prior.has(id):followers.append(id)
	return {"added":added,"updated":updated,"removed":removed,"terrain_ids":terrain,"road_ids":roads,"follower_ids":followers}

func preview(args:Dictionary)->Dictionary:
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	if _publishing:return fail("busy","正在发布联合候选")
	var issue:=Data.S.validate(args,schema())
	if not issue.is_empty():return fail("invalid_arguments",issue,"site_request")
	var terrain:Dictionary=args.terrain.duplicate(true);var strokes:Array=terrain.get("strokes",[])
	var steps:int=strokes.size()+(1 if terrain.has("ramp") else 0)
	if steps<1 or steps>MAX_STEPS:return fail("invalid_arguments","联合候选需要 1–64 项整地操作（含可选坡道）","site_request")
	var version:=_version();var request_id:=Data.token(args)
	if not _candidate.is_empty() and _candidate.request_id==request_id and _candidate.summary.base_version==version and _dependencies_current(_candidate.dependencies):return _candidate.summary.duplicate(true)
	_candidate={}
	if not Data.valid(editor._doc.map_meta):return fail("site_constraint","现有道路或河道关联无效","terrain")
	var bridges:=BridgeContext.capture(editor,Data.resolve(editor._doc.map_meta))
	if not bridges.ok:return bridges
	# Pin source dependencies before any terrain/material preparation. Candidate
	# dependencies may only add new resources, never replace an earlier identity.
	var dependencies:Dictionary={}
	issue=_dependencies(editor._doc.records,dependencies)
	if not issue.is_empty():return fail("resource_missing",issue,"resource")
	var ramp_recipe:Dictionary={}
	if terrain.has("ramp"):
		ramp_recipe=Ramp.recipe(editor,terrain.ramp)
		if not ramp_recipe.ok:return stage_failure(ramp_recipe,"terrain_ramp")
		strokes.append(ramp_recipe.stroke)
	var layout_args:Dictionary=terrain.duplicate(true);layout_args.erase("ramp");layout_args.strokes=strokes
	var stage:=Context.new();stage.setup(editor)
	# Schema and 64-step cap were checked above. Shared prepare_stage counts the
	# aggregate work budget and validates the FINAL terrain before any followers.
	var prepared:=Layout.prepare_stage(editor,stage,layout_args)
	if not prepared.ok:stage.free();return stage_failure(prepared,"terrain")
	if not ramp_recipe.is_empty():
		var proof:=Ramp.prove(editor._doc,stage._doc,terrain.ramp,ramp_recipe,prepared.terrain_ids)
		if not proof.ok:stage.free();return stage_failure(proof,"terrain_ramp")
		prepared.ramp=proof
	var earthwork:=Ramp.earthwork(editor._doc,stage._doc,prepared.terrain_ids)
	var residential:=Placement.new();residential.editor=stage
	var house:=residential.preview(args.residential)
	if not house.ok:stage.free();return stage_failure(house,"residential")
	var after:Dictionary=residential._candidate.after
	for path:String in residential._candidate.dependencies:
		var sha:String=residential._candidate.dependencies[path]
		if dependencies.has(path) and dependencies[path]!=sha:stage.free();return fail("source_changed","准备期间资源已变化，请重新预览","resource")
		dependencies[path]=sha
	stage._doc.apply_recovery(after)
	var preserved:=BridgeContext.verify(stage._doc,Data.resolve(stage._doc.map_meta),bridges)
	if not preserved.ok:stage.free();return preserved
	if stage._doc.validate_save()!=OK:stage.free();return fail("candidate_invalid","联合候选未通过原生保存校验","save_validation")
	var changes:=delta(editor._doc,stage._doc)
	var changed:Array=changes.added+changes.updated+changes.removed
	var visual:Array=stage._doc.records.filter(func(r):return r.uuid in changed)
	var final_dependencies:Dictionary={};issue=_dependencies(visual,final_dependencies)
	for path:String in final_dependencies:
		if dependencies.has(path) and dependencies[path]!=final_dependencies[path]:stage.free();return fail("source_changed","准备期间资源已变化，请重新预览","resource")
		dependencies[path]=final_dependencies[path]
	if not issue.is_empty():stage.free();return fail("resource_missing",issue,"resource")
	var bounds:=Geometry.bounds(visual)
	var summary:Dictionary=house.duplicate(true)
	summary.merge({"plan_token":Crypto.new().generate_random_bytes(24).hex_encode(),"base_version":version,"changed_ids":changed,"changes":changes,"earthwork":earthwork,"terrain":Layout.public_result(prepared),"terrain_operation_count":steps,"bounds":{"position":Data.xyz(bounds.position),"size":Data.xyz(bounds.size)},"publication":{"authoring":"single_synchronous_transaction","derived":"native_refresh_and_shared_batches","runtime":"requires_runtime_verification"}},true)
	summary.checks.final_terrain=true;summary.checks.final_combined_save=true
	stage.free()
	if _version()!=version or not _dependencies_current(dependencies):return fail("base_changed","地图或资源已变化，请重新预览")
	_candidate={"summary":summary,"request_id":request_id,"dependencies":dependencies,"after":after,"integrity":Data.token(after),"visual":visual}
	return summary.duplicate(true)

func apply(args:Dictionary)->Dictionary:
	# All fallible authoring validation stays BEFORE the synchronous live swap.
	# A late invalid candidate never needs rollback over a subsequent edit.
	if not _candidate.is_empty() and args.get("plan_token")==_candidate.summary.plan_token:
		var doc:=Doc.new();doc.apply_recovery(_candidate.after)
		if Data.token(_candidate.after)!=_candidate.integrity or doc.validate_save()!=OK:
			_candidate={};return fail("candidate_invalid","联合候选发布前校验失败，地图保持原状","publication")
	var result:=super.apply(args)
	if result.ok and editor._terrain_panel!=null:editor._terrain_panel.refresh()
	return result
