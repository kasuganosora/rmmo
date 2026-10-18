extends Node
const ModelOwners=preload("res://scripts/world3d/model_resource_owners.gd")
## Unused large templates relinquish GPU/CPU Resource owners on bounded main
## thread slices. Logical cache eviction is immediate; this queue owns disposal.
const NODE_NAME:="ResourceRetirement"
const Budget=preload("res://scripts/world3d/frame_work_budget.gd")
const IMPORT_FIELDS:Array[String]=["json","glb_data","nodes","buffers","buffer_views","accessors","meshes","materials","textures","texture_samplers","images","skins","cameras","lights","skeletons","animations","unique_names","unique_animation_names"]
const MAX_IMPORT_VALUES:=262144
var pending:Array=[]
var known:Dictionary={}
var exiting:=false
var serial:=0
var profile:Dictionary={"scenes":0,"imports":0,"slices":0,"max_slice_us":0,"resources":0,"import_values":0,"import_slices":0,"import_max_slice_us":0,"truncated_imports":0,"private_arrays":0,"private_values":0,"private_slices":0,"private_max_slice_us":0,"models":0,"model_values":0,"model_slices":0,"model_max_slice_us":0}
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
	var state:SceneState=scene.get_state()
	if state.get_node_count()<=64:return false
	var service:Node=_service()
	if service==null:return false
	service._enqueue(scene);return true
static func defer_private_array(values:Array)->bool:
	# Only exclusively owned snapshots or completed retirement plans may donate
	# this container. Never donate an array still used by a live index/cursor.
	# Items are unreferenced, never recursively cleared or otherwise mutated.
	if values.size()<256 or not Thread.is_main_thread():return false
	var service:Node=_service()
	if service==null:return false
	service.serial+=1;var id:="private:%d"%service.serial
	service.pending.append({"kind":"private_array","source_id":id,"values":values})
	service.known[id]=true;service.profile.private_arrays+=1;service.set_process(true)
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
	var ticket:Dictionary={"kind":"import","states":states,"state_index":0,"field":0,"metadata":[],"meta_index":0,"work":[],"resources":[],"seen":{},"phase":0,"release_index":0,"on_done":on_done,"owner":owner,"truncated":false}
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
	while not ticket.values.is_empty() and (not progressed or budget_usec<=0 or Time.get_ticks_usec()-began<budget_usec):
		progressed=true
		var value:Variant=ticket.values.pop_back()
		value=null;profile.private_values+=1
	var elapsed:=Time.get_ticks_usec()-began
	profile.slices+=1;profile.max_slice_us=maxi(int(profile.max_slice_us),elapsed)
	profile.private_slices+=1;profile.private_max_slice_us=maxi(int(profile.private_max_slice_us),elapsed)
	return ticket.values.is_empty()
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
	var elapsed:=Time.get_ticks_usec()-began
	profile.slices+=1;profile.max_slice_us=maxi(int(profile.max_slice_us),elapsed)
	profile.import_slices+=1;profile.import_max_slice_us=maxi(int(profile.import_max_slice_us),elapsed)
	return ticket.phase==2
func _finish_front()->void:
	var ticket:Dictionary=pending.pop_front();known.erase(ticket.source_id)
	if ticket.get("kind","") in ["import","model"]:
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
