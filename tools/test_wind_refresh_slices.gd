extends SceneTree
const Runtime=preload("res://scripts/world3d/wind_runtime.gd")
const Response=preload("res://scripts/world3d/wind_response.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
func receiver(host:Node3D,position:Vector3,shelter:bool=false)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.mesh=BoxMesh.new();node.position=position
	node.set_meta("extras",{"rmmo_wind":{"profile":"foliage","shelter":shelter}})
	host.add_child(node);Response.register(node);return node
func drain(wind:Node3D)->int:
	var slices:=0
	while wind._scan_pending and slices<2000:
		wind._advance_refresh(1);slices+=1
	return slices
func camera_guard_regression()->void:
	var scene:=Node3D.new();root.add_child(scene)
	var camera:=Camera3D.new();scene.add_child(camera)
	var wind:=Runtime.new();scene.add_child(wind);wind.camera=camera;wind.set_physics_process(false)
	wind.set_shared_state_enabled(false) # Exercise the retained range/uniform path.
	wind.set_meta("profile_frame",true)
	wind.set_meta("profile_wind_range_detail",true)
	var node:=receiver(scene,Vector3(10.6,0,0))
	node.custom_aabb=AABB(Vector3(-1,-1,-1),Vector3(2,2,2))
	node.rotation=Vector3(.2,.3,.1);node.scale=Vector3(2,.5,3)
	for lower in [false,true]:
		node.position.x=9.4 if lower else 10.6
		node.visibility_range_begin=10.0 if lower else 0.0
		node.visibility_range_end=0.0 if lower else 10.0
		camera.position=Vector3.ZERO;wind.refresh();wind._update_active_rows()
		var sign_value:=1.0 if lower else -1.0
		camera.position.x=sign_value*.7;wind.advance(Vector3(3,0,1),80)
		wind._begin_refresh();drain(wind)
		check(wind.active_rows.is_empty(),"periodic refresh removes receiver outside guarded "+("begin" if lower else "end"))
		camera.position.x=-sign_value*.7;wind.advance(Vector3(3,0,1),81)
		var material:ShaderMaterial=wind.receivers[node.get_instance_id()].materials[0]
		check(wind.active_rows.size()==1 and material.get_shader_parameter("wind_time")==81.0,"reverse camera motion updates visible "+("begin" if lower else "end")+" LOD before drawing")
	# Both points fit inside the same .45m anchor ball. A periodic removal at
	# one side cannot become visible at the other: total drift .88m < guard 1m.
	node.position.x=10.6;node.visibility_range_begin=0;node.visibility_range_end=10
	camera.position=Vector3.ZERO;wind.refresh();wind._update_active_rows()
	camera.position.x=-.44;wind.advance(Vector3(3,0,1),82);wind._begin_refresh();drain(wind)
	camera.position.x=.44;wind.advance(Vector3(3,0,1),83)
	check(wind.range_camera_position==Vector3.ZERO and wind.active_rows.is_empty() and camera.global_position.distance_to(node.global_position)>10,"mixed periodic samples inside anchor guard cannot hide an actually visible LOD")
	camera.position.x=.7;wind.advance(Vector3(3,0,1),84)
	check(wind.active_rows.size()==1 and wind.get_meta("advance_timing").has("range_detail"),"crossing guard threshold scans immediately and reports range detail")
	wind.advance(Vector3(3,0,1),85)
	check(not wind.get_meta("advance_timing").has("range_detail"),"non-scan frames never repeat old range detail")
	wind.remove_meta("profile_wind_range_detail");camera.position.x=1.4;wind.advance(Vector3(3,0,1),86)
	var aggregate:Dictionary=wind.get_meta("advance_timing")
	check(aggregate.has("range_ms") and not aggregate.has("range_detail"),"aggregate profiling remains enabled without stale detailed measurements")
	scene.free()
func run()->void:
	camera_guard_regression()
	var scene:=Node3D.new();root.add_child(scene)
	var camera:=Camera3D.new();scene.add_child(camera)
	var wind:=Runtime.new();scene.add_child(wind);wind.camera=camera;wind.set_physics_process(false);wind.set_meta("profile_frame",true)
	wind.set_shared_state_enabled(false)
	var first:=receiver(scene,Vector3.ZERO)
	wind.refresh();wind.advance(Vector3(3,0,1),10)
	var material:ShaderMaterial=wind.receivers[first.get_instance_id()].materials[0]
	var new_nodes:Array=[]
	for i in 100:new_nodes.append(receiver(scene,Vector3(i%10,0,i/10)))
	wind._begin_refresh();wind._advance_refresh(1)
	check(wind._scan_pending and wind.receivers.size()<101,"small budget leaves pending work rather than a full scan")
	wind.advance(Vector3(3,0,1),11)
	check(material.get_shader_parameter("wind_time")==11.0 and wind.active_rows.size()>0,"existing visible receiver keeps animating while scan is pending")
	var continuous:=true
	var slices:=0
	while wind._scan_pending and slices<2000:
		wind.advance(Vector3(3,0,1),12+slices)
		wind._advance_refresh(1);slices+=1
		for row:Dictionary in wind.active_rows:
			if row.materials[0].get_shader_parameter("wind_time")!=wind.elapsed:continuous=false
	check(not wind._scan_pending and slices>1 and wind.receivers.size()==101,"binding and cleanup finish over multiple bounded slices")
	check(continuous,"new visible bindings immediately receive current time and existing rows never freeze")
	# Mid-scan camera movement uses the current camera for cleanup, not the
	# scan's initial alive set. A synchronous refresh interrupts pending work.
	wind._begin_refresh();wind._advance_refresh(1);camera.position=Vector3(200,0,0)
	check(drain(wind)>1 and wind.receivers.is_empty() and wind.active_rows.is_empty(),"camera movement during scan removes former-radius receivers")
	camera.position=Vector3.ZERO;wind._begin_refresh();wind._advance_refresh(1);wind.refresh()
	check(not wind._scan_pending and wind.receivers.size()==101,"explicit refresh cancels pending cycle and synchronously completes")
	wind.set_meta("profile_wind_timeline",true);wind.refresh()
	var timed:Dictionary=wind.get_meta("refresh_timing")
	check(timed.end_usec>=timed.begin_usec and timed.cancel_timeline.nodes_end_usec>=timed.cancel_timeline.nodes_begin_usec and timed.cancel_timeline.keys_begin_usec>=timed.cancel_timeline.nodes_end_usec,"opt-in cleanup timeline provides ordered absolute intervals")
	wind.remove_meta("profile_wind_timeline");wind.refresh()
	check(not wind.get_meta("refresh_timing").has("cancel_timeline"),"normal profiling does not publish stale cleanup timeline")
	var removed:MeshInstance3D=new_nodes.pop_back();var removed_id:=removed.get_instance_id()
	wind._begin_refresh();wind._advance_refresh(1);removed.free()
	first.remove_from_group(Response.GROUP);drain(wind)
	check(not wind.receivers.has(removed_id) and not wind.receivers.has(first.get_instance_id()) and not first.has_meta("wind_original"),"freed nodes and removed group membership are safely cleaned during a cycle")
	Response.register(first);wind.refresh()
	var isolated:=SubViewport.new();isolated.own_world_3d=true;root.add_child(isolated)
	var alternate:=Node3D.new();isolated.add_child(alternate)
	wind._begin_refresh();first.reparent(alternate);drain(wind)
	check(not wind.receivers.has(first.get_instance_id()) and not first.has_meta("wind_original"),"moving a receiver to another World3D restores its source")
	first.reparent(scene);wind.refresh()
	wind._begin_refresh();wind._advance_refresh(1);wind.set_enabled(false)
	check(not wind._scan_pending and wind.receivers.is_empty() and wind.active_rows.is_empty() and not first.has_meta("wind_original"),"disabling cancels work and restores all sources")
	wind.set_enabled(true);wind.set_physics_process(false);wind.refresh()
	# Shelter is evaluated in the receiver's current world when its slice runs.
	var sheltered:=receiver(scene,Vector3(20,0,0),true)
	var roof:=StaticBody3D.new();scene.add_child(roof);roof.position=Vector3(20,3,0)
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(5,1,5);collision.shape=box;roof.add_child(collision)
	await physics_frame;await process_frame
	wind.advance(Vector3(3,0,1),44);wind._begin_refresh();drain(wind)
	check(wind.receivers[sheltered.get_instance_id()].exposure==0.0 and wind.receivers[sheltered.get_instance_id()].materials[0].get_shader_parameter("wind_velocity")==Vector3.ZERO,"slice shelter query suppresses force beneath roof")
	roof.position.x=40;await physics_frame;await process_frame
	wind._begin_refresh();drain(wind)
	check(wind.receivers[sheltered.get_instance_id()].exposure==1.0 and wind.receivers[sheltered.get_instance_id()].materials[0].get_shader_parameter("wind_velocity")==Vector3(3,0,1),"later periodic query restores wind after shelter moves")
	# Multiple catch-up physics ticks must not accumulate budgets in one render frame.
	wind.scan_left=0;wind._last_slice_frame=-1;wind._physics_process(.01)
	var cursor:int=wind._scan_cursor;var count:int=wind._scan_slices
	wind._physics_process(.01)
	check(wind._scan_cursor==cursor and wind._scan_slices==count and wind.scan_left<.35,"catch-up ticks consume only one slice and cadence decreases while scanning")
	wind._begin_refresh();wind._advance_refresh(1);wind.free()
	check(not first.has_meta("wind_original") and not sheltered.has_meta("wind_original"),"controller exit cancels work and restores surviving nodes")
	scene.free();isolated.free();print("WIND_REFRESH_SLICES failures=",failures);quit(failures)
