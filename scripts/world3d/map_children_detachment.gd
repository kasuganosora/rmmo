extends "res://scripts/world3d/map_body_detachment.gd"
## Only the already-closed, plain MapLoader runtime root uses this driver.
## Its shallow reverse snapshot shares one held FIFO with bodies and MapRoot.
## Each subtree exit remains atomic. This splits work; it does not remove it.
var _map:WeakRef
func configure_map(world:Node,map:Node,children:Array,hold:RefCounted,cover:Node,stage:Node)->void:
	_map=weakref(map)
	profile.direct_snapshots=1;profile.skipped_freed=0;profile.already_detached=0
	configure(world,children,hold,cover,stage)
func advance()->void:
	if done:return
	if not _valid_lifetime():_finish(false,"invalid_lifetime");return
	var map:Node=_map.get_ref() if _map!=null else null
	var world:Node=_world.get_ref()
	if map==null or map.is_queued_for_deletion() or not world.is_ancestor_of(map):_finish(false,"map_adopted_or_lost");return
	var frame:=Engine.get_process_frames()
	if _last_frame==frame:return
	_last_frame=frame
	var allowed:=Budget.allowance_disposal(1000,true)
	if allowed<=0:profile.budget_denials+=1;return
	var began:=Time.get_ticks_usec();var progressed:=false
	while _cursor<_roots.size() and (not progressed or Time.get_ticks_usec()-began<allowed):
		progressed=true;var child:Variant=_roots[_cursor];profile.visited+=1
		if not is_instance_valid(child):profile.skipped_freed+=1
		else:
			var parent:Node=child.get_parent()
			if parent==null and not child.is_inside_tree():profile.already_detached+=1
			elif parent!=map:
				_record_slice(began);_finish(false,"child_adopted");return
			else:
				if not _hold.remove_owned_node(child,map):
					_record_slice(began);_finish(false,"child_detach_refused");return
				profile.detached+=1
				if done:_record_slice(began);return
				if is_instance_valid(child) and (child.is_inside_tree() or child.get_parent()!=null):
					_record_slice(began);_finish(false,"child_not_detached");return
				# A callback may move or queue the MapRoot itself. Never continue
				# against an adopted parent merely because its identity survived.
				if not is_instance_valid(map) or map.is_queued_for_deletion() or not world.is_ancestor_of(map):
					_record_slice(began);_finish(false,"map_adopted_or_lost");return
		_cursor+=1
	_record_slice(began)
	if _cursor>=_roots.size():
		if map.get_child_count(true)!=0:_finish(false,"map_children_changed")
		else:_finish(true,"")
