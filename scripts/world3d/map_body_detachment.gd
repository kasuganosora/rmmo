extends Node
## MAIN-only outgoing body detachment. The existing retirement lane pays every
## slice; the held FIFO reservation protects all roots until MapRoot exits too.
signal finished(ok:bool)
const Budget=preload("res://scripts/world3d/frame_work_budget.gd")
var _world:WeakRef
var _cover:WeakRef
var _stage:WeakRef
var _hold:RefCounted
var _roots:Array=[]
var _cursor:=0
var _last_frame:=-1
var done:=false
var succeeded:=false
var profile:Dictionary={"roots":0,"visited":0,"detached":0,"slices":0,"active_us":0,"max_slice_us":0,"budget_denials":0,"reason":""}
func _ready()->void:set_process(false)
func configure(world:Node,roots:Array,hold:RefCounted,cover:Node,stage:Node)->void:
	_world=weakref(world);_roots=roots;_hold=hold;_cover=weakref(cover);_stage=weakref(stage)
	profile.roots=roots.size()
	cover.tree_exiting.connect(_cover_exiting)
	stage.tree_exiting.connect(_stage_exiting)
	set_process(true)
func _cover_exiting()->void:_finish(false,"cover_exited")
func _stage_exiting()->void:_finish(false,"stage_exited")
func _valid_lifetime()->bool:
	var world:Node=_world.get_ref() if _world!=null else null
	var cover:Node=_cover.get_ref() if _cover!=null else null
	var stage:Node=_stage.get_ref() if _stage!=null else null
	return world!=null and world.is_inside_tree() and not world.is_queued_for_deletion() and cover!=null and cover.is_inside_tree() and not cover.is_queued_for_deletion() and cover.is_opaque_drawn() and stage!=null and stage.is_inside_tree() and not stage.is_queued_for_deletion()
func _process(_delta:float)->void:advance()
func advance()->void:
	if done:return
	if not _valid_lifetime():_finish(false,"invalid_lifetime");return
	var frame:=Engine.get_process_frames()
	if _last_frame==frame:return
	_last_frame=frame
	var allowed:=Budget.allowance_disposal(1000,true)
	if allowed<=0:profile.budget_denials+=1;return
	var began:=Time.get_ticks_usec();var progressed:=false
	var world:Node=_world.get_ref()
	while _cursor<_roots.size() and (not progressed or Time.get_ticks_usec()-began<allowed):
		progressed=true;var body:Variant=_roots[_cursor];profile.visited+=1
		if is_instance_valid(body):
			var parent:Node=body.get_parent()
			if parent!=null:
				if not world.is_ancestor_of(body):
					_record_slice(began);_finish(false,"body_adopted");return
				if not _hold.remove_owned_node(body,parent):
					_record_slice(began);_finish(false,"body_detach_refused");return
				profile.detached+=1
				# An exit callback can also close the cover/World and finish this driver.
				if done:_record_slice(began);return
			if is_instance_valid(body) and (body.is_inside_tree() or body.get_parent()!=null):
				_record_slice(began);_finish(false,"body_not_detached");return
		_cursor+=1
	_record_slice(began)
	if _cursor>=_roots.size():_finish(true,"")
func _record_slice(began:int)->void:
	var elapsed:=Time.get_ticks_usec()-began
	Budget.charge_disposal(began)
	profile.slices+=1;profile.active_us+=elapsed;profile.max_slice_us=maxi(profile.max_slice_us,elapsed)
func _finish(ok:bool,reason:String)->void:
	if done:return
	done=true;succeeded=ok;profile.reason=reason;set_process(false)
	if not ok and _hold!=null:_hold.cancel()
	var cover:Node=_cover.get_ref() if _cover!=null else null
	var stage:Node=_stage.get_ref() if _stage!=null else null
	if cover!=null and cover.tree_exiting.is_connected(_cover_exiting):cover.tree_exiting.disconnect(_cover_exiting)
	if stage!=null and stage.tree_exiting.is_connected(_stage_exiting):stage.tree_exiting.disconnect(_stage_exiting)
	finished.emit(ok)
	queue_free()
func _exit_tree()->void:
	# Emit while the parent World is still a live script instance. Its awaiting
	# transfer returns without UI mutation; held.cancel never destroys here.
	if not done:_finish(false,"owner_exited")
