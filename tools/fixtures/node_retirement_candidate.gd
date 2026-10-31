extends RefCounted
## Prototype only: privately owned, permanently detached native Node trees.
## Children are snapshotted once; no repeated get_child() cache reconstruction.
var native_enabled:=false
var native_state:Dictionary={}
var roots:Array[Node]=[]
var root_cursor:=0
var stack:Array[Node]=[]
var expanded:Array[bool]=[]
var freed:=0
var snapshots:=0
var cancelled:=0
var flat_groups:=0
const FLAT_NATIVE_GROUP_LIMIT:=8 # Per native deletion unit, not a resource cap.

func take(owned_roots:Array[Node])->void:
	assert(roots.is_empty() and stack.is_empty())
	roots=owned_roots
	if native_enabled:native_state={"roots":roots,"stack":stack,"expanded":expanded,"root_cursor":0,"freed":0,"snapshots":0,"cancelled":0,"atomic_subtrees":0}

func step(budget_us:int)->bool:
	if native_enabled:
		var complete:bool=ClassDB.class_call_static("Node","rmmo_retire_detached_nodes_step",native_state,budget_us)
		freed=int(native_state.freed);snapshots=int(native_state.snapshots);cancelled=int(native_state.cancelled)
		return complete
	var began:=Time.get_ticks_usec()
	var progressed:=false
	while not progressed or budget_us<=0 or Time.get_ticks_usec()-began<budget_us:
		progressed=true
		if stack.is_empty():
			if root_cursor==roots.size():
				roots=[];root_cursor=0
				return true
			var next:Variant=roots[root_cursor]
			if is_instance_valid(next) and next.is_inside_tree():return false
			roots[root_cursor]=null;root_cursor+=1
			if not is_instance_valid(next):continue
			stack.append(next);expanded.append(false)
		var last:int=stack.size()-1
		var node:Variant=stack[last]
		if not is_instance_valid(node):
			stack.pop_back();expanded.pop_back();continue
		if node.is_inside_tree():return false
		if not expanded[last]:
			expanded[last]=true
			if node.get_child_count(true)>0:
				var children:Array[Node]=node.get_children(true)
				snapshots+=1
				# Small native leaf groups can use the engine's own child loop.
				# Immediate child count alone is insufficient for nested trees.
				var flat:bool=children.size()<=FLAT_NATIVE_GROUP_LIMIT and node.get_script()==null
				if flat:
					for child:Node in children:
						if child.get_child_count(true)>0 or child.get_script()!=null:flat=false;break
				if flat:
					var group_count:=children.size()+1
					node.free()
					if is_instance_valid(node):cancelled+=1;return false
					stack.pop_back();expanded.pop_back();freed+=group_count;flat_groups+=1
					continue
				stack.append_array(children)
				expanded.resize(stack.size())
				continue
		node.free()
		if is_instance_valid(node):
			cancelled+=1
			return false
		stack.pop_back();expanded.pop_back();freed+=1
	return false
