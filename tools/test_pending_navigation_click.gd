extends SceneTree
class PendingNavigation extends Node:
	var version:=1
	var available:=false
	func find_path(start:Vector3,goal:Vector3,_tolerance:float)->Dictionary:
		return {"ok":true,"path":PackedVector3Array([start,goal])} if available else {"ok":false,"reason":"pending"}
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures+=1
func run()->void:
	var player=preload("res://scripts/world3d/world_player.gd").new()
	var model:=Node3D.new();model.name="CharacterModel3D";player.add_child(model)
	player.set_physics_process(false);root.add_child(player)
	var nav:=PendingNavigation.new();root.add_child(nav);player.navigation=nav
	player.set_click_target(Vector3(-100,0,0),"ground")
	check(player._pending_click is Vector3 and player.click_target==null,"unfinished nearby route retains the requested click")
	player.click_target=null
	check(player._pending_click==null,"existing combat/transfer cancellation also cancels deferred movement")
	player.set_click_target(Vector3(-100,0,0),"ground");player.set_click_target(Vector3(-90,0,0),"ground")
	check(player._pending_click==Vector3(-90,0,0),"latest click replaces earlier pending destination")
	nav.available=true;nav.version+=1
	player.set_click_target(player._pending_click,"ground")
	check(player.click_target==Vector3(-90,0,0) and player._pending_click==null,"completed local bake converts pending click into a route")
	player.free();nav.free();print("PENDING_NAVIGATION_CLICK failures=",failures);quit(1 if failures else 0)
