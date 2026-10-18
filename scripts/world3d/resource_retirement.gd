extends Node
## Unused large templates relinquish GPU/CPU Resource owners on bounded main
## thread slices. Logical cache eviction is immediate; this queue owns disposal.
const NODE_NAME:="ResourceRetirement"
const Budget=preload("res://scripts/world3d/frame_work_budget.gd")
var pending:Array=[]
var known:Dictionary={}
var exiting:=false
var profile:Dictionary={"scenes":0,"slices":0,"max_slice_us":0,"resources":0}
static func defer_scene(scene:PackedScene)->bool:
	if scene==null or not Thread.is_main_thread():return false
	var tree:SceneTree=Engine.get_main_loop() as SceneTree
	if tree==null or not is_instance_valid(tree.root) or not tree.root.is_inside_tree():return false
	var state:SceneState=scene.get_state()
	if state.get_node_count()<=64:return false
	var service:Node=tree.root.get_node_or_null(NODE_NAME)
	if service!=null and service.exiting:return false
	if service==null:
		service=new();service.name=NODE_NAME;service.process_mode=Node.PROCESS_MODE_ALWAYS;tree.root.add_child(service)
	service._enqueue(scene);return true
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
			if value is PackedScene:_enqueue(value)
			# Include the final destructor in the slice, not a later stack unwind.
			value=null;profile.resources+=1
	var elapsed:=Time.get_ticks_usec()-began
	profile.slices+=1;profile.max_slice_us=maxi(int(profile.max_slice_us),elapsed)
	return ticket.phase==2
func _process(_delta:float)->void:
	var allowed:=Budget.allowance("retire",1000,false)
	if allowed<=0 or pending.is_empty():return
	var began:=Time.get_ticks_usec()
	if _advance(pending[0],allowed):
		known.erase(pending[0].source_id);pending.pop_front()
	Budget.charge("retire",began)
	if pending.is_empty():set_process(false)
func _exit_tree()->void:
	exiting=true
	# Engine exit has no future frames; finish all queued dependencies on main.
	while not pending.is_empty():
		_advance(pending[0],0);known.erase(pending[0].source_id);pending.pop_front()
