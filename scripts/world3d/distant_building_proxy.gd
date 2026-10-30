extends Node3D
## Bounded exact-material HLOD per building. Source floor/roof/door semantics
## remain independent. Visibility/pose/source replacement invalidates at once.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Geometry=preload("res://scripts/world3d/ground_batch_geometry.gd")
const Lod=preload("res://scripts/world3d/render_lod_preparation.gd")
const Retirement=preload("res://scripts/world3d/cpu_worker_retirement.gd")
static var enabled:=true
const ENTER_M=240.
const EXIT_M=200.
const MAX_VERTICES=65536
const MAX_PROXIES=32
var profile:Dictionary={"prepared":0,"active":0,"invalidated":0,"source_draws":0,"proxy_draws":0,"last_wait":"","near_snapshot_skips":0,"snapshot_attempts":0}
var _rows:Dictionary={}
var _job:Dictionary={}
var _cooldown:Dictionary={} # Scalar retry times, never rejected mesh owners.
var _clock:=0.
var _switching:=false
func _ready()->void:set_meta("stream_instance",true)
func _process(delta:float)->void:
	_poll()
	_clock+=delta
	if _clock<.25:return
	_clock=0.
	var camera:=get_viewport().get_camera_3d()
	if camera!=null:tick(camera.global_position)
func tick(origin:Vector3)->void:
	if not _job.is_empty() and _job.row.bounds.get_center().distance_to(origin)<EXIT_M:_job.cancelled=true
	var batcher:=get_parent().get_node_or_null("GroundRenderBatches")
	if batcher==null:return
	var candidates:Dictionary={};var material_keys:Dictionary={}
	for group:Dictionary in batcher.groups.values():
		if group.category!="building" or group.get("moving",false) or not is_instance_valid(group.get("visual")) or not group.visual is MeshInstance3D:continue
		var record:Dictionary=group.members[0].get_meta("ground_batch_record",{})
		if not record.has("building") or record.has("fixture"):continue
		if group.visual.global_position.distance_to(origin)<EXIT_M-128.:continue
		if not _eligible(group.visual,material_keys):continue
		var id:String=_cohort(record,group.visual)
		if not candidates.has(id):candidates[id]=[]
		candidates[id].append(group)
	# Frozen floor/roof meshes keep their authored LOD and selection semantics
	# outside the ordinary batcher. Include opaque static nodes directly.
	for node:Variant in get_parent().get_meta("stream_meshes",{}).values():
		if not node is MeshInstance3D or node.mesh==null or node.mesh is Cpu or node.has_meta("ground_render_batch"):continue
		var record:Dictionary=node.get_meta("ground_batch_record",{})
		if not record.has("building") or record.has("fixture") or not record.has("house_prefab"):continue
		if node.global_position.distance_to(origin)<EXIT_M-128.:continue
		if not _eligible(node,material_keys):continue
		var id:String=_cohort(record,node)
		if not candidates.has(id):candidates[id]=[]
		candidates[id].append({"visual":node,"members":[node]})
	for id:String in _rows.keys():
		var row:Dictionary=_rows[id]
		if not enabled or not _current(row,candidates.get(id,[])) or row.bounds.get_center().distance_to(origin)<EXIT_M:_drop(id)
	if not enabled or not _job.is_empty():return
	for id:String in candidates:
		if _rows.has(id) or _rows.size()>=MAX_PROXIES:continue
		if int(_cooldown.get(id,0))>Time.get_ticks_msec():continue
		var groups:Array=candidates[id]
		if groups.size()<2:continue
		if groups[0].visual.global_position.distance_to(origin)<ENTER_M-128.:continue
		# A source node's origin only gives a conservative first filter. Check
		# the complete cohort bounds before capturing arrays or material hashes.
		var bounds:Variant=_candidate_bounds(groups)
		if bounds==null:profile.last_wait="snapshot_rejected";_retry_later(id);continue
		if bounds.get_center().distance_to(origin)<ENTER_M:
			profile.near_snapshot_skips+=1;continue
		profile.snapshot_attempts+=1
		var row:=_snapshot(groups)
		if row.is_empty():profile.last_wait="snapshot_rejected";_retry_later(id);continue
		if row.bounds.get_center().distance_to(origin)<ENTER_M:continue
		var thread:=Thread.new();var lease:=Retirement.watch(thread,get_tree(),[row])
		if lease.is_empty():return
		var task:=_prepare.bind(row.sources,row.origin)
		if thread.start(task)!=OK:Retirement.complete(lease);return
		_job={"id":id,"thread":thread,"lease":lease,"row":row};return
static func _eligible(visual:MeshInstance3D,keys:Dictionary={})->bool:
	if visual.material_override!=null or visual.material_overlay!=null:return false
	if visual.mesh==null:return false
	for slot in visual.mesh.get_surface_count():
		var material:Material=visual.mesh.surface_get_material(slot)
		if not material is StandardMaterial3D:return false
		var id:int=material.get_instance_id()
		if not keys.has(id):keys[id]=Geometry.material_supported(material)
		if not keys[id]:return false
	return true

static func _candidate_bounds(groups:Array)->Variant:
	var bounds:=AABB();var first:=true
	for group:Dictionary in groups:
		var visual:MeshInstance3D=group.visual
		if not is_instance_valid(visual) or not visual.visible or visual.mesh==null:return null
		var box:AABB=visual.global_transform*visual.mesh.get_aabb()
		bounds=box if first else bounds.merge(box);first=false
		if maxf(bounds.size.x,bounds.size.z)>128.:return null
	return null if first else bounds
func _retry_later(id:String)->void:
	if _cooldown.size()>=512:_cooldown.clear()
	_cooldown[id]=Time.get_ticks_msec()+5000
static func _cohort(record:Dictionary,visual:MeshInstance3D)->String:
	return str([record.building.id,visual.get_meta("distant_proxy_layers",visual.layers),visual.cast_shadow])
static func _snapshot(groups:Array)->Dictionary:
	var row:={"sources":[],"visuals":[],"controllers":[],"members":[],"poses":[],"bounds":AABB(),"origin":Vector3.ZERO,"callbacks":[],"watchers":[]}
	var vertices:=0;var draws:=0;var first:=true
	for group:Dictionary in groups:
		var visual:MeshInstance3D=group.visual
		if not visual.visible or visual.material_override!=null or visual.material_overlay!=null or visual.mesh==null:return {}
		var cpu:Mesh=Cpu.capture(visual.mesh);var keys:Array=[]
		for material:Material in cpu.materials:
			if not material is StandardMaterial3D:return {}
			var key:=Geometry.material_key(material)
			if key.is_empty():return {}
			keys.append(key)
		vertices+=Geometry.vertex_count(cpu);draws+=cpu.surfaces.size()
		if vertices>MAX_VERTICES:return {}
		var box:AABB=visual.global_transform*cpu.get_aabb()
		row.bounds=box if first else row.bounds.merge(box);first=false
		if maxf(row.bounds.size.x,row.bounds.size.z)>128.:return {}
		row.sources.append({"record":{"building":{}},"surfaces":cpu.surfaces,"materials":cpu.materials,"keys":keys,"transform":visual.global_transform})
		row.visuals.append(weakref(visual));row.poses.append(visual.global_transform)
		row.controllers.append(weakref(group.members[0]))
		for member:Node3D in group.members:
			if not member.is_visible_in_tree():return {}
			row.members.append(weakref(member))
	row.origin=row.bounds.get_center();row.draws=draws
	row.layers=groups[0].visual.layers;row.shadow=groups[0].visual.cast_shadow
	for group:Dictionary in groups:
		if group.visual.layers!=row.layers or group.visual.cast_shadow!=row.shadow:return {}
	return row
static func _prepare(sources:Array,origin:Vector3)->Dictionary:
	var data:=Geometry.build_fortification(sources,origin,true);data.compressed=false
	var arrays:Array=[]
	for slot:Dictionary in data.slots:arrays.append(slot.arrays)
	var lod:=Lod.derive(arrays)
	if not lod.is_empty():
		for i in data.slots.size():data.slots[i].lods=lod.lods[i]
	data.lod=lod
	return data
func _current(row:Dictionary,groups:Array)->bool:
	if groups.size()!=row.visuals.size():return false
	for i in groups.size():
		var visual:Node3D=row.visuals[i].get_ref()
		if not is_instance_valid(visual) or groups[i].visual!=visual or visual.global_transform!=row.poses[i]:return false
	for ref:WeakRef in row.members:
		var node:Node3D=ref.get_ref()
		if not is_instance_valid(node) or not node.is_visible_in_tree():return false
	return true
func _poll()->void:
	if _job.is_empty() or _job.thread.is_alive():return
	var data:Dictionary=_job.thread.wait_to_finish();Retirement.complete(_job.lease)
	var id:String=_job.id;var row:Dictionary=_job.row;var cancelled:bool=_job.get("cancelled",false);_job={}
	if cancelled:return
	for i in row.visuals.size():
		var visual:Node3D=row.visuals[i].get_ref()
		if not is_instance_valid(visual) or not visual.visible or visual.global_transform!=row.poses[i]:return
	for ref:WeakRef in row.members:
		var node:Node3D=ref.get_ref()
		if not is_instance_valid(node) or not node.is_visible_in_tree():return
	if not enabled or data.slots.size()>=row.draws:profile.last_wait="no_draw_reduction";_retry_later(id);return
	var uploaded:=Geometry.upload(data)
	if uploaded.is_empty():return
	var proxy:=MeshInstance3D.new();proxy.mesh=uploaded.mesh;proxy.layers=row.layers;proxy.cast_shadow=row.shadow;proxy.position=row.origin;proxy.lod_bias=2.;proxy.set_meta("ground_render_batch",true);add_child(proxy)
	row.proxy=proxy;row.lod=data.get("lod",{}).duplicate();row.lod.erase("lods");row.erase("sources");_rows[id]=row
	for ref:WeakRef in row.members:
		var node:Node3D=ref.get_ref();var callback:=_invalidate.bind(id)
		node.visibility_changed.connect(callback);node.tree_exiting.connect(callback,CONNECT_ONE_SHOT);row.callbacks.append({"node":ref,"callback":callback})
	for ref:WeakRef in row.visuals:
		var visual:Node3D=ref.get_ref();var callback:=_invalidate.bind(id)
		if not visual.tree_exiting.is_connected(callback):visual.tree_exiting.connect(callback,CONNECT_ONE_SHOT);row.callbacks.append({"node":ref,"callback":callback})
		var watcher:=preload("res://scripts/world3d/batch_transform_watch.gd").new();visual.add_child(watcher);watcher.changed=_invalidate.bind(id);row.watchers.append(weakref(watcher))
	_switching=true
	for ref:WeakRef in row.visuals:
		ref.get_ref().set_meta("distant_proxy_layers",row.layers);ref.get_ref().layers=0
	_switching=false
	profile.prepared+=1;profile.active=_rows.size();profile.source_draws+=row.draws;profile.proxy_draws+=uploaded.mesh.get_surface_count();profile.last_wait=""
func _invalidate(id:String)->void:
	if not _switching:_drop(id)
func _drop(id:String)->void:
	if not _rows.has(id):return
	var row:Dictionary=_rows[id];_rows.erase(id);_switching=true
	for callback:Dictionary in row.callbacks:
		var node:Node3D=callback.node.get_ref()
		if not is_instance_valid(node):continue
		if node.visibility_changed.is_connected(callback.callback):node.visibility_changed.disconnect(callback.callback)
		if node.tree_exiting.is_connected(callback.callback):node.tree_exiting.disconnect(callback.callback)
	for ref:WeakRef in row.watchers:
		var watcher:Node=ref.get_ref()
		if is_instance_valid(watcher):watcher.changed=Callable();watcher.queue_free()
	for i in row.visuals.size():
		var visual:Node3D=row.visuals[i].get_ref();var source:Node3D=row.controllers[i].get_ref()
		if is_instance_valid(visual):
			visual.remove_meta("distant_proxy_layers")
			visual.layers=row.layers
			visual.visible=is_instance_valid(source) and source.is_visible_in_tree()
	# This also runs inside transform/visibility notifications. Withdraw now,
	# destroy after the engine finishes iterating its Node3D notification list.
	row.proxy.hide();row.proxy.queue_free();_switching=false;profile.active=_rows.size();profile.invalidated+=1
func clear()->void:
	_cooldown.clear()
	if not _job.is_empty():_job.cancelled=true
	for id:String in _rows.keys():_drop(id)
func _exit_tree()->void:
	clear()
	if not _job.is_empty():Retirement.abandon(_job.lease);_job={}
