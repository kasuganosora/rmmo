extends RefCounted
## Root-child changes contain no authoritative specs. Keep weak pending roots
## until adoption; registered runtime instances are already in the stream index.
var root:WeakRef
var pending:Dictionary={}
var full_scan:=false

func _init(map_root:Node,initial_scan:bool)->void:
	root=weakref(map_root);full_scan=initial_scan
	map_root.child_entered_tree.connect(_entered)
	map_root.tree_exited.connect(_tree_exited)

func _entered(child:Node)->void:
	if not child.has_meta("stream_instance"):pending[child.get_instance_id()]=weakref(child)

func _tree_exited()->void:
	# Changes outside the tree do not emit child_entered_tree. Re-entry must
	# reconcile them even if remove/add left the direct child count unchanged.
	full_scan=true;pending.clear()

func dirty()->bool:return full_scan or not pending.is_empty()

func take_roots(force_full:bool)->Variant:
	if force_full or full_scan:
		full_scan=false;pending.clear();return null
	var ready:Dictionary={}
	for id:int in pending:
		var child:Node=pending[id].get_ref()
		if child!=null and not child.has_meta("stream_instance"):ready[id]=true
	pending.clear()
	var result:Array=[]
	if ready.is_empty():return result
	# Node's internal-mode accessor is not exposed to GDScript. Enumerate only
	# when there are actual unmarked arrivals, preserving get_children(false)
	# order/exclusion; never walk existing descendants or check their metadata.
	var map_root:Node=root.get_ref()
	for child:Node in map_root.get_children():
		if ready.has(child.get_instance_id()):result.append(child)
	return result
