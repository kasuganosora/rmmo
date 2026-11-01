extends RefCounted
## Reservation for a caller-owned permanent map-disposal transaction.
## reserve alone is reversible; begin_disposal precedes terminal close/donation.
## Thereafter cancel means finish disposal, never resume the previous map.
## State is held by the FIFO ticket. It never retains the caller's Hold.
## Roots must be independently detached before commit: no nested root aliases.
## Successful commit transfers them exclusively; callers must not reparent them.
var roots:Array[Node]=[]
var owner:WeakRef
var armed:=false
var held:=true
var aborted:=false
var finished:=false
var abort_reason:=""
var abort_cursor:=0
var total_roots:=0
var commit_root_checks:=0
var abort_root_visits:=0
var abort_detach_calls:=0
var relinquished_roots:=0

class Hold extends RefCounted:
	var _state:RefCounted
	func _init(state:RefCounted)->void:_state=state
	func begin_disposal()->bool:return _state.begin_disposal()
	func commit()->bool:return _state.commit()
	func cancel()->void:_state.request_abort("caller_cancelled")
	func status()->Dictionary:return _state.status()
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE and _state!=null:_state.request_abort("handle_released")

func configure(values:Array[Node],lifetime:Node)->void:
	roots=values;total_roots=values.size();owner=weakref(lifetime)
	lifetime.tree_exiting.connect(_owner_exiting)
func begin_disposal()->bool:
	if finished or aborted or not held:return false
	armed=true;return true
func commit()->bool:
	if finished or aborted or not held or not armed:return false
	# Lifecycle guard only. A future proven driver cursor can remove this scan.
	for node:Node in roots:
		commit_root_checks+=1
		if is_instance_valid(node) and (node.is_inside_tree() or node.get_parent()!=null):return false
	held=false;return true
func request_abort(reason:String)->void:
	if finished or not held:return
	aborted=true
	if abort_reason.is_empty():abort_reason=reason
func _owner_exiting()->void:request_abort("owner_exited")
func advance_abort(budget_usec:int)->bool:
	if not held:return true
	if not aborted:return false
	if not armed:
		# No permanent close or owner donation is allowed before begin_disposal.
		# Dropping this private outer array never frees the original scene Nodes.
		roots.clear();held=false;return true
	var began:=Time.get_ticks_usec();var progressed:=false
	while abort_cursor<roots.size() and (not progressed or budget_usec<=0 or Time.get_ticks_usec()-began<budget_usec):
		progressed=true;var node:Node=roots[abort_cursor];abort_root_visits+=1
		if is_instance_valid(node):
			var parent:Node=node.get_parent()
			if parent!=null or node.is_inside_tree():
				var lifetime:Node=owner.get_ref() if owner!=null else null
				# Off-tree parents own children too. Never retire foreign adoption.
				if lifetime==null or not lifetime.is_ancestor_of(node):
					roots[abort_cursor]=null;relinquished_roots+=1;abort_cursor+=1;continue
				if parent==null:return false
				abort_detach_calls+=1;parent.remove_child(node)
				if is_instance_valid(node) and (node.is_inside_tree() or node.get_parent()!=null):
					# tree_exited runs before remove_child returns and can adopt this
					# root elsewhere. Classify that new owner before a shutdown fallback.
					lifetime=owner.get_ref() if owner!=null else null
					if lifetime==null or not lifetime.is_ancestor_of(node):
						roots[abort_cursor]=null;relinquished_roots+=1;abort_cursor+=1;continue
					return false
		abort_cursor+=1
	if abort_cursor<roots.size():return false
	held=false;return true
func finish()->void:
	if finished:return
	finished=true;held=false
	var lifetime:Node=owner.get_ref() if owner!=null else null
	if lifetime!=null and lifetime.tree_exiting.is_connected(_owner_exiting):lifetime.tree_exiting.disconnect(_owner_exiting)
	owner=null;roots=[]
func status()->Dictionary:
	return {"armed":armed,"held":held,"aborted":aborted,"finished":finished,"abort_reason":abort_reason,"total_roots":total_roots,"commit_root_checks":commit_root_checks,"abort_root_visits":abort_root_visits,"abort_detach_calls":abort_detach_calls,"relinquished_roots":relinquished_roots}
