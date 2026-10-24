extends Node
const ModelOwners=preload("res://scripts/world3d/model_resource_owners.gd")
## Unused large templates relinquish GPU/CPU Resource owners on bounded main
## thread slices. Logical cache eviction is immediate; this queue owns disposal.
const NODE_NAME:="ResourceRetirement"
const Budget=preload("res://scripts/world3d/frame_work_budget.gd")
const IMPORT_FIELDS:Array[String]=["json","glb_data","nodes","buffers","buffer_views","accessors","meshes","materials","textures","texture_samplers","images","skins","cameras","lights","skeletons","animations","unique_names","unique_animation_names"]
const MAX_IMPORT_VALUES:=262144
static var background_byte_release_enabled:=true
static var background_geometry_release_enabled:=true
static var background_decoded_release_enabled:=true
static var geometry_size_reuse_enabled:=true
static var batched_geometry_release_enabled:=true # Diagnostic threshold-scan baseline.
static var ordered_retirement_tail_enabled:=true # Diagnostic old-batch fence control.
static var _geometry_sizes:=preload("res://scripts/world3d/cpu_geometry_size.gd").new()
const BACKGROUND_BYTE_MIN:=8*1024*1024
const CPU_GEOMETRIES_PER_BATCH:=1024
var pending:Array=[]
var known:Dictionary={}
var exiting:=false
var serial:=0
var _advancing_ticket:Dictionary={}
var _open_geometry_batch:Dictionary={}
var profile:Dictionary={"scenes":0,"imports":0,"slices":0,"max_slice_us":0,"resources":0,"import_values":0,"import_slices":0,"import_max_slice_us":0,"truncated_imports":0,"private_arrays":0,"private_values":0,"private_slices":0,"private_max_slice_us":0,"models":0,"model_values":0,"model_slices":0,"model_max_slice_us":0,"terrain_shape_arrays":0,"terrain_shape_refs":0}
static func _service()->Node:
	if not Thread.is_main_thread():return null
	var tree:SceneTree=Engine.get_main_loop() as SceneTree
	if tree==null or not is_instance_valid(tree.root) or not tree.root.is_inside_tree():return null
	var service:Node=tree.root.get_node_or_null(NODE_NAME)
	if service!=null and service.exiting:return null
	if service==null:
		service=new();service.name=NODE_NAME;service.process_mode=Node.PROCESS_MODE_ALWAYS;tree.root.add_child(service)
	return service
static func defer_scene(scene:PackedScene)->bool:
	if scene==null or not Thread.is_main_thread():return false
	# Node count does not bound native ownership: one node may own a large mesh.
	# Admit even small templates; scan/release work remains budgeted by the queue.
	var service:Node=_service()
	if service==null:return false
	service._enqueue(scene);return true
static func defer_private_array(values:Array,force_small:bool=false)->bool:
	# Only exclusively owned snapshots or completed retirement plans may donate
	# this container. Never donate an array still used by a live index/cursor.
	# Items are unreferenced, never recursively cleared or otherwise mutated.
	if values.is_empty() or (values.size()<256 and not force_small) or not Thread.is_main_thread():return false
	var service:Node=_service()
	if service==null:return false
	service._enqueue_private_array(values)
	return true
func _enqueue_private_array(values:Array)->Dictionary:
	serial+=1;var id:="private:%d"%serial
	var ticket:Dictionary={"kind":"private_array","source_id":id,"values":values}
	pending.append(ticket);known[id]=true;profile.private_arrays+=1;set_process(true)
	return ticket
static func defer_terrain_shape_owners(shapes:Variant,basis_entries:Variant)->bool:
	# Exact producer schema only: flat Shape refs from identity and <=8 basis
	# sets. Snapshot outer refs; never mutate borrowed arrays or send RIDs to CPU.
	if (shapes==null and basis_entries==null) or not Thread.is_main_thread():return false
	var service:Node=_service()
	if service==null:return false
	var values:Array=shapes.duplicate() if shapes!=null else []
	if basis_entries!=null:
		for key:String in basis_entries:values.append_array(basis_entries[key].shapes)
	if values.is_empty():return false
	var ticket:Dictionary=service._enqueue_private_array(values)
	service.profile.terrain_shape_arrays+=1;service.profile.terrain_shape_refs+=values.size()
	# Only native terrain Shape leaves inherit this fence. The producer adds
	# no CPU mesh metadata/debug-cache graph to these Shapes. This is not a
	# general Resource-graph retirement API. An inherited private tail does
	# not activate model/import context for arbitrary grandchildren.
	# Only these leaf Shape units inherit a model/import completion fence.
	# Generic private snapshots may contain other graphs and do not opt in.
	if service._advancing_ticket.get("kind","") in ["model","import"]:
		service._advancing_ticket.geometry_tail=ticket
	return true
static func defer_cpu_geometry(surfaces:Array,lods:Array,faces:PackedVector3Array,geometry_identity:String="")->bool:
	# Called from a CPU mesh's PREDELETE, after its final Resource owner is gone.
	# These schema fields contain only geometry arrays; materials/metadata and
	# GPU resources remain in the original main-thread destructor. Never clear
	# the nested arrays: other immutable CPU meshes may still borrow them.
	if not background_geometry_release_enabled or not Thread.is_main_thread():return false
	if batched_geometry_release_enabled:
		if surfaces.is_empty() and lods.is_empty() and faces.is_empty():return false
		var service:Node=_service()
		if service==null:return false
		service._enqueue_cpu_geometry(surfaces,lods,faces)
		return true
	# Material projections and restored GPU owners borrow the same immutable
	# channel/LOD identity. Retain only its scalar size, not a geometry owner.
	# Faces are lazy per mesh, so never reuse their charge through this key.
	var bytes:int=faces.size()*(24 if OS.has_feature("double") else 12)+_geometry_sizes.measure(surfaces,lods,geometry_identity if geometry_size_reuse_enabled else "")
	if bytes<BACKGROUND_BYTE_MIN:return false
	var service:Node=_service()
	if service==null:return false
	service.serial+=1;var id:="geometry:%d"%service.serial
	# Do not start a worker inside PREDELETE: the mesh's members still retain
	# these buffers until that destructor returns. The next service slice starts
	# the transfer; a shutdown drains it synchronously after all prior owners.
	var ticket:Dictionary={"kind":"cpu_geometry","source_id":id,"values":[surfaces,lods,faces],"logical_bytes":bytes,"worker":null}
	service.pending.append(ticket)
	if service._advancing_ticket.get("kind","") in ["model","import"]:
		# FIFO disposal makes the newest queued child the completion fence for
		# all children. Its parent transfers admission/callback ownership there.
		service._advancing_ticket.geometry_tail=ticket
	service.known[id]=true;service.set_process(true)
	return true
func _enqueue_cpu_geometry(surfaces:Array,lods:Array,faces:PackedVector3Array)->void:
	# The schema is already pure CPU data. Transfer roots without walking them
	# to decide a size threshold. This changes no memory-admission accounting:
	# the original model reservation still follows its final completion fence.
	var owner_id:String=str(_advancing_ticket.get("source_id",""))
	if _open_geometry_batch.is_empty() or _open_geometry_batch.owner_id!=owner_id or int(_open_geometry_batch.geometry_owners)>=CPU_GEOMETRIES_PER_BATCH:
		serial+=1;var id:="geometry:%d"%serial
		_open_geometry_batch={"kind":"cpu_geometry","source_id":id,"owner_id":owner_id,"values":[],"geometry_owners":0,"logical_bytes":0,"worker":null}
		pending.append(_open_geometry_batch);known[id]=true
		# Tail advances only when a child enters FIFO. Reusing an older batch
		# must not move the fence back ahead of newer main-thread Shape children.
		if _advancing_ticket.get("kind","") in ["model","import"]:_advancing_ticket.geometry_tail=_open_geometry_batch
	var values:Array=_open_geometry_batch.values
	values.append(surfaces);values.append(lods);values.append(faces)
	_open_geometry_batch.geometry_owners+=1
	if not ordered_retirement_tail_enabled and _advancing_ticket.get("kind","") in ["model","import"]:_advancing_ticket.geometry_tail=_open_geometry_batch
	set_process(true)

static func defer_cpu_values(values:Array,logical_bytes:int)->bool:
	# Producer contract: newly owned outer container with only decoded values,
	# never Objects/RIDs/Callables. Do not recursively clear borrowed children.
	if not background_decoded_release_enabled or values.is_empty() or not Thread.is_main_thread():return false
	var service:Node=_service()
	if service==null:return false
	service.serial+=1;var id:="cpu_values:%d"%service.serial
	service.pending.append({"kind":"cpu_geometry","source_id":id,"values":values,"logical_bytes":logical_bytes,"worker":null})
	service.known[id]=true;service.set_process(true)
	return true
static func defer_import_packet(packet:Dictionary,on_done:Callable,owner:RefCounted)->bool:
	var _scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.resource_retirement.defer_import_packet") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not Thread.is_main_thread() or not on_done.is_valid() or owner==null:return false
	var states:Array[GLTFState]=[]
	_collect_imports(packet,states,[],{})
	if states.is_empty():return false
	var service:Node=_service()
	if service==null:return false
	service._enqueue_import(states,on_done,owner);return true
static func defer_model_packet(packet:Dictionary,on_done:Callable,owner:RefCounted)->bool:
	# Runtime model producers hand over one typed owner. No graph discovery and
	# no legacy packet adapter: admission belongs to this ticket until completion.
	var resources:Variant=packet.get("resource_owners")
	if not resources is ModelOwners or not Thread.is_main_thread():return false
	var service:Node=_service()
	if service==null:return false
	packet.erase("resource_owners")
	service.serial+=1
	var id:="model:%d"%service.serial
	service.pending.append({"kind":"model","source_id":id,"resources":resources,"scene_ticket":{},"scene_queue":[],"scene_ids":{},"import_ticket":{},"on_done":on_done,"owner":owner,"phase":0})
	service.known[id]=true;service.profile.models+=1;service.set_process(true)
	return true
static func _collect_imports(value:Variant,states:Array[GLTFState],seen:Array,ids:Dictionary)->void:
	if value is GLTFState:
		if ids.has(value.get_instance_id()):return
		ids[value.get_instance_id()]=true
		# Typed GLTFState getters copy their vectors: read each one only once.
		if value.get_nodes().size()>64:states.append(value)
	elif value is Dictionary or value is Array:
		for previous:Variant in seen:
			if is_same(value,previous):return
		seen.append(value)
		if value is Array:
			for item:Variant in value:_collect_imports(item,states,seen,ids)
		else:
			# These are the drainer's ownership edges. Author/index/record data is
			# borrowed, and must not be traversed or retained by this service.
			for key:String in ["retained_resources","native_packet","private_preparation","prefab_texture_packet"]:
				_collect_imports(value.get(key),states,seen,ids)
func _enqueue_import(states:Array[GLTFState],on_done:Callable,owner:RefCounted)->void:
	serial+=1
	var id:="import:%d"%serial
	var ticket:Dictionary=_import_ticket(states,on_done,owner)
	ticket.source_id=id
	known[id]=true;pending.append(ticket);set_process(true)
func _import_ticket(states:Array[GLTFState],on_done:Callable,owner:RefCounted)->Dictionary:
	var ticket:Dictionary={"kind":"import","states":states,"state_index":0,"field":0,"metadata":[],"meta_index":0,"work":[],"resources":[],"seen":{},"phase":0,"release_index":0,"on_done":on_done,"owner":owner,"truncated":false,"cpu_buffers":[],"cpu_worker":null}
	for state:GLTFState in states:_retain(ticket,state)
	profile.imports+=1;return ticket
func _enqueue(scene:PackedScene)->void:
	var id:=scene.get_instance_id()
	if known.has(id):return
	known[id]=true
	pending.append({"source_id":id,"packed":scene,"state":scene.get_state(),"node":0,"property":-1,"resources":[],"seen":{},"phase":0})
	profile.scenes+=1;set_process(true)
func _retain(ticket:Dictionary,value:Variant)->void:
	# Native PackedScene resource properties (mesh/material/skin/shape/texture,
	# including node metadata Resource values) retain their own dependencies.
	if not value is Resource or ticket.seen.has(value.get_instance_id()):return
	ticket.seen[value.get_instance_id()]=true;ticket.resources.append(value)
func _advance(ticket:Dictionary,budget_usec:int)->bool:
	var previous:Dictionary=_advancing_ticket
	if ticket.get("kind","") in ["model","import"]:_advancing_ticket=ticket
	var complete:=_advance_ticket(ticket,budget_usec)
	_advancing_ticket=previous
	return complete
func _advance_ticket(ticket:Dictionary,budget_usec:int)->bool:
	if ticket.get("kind","")=="cpu_geometry":return _advance_cpu_geometry(ticket,budget_usec<=0)
	if ticket.get("kind","")=="model":return _advance_model(ticket,budget_usec)
	if ticket.get("kind","")=="private_array":return _advance_private_array(ticket,budget_usec)
	if ticket.get("kind","")=="import":return _advance_import(ticket,budget_usec)
	var began:=Time.get_ticks_usec();var progressed:=false
	while ticket.phase<2 and (not progressed or budget_usec<=0 or Time.get_ticks_usec()-began<budget_usec):
		progressed=true
		if ticket.phase==0:
			var state:SceneState=ticket.state
			if ticket.node>=state.get_node_count():
				# Release descriptions while their direct Resource properties still
				# have explicit owners. No live Resource is modified by this queue.
				ticket.state=null;ticket.packed=null;state=null;ticket.phase=1;continue
			if int(ticket.property)<0:
				_retain(ticket,state.get_node_instance(ticket.node));ticket.property=0
			elif ticket.property>=state.get_node_property_count(ticket.node):
				ticket.node+=1;ticket.property=-1
			else:
				_retain(ticket,state.get_node_property_value(ticket.node,ticket.property));ticket.property+=1
		else:
			if ticket.resources.is_empty():ticket.phase=2;break
			var value:Resource=ticket.resources.pop_back()
			if value is PackedScene:
				if ticket.has("nested_scenes"):
					var id:int=value.get_instance_id()
					if not ticket.scene_ids.has(id):ticket.scene_ids[id]=true;ticket.nested_scenes.append(value)
				else:_enqueue(value)
			# Include the final destructor in the slice, not a later stack unwind.
			value=null;profile.resources+=1
	var elapsed:=Time.get_ticks_usec()-began
	profile.slices+=1;profile.max_slice_us=maxi(int(profile.max_slice_us),elapsed)
	return ticket.phase==2
func _advance_private_array(ticket:Dictionary,budget_usec:int)->bool:
	var began:=Time.get_ticks_usec();var progressed:=false
	var trace=preload("res://scripts/world3d/load_trace.gd")
	while not ticket.values.is_empty() and (not progressed or budget_usec<=0 or Time.get_ticks_usec()-began<budget_usec):
		progressed=true
		var release_began:=Time.get_ticks_usec() if trace.enabled else 0
		# A call result can remain in a VM temporary even after value=null. Its
		# complete stack must unwind before measuring or starting the next unit.
		var details:=_drop_private_value(ticket.values,trace.enabled)
		profile.private_values+=1
		if trace.enabled:
			var elapsed_value:=Time.get_ticks_usec()-release_began
			if elapsed_value>int(profile.get("private_max_value_us",0)):
				profile.private_max_value_us=elapsed_value;profile.private_max_value=details
			trace.elapsed("retirement.private_value_release",release_began,details)
	var elapsed:=Time.get_ticks_usec()-began
	profile.slices+=1;profile.max_slice_us=maxi(int(profile.max_slice_us),elapsed)
	profile.private_slices+=1;profile.private_max_slice_us=maxi(int(profile.private_max_slice_us),elapsed)
	return ticket.values.is_empty()
static func _drop_private_value(values:Array,diagnostics:bool)->Dictionary:
	var value:Variant=values.pop_back();var details:Dictionary={}
	if diagnostics:
		details={"class":value.get_class() if value is Object else type_string(typeof(value)),"size":value.size() if value is Array or value is Dictionary else 0}
		if value is Resource and value.get_script()!=null:details.script=value.get_script().resource_path
		if value is Dictionary:
			var keys:Array[String]=[]
			for key:Variant in value:keys.append(str(key) if key is String or key is StringName else type_string(typeof(key)))
			details.keys=keys;details.uuid=str(value.get("uuid",""))
	return details
static func _release_cpu_geometry(values:Array)->Dictionary:
	var began:=Time.get_ticks_usec()
	# Only the new transfer container is mutated. Its nested geometry may be
	# shared, and releasing this reference must not alter any surviving borrower.
	while not values.is_empty():_drop_private_value(values,false)
	return {"elapsed_us":Time.get_ticks_usec()-began,"thread_id":OS.get_thread_caller_id()}
static func _release_cpu_geometry_batch(values:Array)->Dictionary:
	var began:=Time.get_ticks_usec()
	# The worker is the sole mutator of this private outer container. Native
	# clear releases borrowed children without clearing their shared contents.
	values.clear()
	return {"elapsed_us":Time.get_ticks_usec()-began,"thread_id":OS.get_thread_caller_id()}
func _advance_cpu_geometry(ticket:Dictionary,shutdown:bool)->bool:
	var began:=Time.get_ticks_usec();var worker:Thread=ticket.worker
	if worker==null:
		if is_same(_open_geometry_batch,ticket):_open_geometry_batch={}
		worker=Thread.new()
		var release:Callable=_release_cpu_geometry_batch if ticket.has("geometry_owners") else _release_cpu_geometry
		if worker.start(release.bind(ticket.values))!=OK:
			profile.geometry_start_failures=int(profile.get("geometry_start_failures",0))+1
			ticket.values.clear();return true
		ticket.worker=worker
		profile.geometry_batches=int(profile.get("geometry_batches",0))+1
		profile.geometry_logical_bytes=int(profile.get("geometry_logical_bytes",0))+int(ticket.logical_bytes)
		# Unknown bytes are explicit, never reported as measured zero/RSS. No
		# channel traversal is added solely to collect a retirement statistic.
		profile.geometry_unmeasured_owners=int(profile.get("geometry_unmeasured_owners",0))+int(ticket.get("geometry_owners",0))
	var done:=not worker.is_alive() or shutdown
	if done:
		var result:Dictionary=worker.wait_to_finish();ticket.worker=null
		profile.geometry_worker_us=int(profile.get("geometry_worker_us",0))+int(result.elapsed_us)
		profile.geometry_max_worker_us=maxi(int(profile.get("geometry_max_worker_us",0)),int(result.elapsed_us))
		profile.geometry_last_thread_id=result.thread_id
	profile.geometry_max_main_us=maxi(int(profile.get("geometry_max_main_us",0)),Time.get_ticks_usec()-began)
	return done
func _advance_model(ticket:Dictionary,budget_usec:int)->bool:
	var began:=Time.get_ticks_usec();var progressed:=false
	var resources:ModelOwners=ticket.resources
	while ticket.phase<4 and (not progressed or budget_usec<=0 or Time.get_ticks_usec()-began<budget_usec):
		progressed=true
		var remaining:int=maxi(1,budget_usec-(Time.get_ticks_usec()-began)) if budget_usec>0 else 0
		match ticket.phase:
			0:
				if resources.packed!=null:
					ticket.scene_queue.append(resources.packed);ticket.scene_ids[resources.packed.get_instance_id()]=true;resources.packed=null
				if ticket.scene_ticket.is_empty() and not ticket.scene_queue.is_empty():
					var packed:PackedScene=ticket.scene_queue.pop_back()
					ticket.scene_ticket={"packed":packed,"state":packed.get_state(),"node":0,"property":-1,"resources":[],"seen":{},"phase":0,"nested_scenes":ticket.scene_queue,"scene_ids":ticket.scene_ids}
				if not ticket.scene_ticket.is_empty() and not _advance(ticket.scene_ticket,remaining):break
				ticket.scene_ticket.clear()
				# Nested templates remain in this same reservation, not separate
				# tickets that could outlive the parent's admission callback.
				if ticket.scene_queue.is_empty():ticket.scene_ids.clear();ticket.phase=1
			1:
				var visuals:Array[Resource]=resources.visuals
				var released:=false
				while not visuals.is_empty() and (not released or budget_usec<=0 or Time.get_ticks_usec()-began<budget_usec):
					released=true
					var value:Resource=visuals.pop_back()
					value=null;profile.model_values+=1
				if visuals.is_empty():ticket.phase=2
			2:
				if resources.state!=null:
					var states:Array[GLTFState]=[resources.state]
					ticket.import_ticket=_import_ticket(states,Callable(),null)
					resources.state=null
				if not ticket.import_ticket.is_empty() and not _advance_import(ticket.import_ticket,remaining):break
				ticket.import_ticket.clear();ticket.phase=3
			3:
				resources.document=null;ticket.resources=null;ticket.phase=4
	var elapsed:=Time.get_ticks_usec()-began
	profile.model_slices+=1;profile.model_max_slice_us=maxi(int(profile.model_max_slice_us),elapsed)
	return ticket.phase==4
func _retain_import_value(ticket:Dictionary,value:Variant,depth:int)->void:
	if value is Resource:
		_retain(ticket,value)
	elif value is Array or value is Dictionary:
		# Retain parents before children. Dropping the parent then cannot cause
		# one recursive final release of the complete JSON/resource graph.
		ticket.resources.append(value)
		if depth<=128 and ticket.resources.size()<MAX_IMPORT_VALUES:
			ticket.work.append({"value":value,"index":0,"keys":value.keys() if value is Dictionary else [],"depth":depth})
		elif not ticket.truncated:
			ticket.truncated=true;profile.truncated_imports+=1
	elif typeof(value)>=TYPE_PACKED_BYTE_ARRAY:
		ticket.resources.append(value)
func _advance_import(ticket:Dictionary,budget_usec:int)->bool:
	var _scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.resource_retirement._advance_import") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var began:=Time.get_ticks_usec();var progressed:=false
	while ticket.phase<2 and (not progressed or budget_usec<=0 or Time.get_ticks_usec()-began<budget_usec):
		progressed=true
		if ticket.phase==1:
			if ticket.release_index>=ticket.resources.size():
				ticket.resources.clear();ticket.seen.clear();ticket.phase=2;break
			var retained:Variant=ticket.resources[ticket.release_index]
			ticket.resources[ticket.release_index]=null;ticket.release_index+=1
			var traced:bool=preload("res://scripts/world3d/load_trace.gd").enabled
			var release_began:=Time.get_ticks_usec() if traced else 0
			var kind:String=(retained.get_class() if retained is Resource else type_string(typeof(retained))) if traced else ""
			if background_byte_release_enabled and retained is PackedByteArray and retained.size()>=BACKGROUND_BYTE_MIN:
				# Only plain bytes cross threads. No Resource, Node, or borrowed
				# container is mutated. Drop this local alias before starting work.
				ticket.cpu_buffers.append(retained)
			profile.resources+=int(retained is Resource);profile.import_values+=1;retained=null
			if traced and Time.get_ticks_usec()-release_began>=1000:preload("res://scripts/world3d/load_trace.gd").elapsed("retirement.import_value_release",release_began,{"class":kind})
		elif not ticket.work.is_empty():
			var work:Dictionary=ticket.work.back()
			var container:Variant=work.value
			if work.index>=container.size():ticket.work.pop_back()
			else:
				var item:Variant
				if container is Dictionary:
					var key:Variant=work.keys[work.index]
					_retain_import_value(ticket,key,work.depth+1);item=container[key]
				else:item=container[work.index]
				work.index+=1;_retain_import_value(ticket,item,work.depth+1);item=null
			container=null;work={}
		elif ticket.state_index>=ticket.states.size():
			ticket.states.clear();ticket.metadata.clear();ticket.phase=1
		else:
			var state:GLTFState=ticket.states[ticket.state_index]
			if ticket.field<IMPORT_FIELDS.size():
				var value:Variant=state.get(IMPORT_FIELDS[ticket.field]);ticket.field+=1
				_retain_import_value(ticket,value,0);value=null
			elif ticket.field==IMPORT_FIELDS.size():
				ticket.metadata=state.get_meta_list();ticket.meta_index=0;ticket.field+=1
			elif ticket.meta_index<ticket.metadata.size():
				var value:Variant=state.get_meta(ticket.metadata[ticket.meta_index]);ticket.meta_index+=1
				_retain_import_value(ticket,value,0);value=null
			else:
				ticket.state_index+=1;ticket.field=0;ticket.metadata.clear()
			state=null
	var complete:bool=ticket.phase==2 and _finish_cpu_buffers(ticket,budget_usec<=0)
	var elapsed:=Time.get_ticks_usec()-began
	profile.slices+=1;profile.max_slice_us=maxi(int(profile.max_slice_us),elapsed)
	profile.import_slices+=1;profile.import_max_slice_us=maxi(int(profile.import_max_slice_us),elapsed)
	return complete

static func _release_cpu_buffers(values:Array)->Dictionary:
	# This private transfer container is shared only so the worker can empty it.
	# The main thread never reads it until join; the admission owner stays main.
	var began:=Time.get_ticks_usec();var count:=0;var bytes:=0
	while not values.is_empty():
		var value:PackedByteArray=values.pop_back();bytes+=value.size();count+=1
		value=PackedByteArray()
	preload("res://scripts/world3d/load_trace.gd").elapsed("retirement.cpu_buffers_release",began,{"values":count,"logical_bytes":bytes})
	return {"values":count,"bytes":bytes,"elapsed_us":Time.get_ticks_usec()-began,"thread_id":OS.get_thread_caller_id()}

func _finish_cpu_buffers(ticket:Dictionary,shutdown:bool)->bool:
	var worker:Thread=ticket.cpu_worker
	if worker==null and not ticket.cpu_buffers.is_empty():
		worker=Thread.new()
		# All source slots/local aliases have now been cleared. Starting earlier
		# could race with the final main-thread reference and move the stall back.
		if worker.start(_release_cpu_buffers.bind(ticket.cpu_buffers))!=OK:
			profile.cpu_start_failures=int(profile.get("cpu_start_failures",0))+1
			ticket.cpu_buffers.clear();return true
		ticket.cpu_worker=worker
		profile.cpu_batches=int(profile.get("cpu_batches",0))+1
	if worker==null:return true
	if worker.is_alive() and not shutdown:return false
	var result:Dictionary=worker.wait_to_finish()
	profile.cpu_values=int(profile.get("cpu_values",0))+result.values
	profile.cpu_bytes=int(profile.get("cpu_bytes",0))+result.bytes
	profile.cpu_worker_us=int(profile.get("cpu_worker_us",0))+result.elapsed_us
	profile.cpu_max_worker_us=maxi(int(profile.get("cpu_max_worker_us",0)),result.elapsed_us)
	profile.cpu_last_thread_id=result.thread_id
	ticket.cpu_worker=null
	return true
func _finish_front()->void:
	var ticket:Dictionary=pending.pop_front();known.erase(ticket.source_id)
	if ticket.has("geometry_tail"):
		var tail:Dictionary=ticket.geometry_tail;ticket.erase("geometry_tail")
		tail.on_done=ticket.get("on_done",Callable());tail.owner=ticket.get("owner")
		ticket.on_done=Callable();ticket.owner=null
	elif ticket.has("on_done"):
		var callback:Callable=ticket.on_done;ticket.on_done=Callable()
		if callback.is_valid():callback.call()
		ticket.owner=null
func _process(_delta:float)->void:
	var allowed:=Budget.allowance("retire",1000,false)
	if allowed<=0 or pending.is_empty():return
	var began:=Time.get_ticks_usec()
	if _advance(pending[0],allowed):
		_finish_front()
	Budget.charge("retire",began)
	if pending.is_empty():set_process(false)
func _exit_tree()->void:
	exiting=true
	# Engine exit has no future frames; finish all queued dependencies on main.
	while not pending.is_empty():
		_advance(pending[0],0);_finish_front()
