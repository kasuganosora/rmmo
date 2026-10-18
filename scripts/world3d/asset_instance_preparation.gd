extends RefCounted
## The same asset operation as WorldDocument._asset, advanced while its graph
## is private. Shared per-node operations preserve editor/MCP synchronous use.
const Components=preload("res://scripts/world3d/model_components.gd")
var holder:Node3D
var model:Node3D
var document:RefCounted
var record:Dictionary={}
var nodes:Array[Node]=[]
var components:Dictionary={}
var phase:=0
var profile:Dictionary={"slices":0,"elapsed_us":0,"max_slice_us":0}
func begin(doc:RefCounted,value:Dictionary,template:PackedScene)->void:
	document=doc;record=value
	var began:=Time.get_ticks_usec()
	if value.has("house_prefab"):
		holder=doc._mesh(value);phase=3
		profile.elapsed_us=Time.get_ticks_usec()-began;profile.max_slice_us=profile.elapsed_us
		return
	var context:Dictionary=doc._begin_asset_instance(value,{"template":template})
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
			if nodes.is_empty():components=Components.begin(model,record);phase=1;continue
			var node:Node=nodes.pop_back()
			document._namespace_asset_node(node,str(record.uuid),model,str(record.get("collision","")))
			var children:=node.get_children()
			for i:int in range(children.size()-1,-1,-1):nodes.append(children[i])
		elif phase==1:
			if not Components.advance(components,maxi(1,budget_usec-(Time.get_ticks_usec()-began)) if budget_usec>0 else 0):break
			document._asset_components_ready(holder,model);components={};phase=2
		else:
			holder=document._finish_asset_instance(holder,record);phase=3
	var elapsed:=Time.get_ticks_usec()-began
	profile.slices+=1;profile.elapsed_us+=elapsed;profile.max_slice_us=maxi(int(profile.max_slice_us),elapsed)
	return phase==3
func take_holder()->Node3D:
	var result:=holder;holder=null;model=null;nodes.clear();components.clear();document=null;record={}
	return result
func dispose()->void:
	assert(Thread.is_main_thread())
	if is_instance_valid(holder):holder.free()
	holder=null;model=null;nodes.clear();components.clear();document=null;record={};phase=3
