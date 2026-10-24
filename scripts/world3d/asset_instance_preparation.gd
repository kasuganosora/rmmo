extends RefCounted
## The same asset operation as WorldDocument._asset, advanced while its graph
## is private. Shared per-node operations preserve editor/MCP synchronous use.
const Components=preload("res://scripts/world3d/model_components.gd")
var holder:Node3D
var model:Node3D
var document:RefCounted
var record:Dictionary={}
var nodes:Array[Node]=[]
var visited_nodes:Array[Node]=[]
var finishing:RefCounted
var components:Dictionary={}
var phase:=0
var namespace_nodes_visited:=0
var component_node_steps:=0
var subtree_free_calls:=0
var profile:Dictionary={"slices":0,"elapsed_us":0,"max_slice_us":0,"namespace_nodes_visited":0,"component_node_steps":0,"finish_nodes_visited":0,"finish_visuals_registered":0,"subtree_free_calls":0}
func begin(doc:RefCounted,value:Dictionary,template:PackedScene)->void:
	begin_from_source(doc,value,{"template":template})
func begin_from_source(doc:RefCounted,value:Dictionary,prepared:Dictionary={})->void:
	document=doc;record=value
	var began:=Time.get_ticks_usec()
	if value.has("house_prefab"):
		holder=doc._mesh(value);phase=3
		profile.elapsed_us=Time.get_ticks_usec()-began;profile.max_slice_us=profile.elapsed_us
		return
	var context:Dictionary=doc._begin_asset_instance(value,prepared)
	holder=context.holder;model=context.model
	if model!=null:nodes.append(model)
	else:phase=2
	profile.elapsed_us=Time.get_ticks_usec()-began
	profile.max_slice_us=profile.elapsed_us
func advance(budget_usec:int)->bool:
	assert(Thread.is_main_thread())
	var began:=Time.get_ticks_usec();var advanced:=false
	while phase<3 and (not advanced or budget_usec<=0 or Time.get_ticks_usec()-began<budget_usec):
		advanced=true
		if phase==0:
			if nodes.is_empty():components=Components.begin(model,record,preload("res://scripts/world3d/runtime_package_policy.gd").trusted(),visited_nodes);phase=1;continue
			var node:Node=nodes.pop_back()
			namespace_nodes_visited+=1
			visited_nodes.append(node)
			document._namespace_asset_node(node,str(record.uuid),model,str(record.get("collision","")))
			var children:=node.get_children()
			for i:int in range(children.size()-1,-1,-1):nodes.append(children[i])
		elif phase==1:
			# Each existing component pass advances (phase,at) over the same list.
			# Its delta counts real cursor steps without rescanning those nodes.
			var count_:int=components.get("nodes",[]).size()
			var before:int=int(components.get("phase",0))*count_+int(components.get("at",0))
			var done:=Components.advance(components,maxi(1,budget_usec-(Time.get_ticks_usec()-began)) if budget_usec>0 else 0)
			component_node_steps+=maxi(0,int(components.get("phase",0))*count_+int(components.get("at",0))-before)
			if not done:break
			document._asset_components_ready(holder,model);components={};phase=2
		else:
			if document.has_method("begin_asset_finish"):
				if finishing==null:finishing=document.begin_asset_finish(holder,record,visited_nodes);visited_nodes=[]
				if not finishing.advance(maxi(1,budget_usec-(Time.get_ticks_usec()-began)) if budget_usec>0 else 0):break
				_capture_finish_work()
				holder=finishing.take_holder();finishing=null
			else:holder=document._finish_asset_instance(holder,record)
			phase=3
	var elapsed:=Time.get_ticks_usec()-began
	profile.slices+=1;profile.elapsed_us+=elapsed;profile.max_slice_us=maxi(int(profile.max_slice_us),elapsed)
	if phase==3:profile.namespace_nodes_visited=namespace_nodes_visited;profile.component_node_steps=component_node_steps
	return phase==3
func _capture_finish_work()->void:
	if finishing==null:return
	profile.finish_nodes_visited=int(finishing.profile.get("visited_nodes",0))
	profile.finish_visuals_registered=int(finishing.profile.get("registered_visuals",0))
func take_holder()->Node3D:
	var result:=holder;holder=null;model=null;nodes.clear();visited_nodes.clear();components.clear();document=null;record={}
	return result
func dispose()->void:
	assert(Thread.is_main_thread())
	if finishing!=null:_capture_finish_work();finishing.dispose();finishing=null
	# A cancelled subtree can contain unvisited descendants. Count the actual
	# free call, without a diagnostic traversal or claiming its unknown size.
	if is_instance_valid(holder):holder.free();subtree_free_calls+=1
	profile.namespace_nodes_visited=namespace_nodes_visited;profile.component_node_steps=component_node_steps;profile.subtree_free_calls=subtree_free_calls
	holder=null;model=null;nodes.clear();visited_nodes.clear();components.clear();document=null;record={};phase=3
