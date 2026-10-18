extends RefCounted
## Private, main-thread-only projection. Nothing is published until the whole
## namespace and disposal are complete; cancellation retains the old sync exit.
const Stream=preload("res://scripts/world3d/world_stream.gd")
var holder:Node3D
var specs:Array=[]
var nodes:Array=[]
var visited:Array[Node]=[]
var collision_local:=false
var placement:=Transform3D.IDENTITY
var draw_order:=0
var stage:=0
var profile:Dictionary={"slices":0,"elapsed_us":0,"max_slice_us":0}
func begin(value:Node3D,local_collision:bool,order:int)->void:
	holder=value;collision_local=local_collision;placement=value.transform;draw_order=order
	if local_collision:
		visited.append(holder)
		var children:=holder.get_children()
		for i:int in range(children.size()-1,-1,-1):nodes.append({"node":children[i],"pose":Transform3D.IDENTITY})
	else:nodes.append({"node":holder,"pose":Transform3D.IDENTITY})
func advance(budget_usec:int)->bool:
	assert(Thread.is_main_thread())
	var began:=Time.get_ticks_usec();var advanced:=false
	while stage<2 and (not advanced or budget_usec<=0 or Time.get_ticks_usec()-began<budget_usec):
		advanced=true
		if stage==0:
			if nodes.is_empty():stage=1;continue
			var entry:Dictionary=nodes.pop_back();var node:Node=entry.node
			var pose:Transform3D=entry.pose
			if node is Node3D:pose=pose*node.transform
			visited.append(node)
			var children:=node.get_children()
			for i:int in range(children.size()-1,-1,-1):nodes.append({"node":children[i],"pose":pose})
			if not node is MeshInstance3D:continue
			var spec:Dictionary=Stream._spec(node)
			spec.transform=pose;spec.position=pose.origin;spec.rotation=pose.basis.get_euler()
			var bounds:AABB=pose*node.get_aabb()
			spec.chunk=Stream.chunk_key(pose.origin);spec.chunk_min=Stream.chunk_key(bounds.position);spec.chunk_max=Stream.chunk_key(bounds.end)
			preload("res://scripts/world3d/building_fixtures.gd").prepare_spec(spec)
			spec.uuid=str(spec.extras.get("uuid",node.name))
			if collision_local:
				# Preserve the sidecar's exact multiplication and fixture order.
				pose=placement*spec.transform
				spec.transform=pose;spec.position=pose.origin;spec.rotation=pose.basis.get_euler()
				bounds=pose*spec.mesh.get_aabb()
				spec.chunk=Stream.chunk_key(pose.origin);spec.chunk_min=Stream.chunk_key(bounds.position);spec.chunk_max=Stream.chunk_key(bounds.end)
			spec.map_draw_order=draw_order+specs.size();specs.append(spec)
		else:
			if visited.is_empty():holder=null;stage=2;break
			# Reverse traversal frees children before their parents, while specs
			# retain the exact geometry/material owners needed for publication.
			var node:Node=visited.pop_back()
			if node.get_parent()!=null:node.get_parent().remove_child(node)
			node.free()
	var elapsed:=Time.get_ticks_usec()-began
	profile.slices+=1;profile.elapsed_us+=elapsed;profile.max_slice_us=maxi(int(profile.max_slice_us),elapsed)
	return stage==2
func dispose()->void:
	assert(Thread.is_main_thread())
	if is_instance_valid(holder):holder.free()
	holder=null;nodes.clear();visited.clear();specs.clear();stage=2
