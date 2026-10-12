extends SceneTree
## Pure headless contract: no rendering, resource import or formal map access.
const View=preload("res://scripts/ui/world_map_view_3d.gd")
class Player extends Node3D:
	var input_locked:=false
class World extends Node:
	var _player:=Player.new()
	var _transfer_pending:=false
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var session:Node=root.get_node("GameSession")
	var previous_transition:bool=session._world_transition_active
	var previous_scene:Node=current_scene
	var world:=World.new();root.add_child(world);world.add_child(world._player);current_scene=world
	var view:=View.new();root.add_child(view);view.set_process(false);view.world=world;view.radar=true
	check(view._terrain_warm_budget_usec()==1000,"normal gameplay keeps one millisecond budget")
	world._player.input_locked=true
	check(view._terrain_warm_budget_usec()==1000,"dialogue or combat input lock alone does not increase budget")
	session._world_transition_active=true
	check(view._terrain_warm_budget_usec()==1000,"transition flag without actual cover keeps runtime budget")
	var cover:=CanvasLayer.new();cover.name="WorldTransition";session.add_child(cover)
	check(view._terrain_warm_budget_usec()==4000,"covered current-world radar uses four milliseconds")
	cover.visible=false
	check(view._terrain_warm_budget_usec()==1000,"hidden cover immediately restores runtime budget")
	cover.visible=true;view.radar=false
	check(view._terrain_warm_budget_usec()==1000,"full map overview retains runtime budget")
	view.radar=true;world._player.input_locked=false
	check(view._terrain_warm_budget_usec()==1000,"unlocked player immediately restores runtime budget")
	world._player.input_locked=true;current_scene=null
	check(view._terrain_warm_budget_usec()==1000,"old world after scene switch cannot claim loading budget")
	current_scene=world;session._world_transition_active=false
	check(view._terrain_warm_budget_usec()==1000,"completed or cancelled transition restores runtime budget")
	session._world_transition_active=true;root.remove_child(view)
	check(view._terrain_warm_budget_usec()==1000,"detached view cannot claim loading budget")
	root.add_child(view);view.set_process(false);cover.queue_free()
	check(view._terrain_warm_budget_usec()==1000,"queued cover removal immediately restores runtime budget")
	session._world_transition_active=false;world._transfer_pending=true
	check(view._terrain_warm_budget_usec()==1000,"transfer flag alone retains runtime budget")
	var transfer_cover:=CanvasLayer.new();transfer_cover.name="TransferLoading";world.add_child(transfer_cover)
	check(view._terrain_warm_budget_usec()==4000,"visible same-world transfer cover increases radar budget")
	transfer_cover.visible=false
	check(view._terrain_warm_budget_usec()==1000,"hidden transfer cover retains runtime budget")
	transfer_cover.visible=true;world._transfer_pending=false
	check(view._terrain_warm_budget_usec()==1000,"finished transfer restores runtime radar budget")
	view.free();world.free();current_scene=previous_scene
	session._world_transition_active=previous_transition
	print("WORLD_MAP_LOADING_BUDGET_FINISHED failures=",failures)
	quit(1 if failures else 0)
