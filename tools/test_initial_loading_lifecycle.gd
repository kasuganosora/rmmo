extends SceneTree
## Initial entry contract without a private World3D loading cover. Presentation
## is a controlled test gate; no assertion here claims an actual GPU draw.
const World=preload("res://scripts/world3d/world_3d.gd")
class Player extends CharacterBody3D:
	var input_locked:=false
	var geometry_blocked:=false
class Queue extends Node:
	var permit:=true
	var ended:=0
	var prioritize_calls:=0
	func end_loading_cover()->void:permit=false;ended+=1
	func prioritize(_position:Vector3)->void:prioritize_calls+=1
class Probe extends "res://scripts/world3d/world_3d.gd":
	signal presentation_released
	var presentation_waiting:=false
	var first_frames:=0
	var neighbours:=0
	var local_geometry_requests:=0
	func _ready()->void:set_process(false);set_physics_process(false)
	func _exit_tree()->void:pass
	func _await_initial_loading_presentation()->void:
		presentation_waiting=true
		await presentation_released
		presentation_waiting=false
	func note_entry_first_frame(_rendered:bool)->bool:
		first_frames+=1
		return true
	func activate_entry_neighbours()->void:neighbours+=1
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
	root.add_child(world);world._ready_for_play=true
	return world
func complete(world:Probe,state:Dictionary)->void:
	state.ok=await world.call("_complete_initial_entry",world._map_root)
	state.done=true
func await_presentation(world:Probe)->void:
	for i in 12:
		if world.presentation_waiting:return
		await process_frame
	check(false,"initial entry reaches the controlled presentation gate")
func await_completion(state:Dictionary)->void:
	for i in 12:
		if state.get("done",false):return
		await process_frame
	check(false,"initial entry coroutine finishes after its gate resolves")
func run()->void:
	var session:=root.get_node("GameSession")
	var previous_transition:bool=session._world_transition_active
	var previous_disable:bool=session._transition_previous_disable_3d
	var previous_building:bool=World.building_readiness_enabled
	var previous_viewport:bool=root.disable_3d
	session._world_transition_active=false;World.building_readiness_enabled=false
	var world:=fixture();var queue:Queue=world._map_root.get_node("DeferredAssets")
	world._guard_deferred_geometry()
	check(queue.prioritize_calls==1 and world.local_geometry_requests==1,"ordinary entry retains local geometry demand and safety requests")
	check(world.is_world_ready(),"ordinary no-cover world reports ready")
	var state:={};complete(world,state);await await_completion(state)
	check(state.get("ok",false) and world.neighbours==1 and not world.presentation_waiting,"ordinary no-building entry completes and activates neighbours once")
	world._player.input_locked=false;root.disable_3d=true
	world._abort_initial_entry()
	check(not world.is_world_ready() and world._player.input_locked and not root.disable_3d,"error cleanup restores viewport and keeps gameplay locked")
	check(not queue.permit and queue.ended==1,"error cleanup releases the deferred covered budget")
	world.set_meta("entry_loading_error","entry failed")
	state={};complete(world,state);await await_completion(state)
	check(not state.get("ok",true),"entry errors prevent readiness completion")
	world.free();await process_frame

	session._world_transition_active=true;session._transition_previous_disable_3d=false
	world=fixture();root.disable_3d=true;world._prepare_world_first_frame()
	check(not root.disable_3d,"GameSession retains first-frame viewport restoration")
	World.building_readiness_enabled=true;world._player.input_locked=true
	state={};complete(world,state);await await_completion(state)
	check(state.get("ok",false) and not world.presentation_waiting and world.first_frames==0 and world.neighbours==0 and world._player.input_locked,"GameSession transition retains its own first-frame, neighbours and movement gate")
	world.free();await process_frame

	session._world_transition_active=false
	world=fixture();world._player.input_locked=true
	state={};complete(world,state);await await_presentation(world)
	check(world._player.input_locked and world.first_frames==0 and world.neighbours==0,"building entry remains locked until presentation")
	world.presentation_released.emit();await await_completion(state)
	check(state.get("ok",false) and world.first_frames==1 and world.neighbours==1 and not world._player.input_locked and world._player.is_physics_processing(),"presented building entry activates exactly once and unlocks movement")
	world.free();await process_frame

	world=fixture();world._player.input_locked=true
	state={};complete(world,state);await await_presentation(world)
	root.remove_child(world);world.presentation_released.emit();await await_completion(state)
	check(not state.get("ok",true) and world.first_frames==0 and world.neighbours==0 and world._player.input_locked,"tree exit during presentation cannot unlock or activate entry")
	world.free();await process_frame
	World.building_readiness_enabled=previous_building;session._world_transition_active=previous_transition
	session._transition_previous_disable_3d=previous_disable;root.disable_3d=previous_viewport
	print("INITIAL_LOADING_LIFECYCLE ",checks," checks / ",failures," failures; no-cover headless lifecycle only")
	quit(1 if failures else 0)
