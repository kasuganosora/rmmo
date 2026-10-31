extends SceneTree
const World=preload("res://scripts/world3d/world_3d.gd")
class Player extends CharacterBody3D:
	var input_locked:=false
class ProbeWorld extends World:
	var transfers:Array=[]
	var accepted:=true
	func _ready()->void:
		if has_method("_bind_warp_candidates"):call("_bind_warp_candidates")
		else:child_order_changed.connect(func():_warp_cache_dirty=true)
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func _exit_tree()->void:pass
	func transfer_map(target:String,destination:Vector3,_before_commit:Callable=Callable())->bool:
		transfers.append({"target":target,"destination":destination});return accepted
var checks:=0
var failures:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func warp(target:String)->Node3D:
	var node:=Node3D.new();node.set_meta("kind","warp");node.set_meta("center",Vector3.ZERO)
	node.set_meta("target_path",target);node.set_meta("spawn",[1.,2.,3.]);return node
func run()->void:
	var world:=ProbeWorld.new();var first:=warp("first");world.add_child(first);root.add_child(world)
	var player:=Player.new();world.add_child(player);world._player=player;world._map_path="test-only"
	world._poll_warp()
	check(world.transfers.size()==1 and world.transfers.back().target=="first","initial pre-existing warp is included")
	var second:=warp("second");world.add_child(second);world.move_child(second,0);world._poll_warp()
	check(world.transfers.back().target=="second","reordered overlapping warps retain scene priority")
	world.move_child(first,0);world._poll_warp()
	check(world.transfers.back().target=="first","moving an existing warp updates priority")
	world.remove_child(first)
	check(not world._warp_candidates.has(first),"departure removes candidate immediately, before another poll")
	first.free();world._poll_warp()
	check(world.transfers.back().target=="second","departed warp cannot trigger a transfer")
	second.set_meta("target_path","updated");second.set_meta("spawn",[4.,5.,6.]);world._poll_warp()
	check(world.transfers.back()=={"target":"updated","destination":Vector3(4,5,6)},"target and destination remain live")
	second.set_meta("center",Vector3(100,0,0));var previous:=world.transfers.size();world._poll_warp()
	check(world.transfers.size()==previous,"live centre changes are respected")
	var late:=Node3D.new();world.add_child(late)
	late.set_meta("kind","warp");late.set_meta("center",Vector3.ZERO);late.set_meta("target_path","late");late.set_meta("spawn",[0.,1.,2.]);world._poll_warp()
	check(world.transfers.back().target=="late","metadata set after admission but before polling is included")
	var internal:=warp("internal");world.add_child(internal,false,Node.INTERNAL_MODE_FRONT);world._poll_warp()
	check(world.transfers.back().target=="late" and not world._warp_candidates.has(internal),"internal children keep the original get_children exclusion")
	world.accepted=false;late.set_meta("target_path","failed");world._poll_warp();previous=world.transfers.size();world._poll_warp()
	check(world.transfers.size()==previous,"failed warp is not retried every frame")
	player.position=Vector3(10,0,0);world._poll_warp();player.position=Vector3.ZERO;world._poll_warp()
	check(world.transfers.size()==previous+1,"leaving then returning permits failed warp retry")
	player.input_locked=true;previous=world.transfers.size();world._poll_warp()
	check(world.transfers.size()==previous,"locked player does not transfer")
	player.input_locked=false;world.accepted=true;root.remove_child(world);root.add_child(world);world._poll_warp()
	check(world._warp_candidates.has(late) and world._warp_candidates.has(second),"temporary world detach and re-entry rebuilds candidates")
	var host:=Node3D.new();root.add_child(host);late.reparent(host)
	check(not world._warp_candidates.has(late),"reparenting a warp out removes it immediately")
	late.reparent(world);world._failed_warp="";world._poll_warp()
	check(world.transfers.back().target=="failed","reparenting back restores the same live warp")
	var vanished:=warp("vanished");world.add_child(vanished);vanished.free();world._poll_warp()
	check(world.transfers.back().target=="failed","freed pending arrivals are ignored safely")
	world.free();host.free()
	var report:={"checks":checks,"failures":failures}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
