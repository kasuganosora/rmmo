extends SceneTree
const Proxy=preload("res://scripts/world3d/distant_building_proxy.gd")
class Batches extends Node:
	var groups:Dictionary={}
var failures:Array=[]
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL ",message)
func run()->void:
	var scene:=Node3D.new();root.add_child(scene)
	var batches:=Batches.new();batches.name="GroundRenderBatches";scene.add_child(batches)
	var service:=Proxy.new();scene.add_child(service);service.set_process(false)
	var visuals:Array[MeshInstance3D]=[]
	for house in 32:
		for part in 2:
			var visual:=MeshInstance3D.new();var mesh:=BoxMesh.new()
			mesh.size=Vector3(2,3,2);mesh.material=StandardMaterial3D.new();visual.mesh=mesh
			visual.position=Vector3(140+house%8*6,0,house/8*8+part*3)
			visual.set_meta("ground_batch_record",{"building":{"id":"house_"+str(house)}})
			scene.add_child(visual);visuals.append(visual)
			batches.groups[str(visual.get_instance_id())]={"category":"building","visual":visual,"members":[visual]}
	var before:=Time.get_ticks_usec()
	for i in 120:service.tick(Vector3.ZERO)
	var elapsed:=(Time.get_ticks_usec()-before)/1000.
	var captured:=0
	for visual:MeshInstance3D in visuals:
		if visual.mesh.has_meta("ground_cpu_cache"):captured+=1
	check(captured==0,"inside admission distance never downloads or captures source geometry")
	check(service._job.is_empty() and service._rows.is_empty(),"near groups never start proxy workers")
	var near_profile:Dictionary=service.profile.duplicate(true)
	service.tick(Vector3(-300,0,0))
	check(not service._job.is_empty(),"moving outside threshold immediately admits worker, without a near retry cooldown")
	var deadline:=Time.get_ticks_msec()+10000
	while not service._job.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame;service._poll()
	check(not service._rows.is_empty(),"eligible far group still publishes exact-material proxy")
	service.tick(Vector3(140,0,0))
	check(service._rows.is_empty(),"return inside exit threshold retires proxy")
	check(visuals.all(func(v):return v.layers==1 and v.visible),"return preserves original source visibility")
	var result:={"checks":checks,"failures":failures,"near_ticks":120,"source_meshes":64,"near_cpu_captures":captured,"near_tick_ms":elapsed,"near_profile":near_profile,"final_profile":service.profile.duplicate(true)}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			var file:=FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print(JSON.stringify(result));scene.queue_free();await process_frame;await process_frame
	quit(0 if failures.is_empty() else 1)
