extends SceneTree
## Headless state-machine regression. Presentation is an explicit test gate;
## no assertion in this file claims to prove an actual GPU draw occurred.
const World=preload("res://scripts/world3d/world_3d.gd")
const Cover=preload("res://scripts/world3d/initial_loading_cover.gd")
class Player extends CharacterBody3D:
	var input_locked:=false
	var geometry_blocked:=false
class Queue extends Node:
	var idle:=true
	var permit:=true
	var ended:=0
	var prioritize_calls:=0
	func is_idle()->bool:return idle
	func end_loading_cover()->void:permit=false;ended+=1
	func prioritize(_position:Vector3)->void:prioritize_calls+=1
class Probe extends "res://scripts/world3d/world_3d.gd":
	signal presentation_released
	var presentation_waiting:=false
	var first_frames:=0
	var noted_after_cover:=false
	var neighbours:=0
	var local_geometry_requests:=0
	var failure_returns:=0
	func _ready()->void:set_process(false);set_physics_process(false)
	func _exit_tree()->void:_release_initial_loading_cover()
	func _await_initial_loading_presentation()->void:
		presentation_waiting=true
		await presentation_released
		presentation_waiting=false
	func note_entry_first_frame(_rendered:bool)->bool:
		first_frames+=1
		noted_after_cover=_initial_loading_cover==null and not get_viewport().disable_3d
		return true
	func activate_entry_neighbours()->void:neighbours+=1
	func _return_from_initial_loading_failure()->void:failure_returns+=1
	func _map_traversal_receipt(_map:Node,_clip:AABB,_demand:String)->Dictionary:
		local_geometry_requests+=1
		return {"ok":true}
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func fixture()->Probe:
	var world:=Probe.new()
	world._map_root=Node3D.new();world.add_child(world._map_root)
	world._map_root.set_meta("collision_first_loading",true)
	var queue:=Queue.new();queue.name="DeferredAssets";world._map_root.add_child(queue)
	world._player=Player.new();world.add_child(world._player);world._player.set_physics_process(false)
	world._status=Label.new();world.add_child(world._status)
	world._initial_loading_cover=Cover.new();world.add_child(world._initial_loading_cover)
	root.add_child(world)
	world._ready_for_play=true
	root.disable_3d=true
	return world
func complete(world:Probe,state:Dictionary,timeout_msec:int=30000)->void:
	state.ok=await world.call("_complete_initial_entry",world._map_root,timeout_msec)
	state.done=true
func await_presentation(world:Probe)->void:
	for i in 12:
		if world.presentation_waiting:return
		await process_frame
	check(false,"ready geometry reaches the controlled presentation gate")
func await_completion(state:Dictionary)->void:
	for i in 12:
		if state.get("done",false):return
		await process_frame
	check(false,"lifecycle coroutine finishes after its gate resolves")
func run()->void:
	var session:=root.get_node("GameSession")
	var previous_transition:bool=session._world_transition_active
	var previous_building:bool=World.building_readiness_enabled
	session._world_transition_active=false;World.building_readiness_enabled=false
	var world:=fixture()
	world._player.input_locked=false
	world._geometry_wait_locked=true
	world._map_root.set_meta("stream_target",Vector2i.ZERO)
	world._status.text="initial loading remains covered"
	world._guard_deferred_geometry()
	check(world._player.input_locked,"local collision readiness cannot unlock an active initial cover")
	check(world._map_root.get_node("DeferredAssets").prioritize_calls==1,"the cover preserves normal player demand refresh")
	check(world.local_geometry_requests==1,"the cover preserves local geometry safety requests")
	check(world._status.text=="initial loading remains covered","local collision readiness cannot replace the initial loading message")
	check(world._ready_for_play and not world.is_world_ready(),"streaming permission remains separate from visible world readiness")
	world._release_initial_loading_cover()
	check(not world.is_world_ready() and world._player.input_locked,"aborting a cover cannot mark the world ready or unlock controls")
	check(not root.disable_3d and not world.has_meta("initial_loading_cover_released"),"abort restores viewport without claiming a successful reveal")
	world.free()
	if not "--guard-only" in OS.get_cmdline_user_args():
		await first_frame_ownership_case()
		await timeout_case()
		await transition_timeout_case()
		await success_case(false,false)
		await success_case(true,false)
		await success_case(false,true)
		await cancelled_presentation_case()
		await cancelled_settle_case()
	World.building_readiness_enabled=previous_building;session._world_transition_active=previous_transition
	root.disable_3d=false
	print("INITIAL_LOADING_LIFECYCLE ",checks," checks / ",failures," failures; headless lifecycle only")
	quit(1 if failures else 0)
func first_frame_ownership_case()->void:
	var session:=root.get_node("GameSession")
	var previous_disable:bool=session._transition_previous_disable_3d
	session._world_transition_active=true;session._transition_previous_disable_3d=false
	var world:=fixture()
	world._prepare_world_first_frame()
	check(root.disable_3d,"GameSession first-frame preparation cannot override the active initial cover")
	world._release_initial_loading_cover();root.disable_3d=true
	world._prepare_world_first_frame()
	check(not root.disable_3d,"without an initial cover the existing GameSession first-frame restore remains active")
	world.free();await process_frame
	session._world_transition_active=false;session._transition_previous_disable_3d=previous_disable
func timeout_case()->void:
	var world:=fixture();var queue:Queue=world._map_root.get_node("DeferredAssets")
	queue.idle=false
	var state:={};complete(world,state,0);await await_completion(state)
	check(not state.get("ok",true),"entry completion propagates a full-ready timeout to its caller")
	check(world._initial_loading_cover!=null and root.disable_3d and world._player.input_locked,"timeout retains opaque loading state and the input lock")
	check(world.has_meta("entry_loading_error") and world.loading_progress().stage==world.get_meta("entry_loading_error"),"timeout preserves its error stage instead of continuing the ready flow")
	check(not queue.permit and queue.ended==1 and not world.has_meta("initial_loading_cover_released"),"timeout revokes the covered budget without reporting a successful reveal")
	check(not world._ready_for_play,"a failed entry cannot keep running its ready-world tick")
	var labels:=world._initial_loading_cover.find_children("*","Label",true,false)
	check(labels.any(func(label:Label)->bool:return str(world.get_meta("entry_loading_error")) in label.text),"direct-entry failure is visible on the opaque cover")
	var buttons:=world._initial_loading_cover.find_children("*","Button",true,false)
	check(buttons.size()==1 and buttons[0].is_visible_in_tree(),"direct-entry failure supplies a visible return action")
	if buttons.size()==1:
		buttons[0].pressed.emit()
		check(world.failure_returns==1 and world._player.input_locked,"direct-entry failure wires its return action without unlocking gameplay")
	world.free();await process_frame
func transition_timeout_case()->void:
	var session:=root.get_node("GameSession");session._world_transition_active=true
	var outer:=CanvasLayer.new();outer.name="WorldTransition";outer.layer=100;session.add_child(outer)
	var shade:=ColorRect.new();shade.color=Color.BLACK;shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);outer.add_child(shade)
	var world:=fixture();var queue:Queue=world._map_root.get_node("DeferredAssets");queue.idle=false
	var cover:CanvasLayer=world._initial_loading_cover
	var state:={};complete(world,state,0);await await_completion(state)
	check(not state.get("ok",true) and world._initial_loading_cover==null,"transition failure hands the error back to GameSession instead of hiding its error UI")
	check(outer.is_inside_tree() and outer.visible and not world._ready_for_play and world._player.input_locked,"failure handoff retains the outer cover and gameplay gate")
	check(not cover.visible and not cover.is_processing_input() and not cover.is_processing_unhandled_input(),"the retired inner cover cannot intercept the outer return button")
	check(not queue.permit and queue.ended==1 and not world.has_meta("initial_loading_cover_released"),"failure handoff revokes loading budget without recording a successful reveal")
	world.free();outer.free();await process_frame;session._world_transition_active=false
func success_case(building:bool,transition:bool)->void:
	World.building_readiness_enabled=building
	root.get_node("GameSession")._world_transition_active=transition
	var world:=fixture();var queue:Queue=world._map_root.get_node("DeferredAssets")
	world._map_root.set_meta("stream_append_pending",[{}])
	var state:={};complete(world,state)
	await process_frame;await process_frame
	check(world._player.input_locked and not world.presentation_waiting,"pending append work keeps movement locked before full readiness")
	world._map_root.set_meta("stream_append_pending",[])
	await await_presentation(world)
	check(world._initial_loading_cover!=null and not world.is_world_ready() and world._player.input_locked,"presentation waits under the cover with controls locked")
	check(not root.disable_3d and not queue.permit and queue.ended==1,"restoring 3D immediately revokes the covered publication permit")
	check(world.first_frames==0,"building first-frame activation cannot happen while 3D is disabled or presentation is pending")
	world.presentation_released.emit();await await_completion(state)
	check(state.get("ok",false) and world.is_world_ready() and world.has_meta("initial_loading_cover_released"),"resolved presentation completes the entry gate")
	check(world._player.input_locked==transition,"GameSession retains its own movement gate; direct entry unlocks after reveal")
	check(world.first_frames==(1 if building and not transition else 0) and (not building or transition or world.noted_after_cover),"direct building activation follows restored presentation exactly once")
	check(not transition or world.neighbours==0,"the initial cover does not take over GameSession neighbour activation")
	world.free();await process_frame
	World.building_readiness_enabled=false;root.get_node("GameSession")._world_transition_active=false
func cancelled_presentation_case()->void:
	var world:=fixture();var state:={};complete(world,state)
	await await_presentation(world)
	root.remove_child(world)
	world.presentation_released.emit();await await_completion(state)
	check(not state.get("ok",true) and not world.is_world_ready(),"tree exit during presentation cancels entry completion")
	check(world._player.input_locked and not root.disable_3d and not world.has_meta("initial_loading_cover_released"),"resuming after exit cannot stamp an aborted cover as released")
	world.free();await process_frame
func cancelled_settle_case()->void:
	var world:=fixture();var queue:Queue=world._map_root.get_node("DeferredAssets");queue.idle=false
	var state:={};complete(world,state)
	await process_frame;root.remove_child(world);await await_completion(state)
	check(not state.get("ok",true) and not world.presentation_waiting and not world.is_world_ready(),"tree exit while geometry is pending cannot enter presentation or readiness")
	check(not world.has_meta("initial_loading_cover_released"),"cancelled geometry settling has no successful-release marker")
	world.free();await process_frame
