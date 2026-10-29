extends "res://tools/test_transfer_experience_http.gd"
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
var held:Array[Node]=[]
var first:=true
func run()->void:
	directory="D:/code/rmmo_runtime/review_artifacts/staged_far_20261017"
	var callback:=func(node:Node):
		if first and node.get_script()==Navigation:
			node.process_mode=Node.PROCESS_MODE_DISABLED;held.append(node)
	node_added.connect(callback)
	await super.run()
func trigger(id:String,destination:Vector3)->void:
	var state:Dictionary=await call_tool("playtest_state")
	check(state.preparation.policy.mode=="staged" and state.preparation.playable,"real HTTP publishes automatically selected playable policy")
	if first:
		check(not state.preparation.navigation.ready and state.preparation.navigation.state=="preparing","HTTP never equates keyboard readiness with navigation readiness")
		var world:Node=editor._playtest.world;world._preparation_sample_at=0;world._update_preparation_hint()
		check(world._preparation_hint.visible,"UI and HTTP expose the same pending capability")
		var blocked:bool=world._player.geometry_blocked;world._player.geometry_blocked=true;world._preparation_sample_at=0;world._update_preparation_hint()
		check(not world._preparation_hint.text.contains("可用键盘移动"),"UI does not promise movement while physical preparation blocks it")
		world._player.geometry_blocked=blocked
		first=false
		for nav:Node in held:nav.process_mode=Node.PROCESS_MODE_INHERIT
		held.clear()
		var deadline:=Time.get_ticks_msec()+60000
		while not world._navigation.ready_for_queries and Time.get_ticks_msec()<deadline:await process_frame
		state=await call_tool("playtest_state");check(state.preparation.navigation.ready,"HTTP observes actual background navigation completion")
	await super.trigger(id,destination)
