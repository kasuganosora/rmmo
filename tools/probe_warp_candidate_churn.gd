extends SceneTree
const World=preload("res://scripts/world3d/world_3d.gd")
class Player extends CharacterBody3D:
	var input_locked:=false
class ProbeWorld extends World:
	func _ready()->void:
		if has_method("_bind_warp_candidates"):call("_bind_warp_candidates")
		else:child_order_changed.connect(func():_warp_cache_dirty=true)
	func _exit_tree()->void:pass
var rows:Array=[]
func _initialize()->void:run.call_deferred()
func run()->void:
	for trial in 3:
		var world:=ProbeWorld.new();root.add_child(world);world.set_process(false)
		var player:=Player.new();world.add_child(player);world._player=player;world._map_path="test-only"
		for i in 2048:world.add_child(Node3D.new())
		world._poll_warp()
		var started:=Time.get_ticks_usec()
		for i in 256:
			var body:=Node3D.new();world.add_child(body);world._poll_warp();body.free();world._poll_warp()
		rows.append({"trial":trial,"stable_children":2049,"arrivals":256,"polls":512,"elapsed_us":Time.get_ticks_usec()-started,"candidates":world._warp_candidates.size(),"incremental_visits":world.get("_warp_candidate_visits")})
		world.free()
	var report:={"rows":rows,"contract":"Real World._poll_warp; unrelated child add/remove churn, no GPU or full-map timing claim."}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WARP_CHURN ",JSON.stringify(report));quit()
