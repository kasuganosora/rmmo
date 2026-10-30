extends Node
## Private, cancellable target preparation. Only _publish touches live state.
signal finished(request_id:int,result:Dictionary)
const Service=preload("res://scripts/world_editor/editor_asset_preparation.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Prefabs=preload("res://scripts/world_editor/prefab_library.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Authoring=preload("res://scripts/world_editor/authoring_view.gd")
const Dependencies=preload("res://scripts/world3d/record_asset_dependencies.gd")
const Context=preload("res://scripts/world3d/prepared_record_context.gd")
const Builder=preload("res://scripts/world_editor/private_view_preparation.gd")
var editor:Node3D
var _serial:=0
var _operations:Dictionary={}
var _rebuild_wanted:=false
var work_budget_us:=2000
var profile:={"started":0,"committed":0,"cancelled":0,"failed":0,"visuals":0,"body_nodes":0,"slices":0,"visual_max_us":0,"body_max_us":0,"commit_max_us":0,"slice_max_us":0,"preparation_max_us":0,"plan_max_us":0,"begin_max_us":0,"place_entry_max_us":0,"history_entry_max_us":0,"history_plan_max_us":0,"history_plan_visits":0,"history_plans":0,"publish_max_us":0,"publish_check_max_us":0,"terrain_updates":0,"terrain_contexts":0,"terrain_boundary_vertices":0}

func snapshot()->Dictionary:return {"pending":_operations.size(),"profile":profile.duplicate()}
func _guard(canvas:String="")->Dictionary:
	return editor._gameplay.guard(canvas=="auto",canvas=="material") if is_instance_valid(editor) else {"ok":false,"error":"编辑器已关闭"}
func _context()->Dictionary:
	return {"path":editor._path,"settings":editor._authoring.settings.duplicate(true),"gravity":editor._gravity.enabled}

func rebuild()->Dictionary:
	var guard:=_guard()
	if not guard.ok:return guard
	_rebuild_wanted=false
	var target:=Doc.new();target.records=editor._doc.records.duplicate();target.map_meta=editor._doc.map_meta.duplicate(true);target._next=editor._doc._next
	return _begin({"kind":"rebuild","target":target,"records":target.records,"ids":target.records.map(func(record):return str(record.uuid)),"full":true,"ui":false,"gravity":false})

## Replace only the private brush presentation. Subscribe before cancelling the
## previous request so common native producers keep their live consumers.
func preview(target:RefCounted,ids:Array,valid:Callable,completed:Callable,canvas:String="auto")->Dictionary:
	var guard:=_guard(canvas)
	if not guard.ok:return guard
	var previous:Array=[]
	for id:int in _operations:
		if _operations[id].kind=="preview":previous.append(id)
	var records:Array=[]
	for id:String in ids:
		var record:Dictionary=target._find(id)
		if not record.is_empty():records.append(record)
	var result:=_begin({"kind":"preview","target":target,"records":records,"ids":ids,"full":false,"ui":true,"gravity":false,"preview_check":valid,"completed":completed,"canvas":canvas})
	for id:int in previous:cancel(id)
	return result

func tag_ui(id:int,cleanup:Callable=Callable())->void:
	if _operations.has(id):_operations[id].ui=true;_operations[id].ui_cleanup=cleanup

## A planner supplies values only; neither document history nor presentation is
## changed until every target visual and body can be published.
func replace(updates:Variant,removed:Variant=[],meta:Variant=null,result:Dictionary={},completed:Callable=Callable())->Dictionary:
	return commit_target(plan_replacements(editor._doc,updates,removed,meta),result,false,completed)

static func plan_replacements(document:RefCounted,updates:Variant,removed:Variant=[],meta:Variant=null)->RefCounted:
	var target:=Doc.new();target.map_meta=document.map_meta if meta==null else meta;target._next=document._next
	var erased:Dictionary={}
	for id:Variant in removed:erased[str(id)]=true
	if updates is Array:
		# Generated groups retain their established remove-then-append order.
		for record:Dictionary in updates:erased[str(record.uuid)]=true
		for record:Dictionary in document.records:
			if not erased.has(str(record.uuid)):target.records.append(record)
		target.records.append_array(updates)
	else:
		var remaining:Dictionary=updates.duplicate()
		for record:Dictionary in document.records:
			var id:=str(record.uuid)
			if remaining.has(id):target.records.append(remaining[id])
			elif not erased.has(id):target.records.append(record)
			remaining.erase(id)
		for record:Dictionary in remaining.values():target.records.append(record)
	return target

func commit_target(target:RefCounted,result:Dictionary={},full:bool=false,completed:Callable=Callable(),canvas:String="",coalesce:bool=false)->Dictionary:
	var began:=Time.get_ticks_usec();var guard:=_guard(canvas)
	if not guard.ok:return guard
	var old:Dictionary={};var ids:Array=[];var changed:Array=[]
	for record:Dictionary in editor._doc.records:old[str(record.uuid)]=record
	full=full or Authoring.Settings.resolve(editor._doc.map_meta)!=Authoring.Settings.resolve(target.map_meta)
	for record:Dictionary in target.records:
		var id:=str(record.uuid)
		if full or record!=old.get(id,{}):ids.append(id);changed.append(record)
		old.erase(id)
	ids.append_array(old.keys())
	if ids.is_empty() and target.map_meta==editor._doc.map_meta:return result.merged({"ok":true},true)
	var op:={"kind":"mutate","target":target,"records":changed,"ids":ids,"full":full,"ui":false,"gravity":false,"result":result,"completed":completed,"canvas":canvas,"coalesce":coalesce and not editor._doc._undo.is_empty()}
	profile.plan_max_us=maxi(profile.plan_max_us,Time.get_ticks_usec()-began)
	return _begin(op)

func place(entry:Dictionary,point:Vector3,ui:bool=false)->Dictionary:
	var began:=Time.get_ticks_usec()
	var result:=_place(entry,point,ui)
	profile.place_entry_max_us=maxi(profile.place_entry_max_us,Time.get_ticks_usec()-began)
	return result

func _place(entry:Dictionary,point:Vector3,ui:bool)->Dictionary:
	var began:=Time.get_ticks_usec()
	var guard:=_guard()
	if not guard.ok:return guard
	if not point.is_finite():return {"ok":false,"error":"放置位置不合法"}
	if ui:cancel_ui()
	var plan:Dictionary
	var prefab_sha:=""
	if entry.has("prefab_path"):
		var loaded:=Prefabs.read(entry)
		if not loaded.ok:return loaded
		var limit:=10000 if ui else 256
		if loaded.records.size()>limit:return {"ok":false,"error":"预制件超过 %d 个构件"%limit}
		var material_validation:Dictionary={}
		for record:Dictionary in loaded.records:
			var issue:String=preload("res://scripts/world3d/document_open_cursor.gd").asset_record_issue(record,material_validation)
			if not issue.is_empty():return {"ok":false,"error":issue}
		prefab_sha=loaded.source_sha
		if editor._gravity.enabled and not loaded.building_instances.is_empty():return {"ok":false,"error":"建筑预制件请关闭重力放置后使用建筑摆放"}
		plan=Prefabs.plan_place(editor._doc,loaded,point,str(entry.get("label","预制件")))
	else:
		var local:=Doc.new();local._next=editor._doc._next
		var id:=local.add_asset(entry,point-Vector3(0,float(entry.get("bounds_position",[0,0,0])[1]),0))
		plan={"ok":true,"ids":[id],"records":local.records,"next":local._next,"meta":editor._doc.map_meta}
	if not plan.ok:return plan
	var target:=Doc.new();target.records=editor._doc.records.duplicate();target.records.append_array(plan.records)
	target.map_meta=plan.meta;target._next=plan.next
	profile.plan_max_us=maxi(profile.plan_max_us,Time.get_ticks_usec()-began)
	return _begin({"kind":"place","target":target,"records":plan.records,"ids":plan.ids,"ui":ui,"entry":entry.duplicate(true),"prefab_sha":prefab_sha,"gravity":editor._gravity.enabled,"full":false})

## Only native-bearing replacements need asynchronous history preparation.
## Cheap property/pose/material transactions keep their existing incremental path.
func history(redo:bool)->Dictionary:
	var began:=Time.get_ticks_usec()
	var result:=_history(redo)
	profile.history_entry_max_us=maxi(profile.history_entry_max_us,Time.get_ticks_usec()-began)
	return result

func _history(redo:bool)->Dictionary:
	cancel_all("撤销或重做已取消未发布的操作")
	var guard:=_guard()
	if not guard.ok:return guard
	var history_:Array=editor._doc._redo if redo else editor._doc._undo
	if history_.is_empty():return {"ok":true,"sync":true}
	var head:Variant=history_.back()
	var records:Array=head.records if head is Dictionary else head
	var meta:Dictionary=head.map_meta if head is Dictionary else editor._doc.map_meta
	var began:=Time.get_ticks_usec()
	var plan:=_history_plan(records,meta)
	profile.history_plans+=1
	profile.history_plan_max_us=maxi(profile.history_plan_max_us,Time.get_ticks_usec()-began)
	if plan.fast:return {"ok":true,"sync":true,"plan":plan}
	var target:=Doc.new();target.records=records;target.map_meta=meta
	# Rendering helpers receive private record dictionaries, not history owners.
	target.records=records.duplicate()
	var planned:Dictionary={}
	for record:Dictionary in plan.records:planned[str(record.uuid)]=record.duplicate(true)
	for i:int in target.records.size():
		if planned.has(str(target.records[i].uuid)):target.records[i]=planned[str(target.records[i].uuid)]
	plan.records=planned.values()
	target.map_meta=meta.duplicate(true)
	target._next=maxi(editor._doc._next,int(head.next)) if head is Dictionary else editor._doc._next
	return _begin({"kind":"redo" if redo else "undo","target":target,"records":plan.records,"ids":plan.ids,"full":plan.full,"head":head,"ui":false,"gravity":false})

func _history_plan(records:Array,meta:Dictionary)->Dictionary:
	var current:Array=editor._doc.records
	var old_meta:Dictionary=editor._doc.map_meta.duplicate();var next_meta:=meta.duplicate()
	old_meta.erase("building_instances");next_meta.erase("building_instances")
	var full:=old_meta!=next_meta
	var ordered:=current.size()==records.size()
	var properties:bool=ordered and editor._doc.map_meta==meta
	var poses:bool=ordered and not full and not editor._authoring.settings.isolation
	var materials:bool=properties
	var old_buildings:Dictionary=editor._doc.map_meta.get("building_instances",{})
	var next_buildings:Dictionary=meta.get("building_instances",{})
	var indices:Array=[];var visibility_changed:=false
	if old_buildings.size()!=next_buildings.size():poses=false
	if poses:
		for key:String in old_buildings:
			if not next_buildings.has(key):poses=false;break
			var a:Dictionary=old_buildings[key].duplicate();var b:Dictionary=next_buildings[key].duplicate()
			for field:String in ["position","yaw","signatures"]:a.erase(field);b.erase(field)
			if a!=b:poses=false;break
	if ordered:
		for i:int in records.size():
			profile.history_plan_visits+=1
			var a:Dictionary=current[i];var b:Dictionary=records[i]
			if a.uuid!=b.uuid:properties=false;poses=false;materials=false;break
			if a==b:continue
			indices.append(i)
			visibility_changed=visibility_changed or a.get("editor_hidden",false)!=b.get("editor_hidden",false)
			if properties:
				var left:=a.duplicate();var right:=b.duplicate()
				for field:String in ["editor_name","editor_group_name","editor_hidden","editor_locked"]:left.erase(field);right.erase(field)
				properties=left==right
			if poses:
				if ["terrain_mesh","road_mesh","channel_mesh","rock_bank"].any(func(field):return b.has(field)):poses=false
				else:
					var left:=a.duplicate();var right:=b.duplicate()
					for field:String in ["position","rotation"]:left.erase(field);right.erase(field)
					if left.has("building") and right.has("building"):
						left.building=left.building.duplicate();right.building=right.building.duplicate()
						left.building.erase("floor_y");right.building.erase("floor_y")
					poses=left==right and editor._view.get_node_or_null(NodePath(str(b.uuid)))!=null
			if materials:
				var left:=a.duplicate();var right:=b.duplicate()
				for field:String in ["terrain_regions","terrain_material","terrain_saturation"]:left.erase(field);right.erase(field)
				materials=a.has("terrain_mesh") and b.has("terrain_mesh") and left==right
	if properties or poses or materials:return {"fast":true,"mode":"properties" if properties else ("poses" if poses else "materials"),"indices":indices,"visibility_changed":visibility_changed}
	var old:Dictionary={}
	for record:Dictionary in current:
		profile.history_plan_visits+=1;old[str(record.uuid)]=record
	var ids:Array=[];var changed:Array=[]
	var native_change:=false
	for record:Dictionary in records:
		profile.history_plan_visits+=1
		var id:=str(record.uuid);var previous:Dictionary=old.get(id,{})
		if full or previous!=record:
			ids.append(id);changed.append(record)
			if Dependencies.has_models(record):
				native_change=true
		old.erase(id)
	ids.append_array(old.keys())
	return {"fast":not native_change,"mode":"full" if full else "records","records":changed,"ids":ids,"full":full}

static func _model(record:Dictionary)->bool:
	return record.get("kind")=="asset" and not record.has("house_prefab") and not record.has("bridge_mesh")

func _begin(op:Dictionary)->Dictionary:
	var began:=Time.get_ticks_usec()
	_serial+=1;var id:=_serial;profile.started+=1
	op.placed_records=op.records;op.placed_ids=op.ids
	op.records=op.records.duplicate();op.ids=op.ids.duplicate()
	op.started_usec=Time.get_ticks_usec();op.before=[];op.snapshot_cursor=0;op.metadata_cursor=0;op.work={"visuals":0,"body_nodes":0}
	op.merge({"id":id,"document":editor._doc,"revision":editor._doc.authoring_revision,"next":editor._doc._next,"context":_context(),"phase":"waiting","request":0,"handles":{},"visuals":{},"bodies":{},"cursor":0,"nodes":[],"root":Node3D.new(),"shapes":editor._picking_shapes.fork(),"transport":Callable()})
	op.authoring=Authoring.new();op.authoring.settings=Authoring.Settings.resolve(op.target.map_meta)
	if op.full:op.root.free();op.root=op.target.export_root([])
	# Native-only changes borrow immutable contexts. Terrain edits fork only the
	# incremental indices; unchanged Images and contexts remain shared/read-only.
	var live:RefCounted=editor._doc.terrain_neighbors
	var terrain_changed:=false
	for record:Dictionary in op.records:
		if record.has("terrain_mesh") and live.edge_cache.get(str(record.uuid),{}).get("signature",[])!=[record.position,record.rotation,record.size,record.terrain_mesh]:terrain_changed=true;break
	if not terrain_changed:
		for uuid:String in op.ids:
			if live.sources.has(uuid) and op.target._find(uuid).is_empty():terrain_changed=true;break
	var neighbors:Array=[]
	if terrain_changed:
		var staged:RefCounted=op.target.terrain_neighbors
		staged.data=live.data.duplicate();staged.signature=live.signature;staged.sources=live.sources.duplicate()
		staged.edge_cache=live.edge_cache.duplicate(true);staged.point_index=live.point_index.duplicate(true);staged.dependents=live.dependents.duplicate(true)
		neighbors=staged.update(op.target.records)
		profile.terrain_updates+=1;profile.terrain_contexts+=int(staged.last_work.get("contexts",0));profile.terrain_boundary_vertices+=int(staged.last_work.get("boundary_vertices",0))
	else:op.target.terrain_neighbors=live
	op.terrain_context_ready=true
	var affected:Dictionary={}
	for record:Dictionary in op.records:affected[str(record.uuid)]=true
	for uuid:String in neighbors:
		if not affected.has(uuid):
			var record:Dictionary=op.target._find(uuid)
			if not record.is_empty():op.records.append(record);op.ids.append(uuid)
	var paths:Array=Dependencies.paths(op.records)
	_operations[id]=op;set_process(true)
	op.banner_imports={};op.banner_owners=[]
	if not _prepare_banner_sources(op):return {"ok":false,"error":"旗帜贴图准备无法启动"}
	if paths.is_empty():
		op.synchronous=true
		_prepared(0,{"ok":true,"handles":{}},id)
		if _operations.has(id):_advance(op,Time.get_ticks_usec()+work_budget_us)
		op.synchronous=false
		profile.begin_max_us=maxi(profile.begin_max_us,Time.get_ticks_usec()-began)
		if op.has("completion"):return op.completion
		return {"ok":true,"pending":true,"operation":"prepared_view","request_id":id}
	var service:Node=Service.for_consumer(self)
	if service==null:_finish(id,{"ok":false,"error":"模型准备服务不可用"});return {"ok":false,"error":"模型准备服务不可用"}
	op.service=service
	op.request=service.request_many(paths,self,_prepared.bind(id))
	if op.request==0:_finish(id,{"ok":false,"error":"模型准备任务无法启动"});return {"ok":false,"error":"模型准备任务无法启动"}
	profile.begin_max_us=maxi(profile.begin_max_us,Time.get_ticks_usec()-began)
	return {"ok":true,"pending":true,"operation":"prepared_view","request_id":id}

func _prepare_banner_sources(op:Dictionary)->bool:
	# New authoring choices import once through the existing shared producer and
	# ledger. History/rebuild already holds immutable published texture paths.
	if op.kind!="mutate":return true
	var requested:Dictionary={};var root_:=preload("res://scripts/world3d/map_paths.gd").external_root()
	for record:Dictionary in op.records:
		if record.get("banner",{}).get("design","") not in ["flag","emblem"]:continue
		var path:String=record.banner.material.texture_path
		if not preload("res://scripts/world3d/streamed_texture_source.gd").plan_imported(path,false,false,root_).is_empty():continue
		requested[path]=true
	if requested.is_empty():return true
	var service:Node=editor._surface_texture_imports
	if not service.finished.is_connected(_banner_imported):service.finished.connect(_banner_imported)
	var library:=preload("res://scripts/world_editor/surface_material_library.gd").new(root_.path_join("assets/banner_streetlamp/designs"))
	for path:String in requested:
		var result:Dictionary=service.submit(library,path,"旗帜图案","source")
		if not result.get("ok",false):_finish(op.id,result);return false
		op.banner_imports[result.request_id]=path
	return true

func _banner_imported(request:int,result:Dictionary)->void:
	for id:int in _operations.keys():
		var op:Dictionary=_operations[id]
		if not op.get("banner_imports",{}).has(request):continue
		var source:String=op.banner_imports[request];op.banner_imports.erase(request)
		if not result.get("ok",false):_finish(id,result);return
		if not _current(op):cancel(id,"旗帜准备期间文档或保护上下文已变化");return
		for record:Dictionary in op.records:
			if record.get("banner",{}).get("material",{}).get("texture_path","")==source:
				record.banner.material.texture_path=result.material.texture_path
		var owner:=preload("res://scripts/world3d/surface_materials.gd").retained_texture(str(result.material.texture_path))
		if owner!=null:op.banner_owners.append(owner)
		return

func bind_transport(id:int,check:Callable)->void:
	if _operations.has(id):_operations[id].transport=check
func _current(op:Dictionary)->bool:
	if not is_instance_valid(editor) or not editor.is_inside_tree() or editor._doc!=op.document:return false
	if editor._doc.authoring_revision!=op.revision or editor._doc._next!=op.next or _context()!=op.context:return false
	if not _guard(op.get("canvas","")).ok:return false
	if op.kind=="preview" and (not op.preview_check.is_valid() or not op.preview_check.call()):return false
	if op.transport.is_valid() and not op.transport.call():return false
	if op.kind in ["undo","redo"]:
		var history_:Array=editor._doc._undo if op.kind=="undo" else editor._doc._redo
		if history_.is_empty() or not is_same(history_.back(),op.head):return false
	return true
func _prepared(_request:int,result:Dictionary,id:int)->void:
	if not _operations.has(id):return
	var op:Dictionary=_operations[id];op.request=0
	if not result.get("ok",false):_finish(id,result);return
	if not _current(op):
		_retain_stale_rebuild(op)
		cancel(id,"文档、保护上下文或请求已变化");return
	op.handles=result.handles;op.phase="building"
	var templates:Dictionary={}
	for path:String in op.handles:templates[path]=op.handles[path].packed
	op.prepared_context=Context.new(templates)
	profile.preparation_max_us=maxi(profile.preparation_max_us,Time.get_ticks_usec()-int(op.started_usec))

func _process(_delta:float)->void:
	var deadline:=Time.get_ticks_usec()+work_budget_us
	for id:int in _operations.keys():
		if not _operations.has(id):continue
		var op:Dictionary=_operations[id]
		if not _current(op):
			_retain_stale_rebuild(op)
			cancel(id,"文档、保护上下文或请求已变化");continue
		if op.phase!="building":continue
		_advance(op,deadline)
		if Time.get_ticks_usec()>=deadline:break
	if not _operations.is_empty():return
	set_process(false)
	# A whole-view rebuild holds no authored change of its own: when a concurrent
	# transaction invalidates it, the old view is still displayed while the
	# document already carries that transaction. Retry once the editor is quiet so
	# the presentation cannot stay behind the authored records.
	if _rebuild_wanted and is_instance_valid(editor) and editor.is_inside_tree() and not editor._load_failed:
		_rebuild_wanted=false
		editor.call_deferred("_rebuild")

## A cancelled view-only rebuild must converge; every other operation is
## transactional and re-planning it would duplicate authored work.
func _retain_stale_rebuild(op:Dictionary)->void:
	if op.kind!="rebuild" or not is_instance_valid(editor) or editor._doc!=op.document:return
	if not _guard().ok:return
	_rebuild_wanted=true

func _advance(op:Dictionary,deadline:int)->void:
	if not op.get("banner_imports",{}).is_empty():return
	var id:int=op.id
	profile.slices+=1
	var slice_started:=Time.get_ticks_usec()
	var advanced:=false
	while _operations.has(id) and (not advanced or Time.get_ticks_usec()<deadline):
		advanced=true
		if op.kind in ["place","mutate"] and not op.get("coalesce",false) and op.snapshot_cursor<op.document.records.size():
			op.before.append(op.document.records[op.snapshot_cursor].duplicate(true));op.snapshot_cursor+=1
		elif op.full and op.metadata_cursor<op.target.records.size():
			op.root.get_meta("extras").rmmo_records.append(op.target.records[op.metadata_cursor].duplicate(true));op.metadata_cursor+=1
		elif not op.nodes.is_empty():
			var began:=Time.get_ticks_usec();var valid:=_body_step(op)
			profile.body_max_us=maxi(profile.body_max_us,Time.get_ticks_usec()-began)
			if not valid:_finish(id,{"ok":false,"error":"模型碰撞准备失败"});break
		elif op.cursor<op.records.size():
			var began:=Time.get_ticks_usec();var valid:=_visual_step(op)
			profile.visual_max_us=maxi(profile.visual_max_us,Time.get_ticks_usec()-began)
			if not valid:_finish(id,{"ok":false,"error":"模型实例准备失败，原文档保持不变"});break
		else:_publish(op);break
	profile.slice_max_us=maxi(profile.slice_max_us,Time.get_ticks_usec()-slice_started)

func _visual_step(op:Dictionary)->bool:
	var valid:=Builder.visual_step(op,editor)
	profile.visuals+=op.work.visuals;op.work.visuals=0
	return valid
func _body_step(op:Dictionary)->bool:
	var valid:=Builder.body_step(op,editor)
	profile.body_nodes+=op.work.body_nodes;op.work.body_nodes=0
	return valid

func _publish(op:Dictionary)->void:
	var began:=Time.get_ticks_usec()
	_publish_checked(op)
	profile.publish_max_us=maxi(profile.publish_max_us,Time.get_ticks_usec()-began)

func _publication_check(op:Dictionary)->Dictionary:
	if not _current(op):return {"ok":false,"cancelled":true,"error":"文档、保护上下文或请求已变化"}
	for handle:RefCounted in op.handles.values():
		if not handle.current():return {"ok":false,"error":"模型原生产物已变化"}
	if op.kind=="place" and not op.prefab_sha.is_empty() and FileAccess.get_sha256(str(op.entry.prefab_path))!=op.prefab_sha:
		return {"ok":false,"error":"预制件已变化"}
	var landing:Dictionary={}
	if op.gravity:
		landing=editor._gravity.landing(op.placed_records)
		if not landing.ok:return landing
	# Last transport check is immediately before the non-yielding commit.
	if not _current(op):return {"ok":false,"cancelled":true,"error":"操作已失效"}
	return {"ok":true,"landing":landing}

func _publish_checked(op:Dictionary)->void:
	var check_started:=Time.get_ticks_usec()
	var validation:=_publication_check(op)
	profile.publish_check_max_us=maxi(profile.publish_check_max_us,Time.get_ticks_usec()-check_started)
	if not validation.ok:
		if validation.get("cancelled",false):cancel(op.id,validation.error)
		else:_finish(op.id,validation)
		return
	var commit_started:=Time.get_ticks_usec()
	if op.kind=="preview":
		var preview_root:Node3D=op.root;op.root=Node3D.new()
		op.completed.call(preview_root,op.ids)
		_finish(op.id,{"ok":true})
		return
	var before:Array=op.before
	var dirty_before:bool=editor._dirty
	var selected:Array=editor._selection_tools.ids.duplicate()
	if op.kind=="place":
		if not op.gravity:
			if op.target.map_meta!=editor._doc.map_meta:editor._doc.checkpoint_recovery()
			else:editor._doc.commit_owned_snapshot(before);before=[]
		editor._doc.records=op.target.records;editor._doc.map_meta=op.target.map_meta;editor._doc._next=op.target._next
	elif op.kind in ["undo","redo"]:
		if op.kind=="undo":editor._doc.undo()
		else:editor._doc.redo()
	elif op.kind=="mutate":
		if op.get("coalesce",false):editor._doc.authoring_revision+=1;editor._doc._redo.clear()
		elif op.target.map_meta!=editor._doc.map_meta:editor._doc.checkpoint_recovery()
		else:editor._doc.commit_owned_snapshot(before);before=[]
		editor._doc.records=op.target.records;editor._doc.map_meta=op.target.map_meta;editor._doc._next=op.target._next
		editor._dirty=true
	editor._doc.terrain_neighbors=op.target.terrain_neighbors
	editor._publish_prepared_records(op)
	editor._picking_shapes.adopt(op.shapes)
	if op.kind=="rebuild":editor._dirty=dirty_before
	if op.kind=="place":editor._selection_tools.set_ids(op.placed_ids)
	else:editor._selection_tools.refresh()
	if op.gravity:editor._gravity.start_prepared(op.placed_records,before,op.next,selected,dirty_before,validation.landing.distance,op.placed_ids)
	profile.committed+=1
	profile.commit_max_us=maxi(profile.commit_max_us,Time.get_ticks_usec()-commit_started)
	var result:Dictionary=op.get("result",{}).merged({"ok":true,"ids":op.placed_ids if op.kind=="place" else op.ids,"gravity_falling":op.gravity},true)
	if op.get("completed",Callable()).is_valid():op.completed.call(result)
	_finish(op.id,result)

func cancel(id:int,reason:String="操作已取消")->bool:
	if not _operations.has(id):return false
	profile.cancelled+=1;_finish(id,{"ok":false,"cancelled":true,"error":reason});return true
func cancel_all(reason:String="操作已取消")->void:
	for id:int in _operations.keys():cancel(id,reason)
func cancel_ui()->void:
	for id:int in _operations.keys():
		if _operations[id].ui:cancel(id)

## Authored operations hold the only copy of pending document changes. Save,
## undo/redo and playtest must wait for them instead of cancelling the edit.
func authored_pending()->int:
	var count:=0
	for id:int in _operations:
		if _operations[id].kind in ["place","mutate","undo","redo"]:count+=1
	return count

## Presentation-only operations can be dropped without losing authored work.
func cancel_presentation()->void:
	for id:int in _operations.keys():
		if _operations[id].kind in ["preview","rebuild"]:cancel(id)
func _finish(id:int,result:Dictionary)->void:
	if not _operations.has(id):return
	var op:Dictionary=_operations[id];_operations.erase(id)
	if op.request!=0 and is_instance_valid(op.get("service")):op.service.cancel(op.request)
	if is_instance_valid(editor) and is_instance_valid(editor._surface_texture_imports):
		for request:int in op.get("banner_imports",{}):editor._surface_texture_imports.cancel(request)
	op.get("banner_owners",[]).clear()
	for bodies:Array in op.bodies.values():
		for body:Node in bodies:
			if is_instance_valid(body) and body.get_parent()==null:body.free()
	Drainer.dispose_scene(op.root);op.handles.clear();op.visuals.clear();op.bodies.clear();op.prepared_context=null
	if op.get("ui_cleanup",Callable()).is_valid():op.ui_cleanup.call(result)
	if not result.get("ok",false) and not result.get("cancelled",false):profile.failed+=1
	if op.kind=="preview" and not result.get("ok",false) and not result.get("cancelled",false) and is_instance_valid(editor):editor._status.text=str(result.get("error","预览准备失败"))
	if op.ui and op.kind!="preview" and is_instance_valid(editor) and editor._status!=null:editor._status.text="已更新，可撤销" if result.get("ok",false) else str(result.get("error","操作失败"))
	if op.get("synchronous",false):op.completion=result
	else:finished.emit(id,result)
func _exit_tree()->void:cancel_all("编辑器已关闭")
