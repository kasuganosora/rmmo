extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	create_timer(80).timeout.connect(func():quit(2))
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(4,5,10);camera.look_at(Vector3(4,0,4));camera.current=true
	var box:=BoxMesh.new();box.size=Vector3(.3,.2,.3);box.material=StandardMaterial3D.new()
	var cpu:Mesh=Cpu.capture(box);var original:=var_to_bytes(cpu.surfaces)
	var override:=StandardMaterial3D.new();override.albedo_color=Color.RED
	var override_spec:={"uuid":"override_probe","mesh":cpu,"ground_batch_record":{"kind":"box"},"material_override":override,"surface_overrides":[]}
	var probe:MeshInstance3D=Stream._spawn(override_spec,true)
	check(probe.mesh is Cpu and probe.has_meta("deferred_gpu") and probe.mesh.surface_get_material(0)==override and probe.material_override==null,"instance-wide override stays CPU-only before batch membership")
	check(cpu.materials[0]==box.material and probe.mesh!=cpu,"instance material fork preserves the shared source descriptor")
	preload("res://scripts/world3d/ground_batcher.gd").restore(probe)
	check(probe.mesh.get_rid().is_valid() and probe.get_active_material(0)==override,"standalone fallback retains the exact effective override")
	probe.free();override_spec.material_override=null;override_spec.surface_overrides=[override]
	probe=Stream._spawn(override_spec,true)
	check(probe.mesh is Cpu and probe.get_active_material(0)==override,"surface override also stays CPU-only with its effective material")
	probe.free()
	var library:Array=[]
	for i:int in 785:
		var position:=Vector3((i%28)*.3,0,(i/28)*.3)
		var id:="source%d"%i
		var record:Dictionary={"uuid":id,"kind":"box","surface_id":"block" if i==784 else "ground","collision":"none","size":[.3,.2,.3],"position":[position.x,0,position.z],"rotation":[0,0,0]}
		library.append({"uuid":id,"position":position,"rotation":Vector3.ZERO,"transform":Transform3D(Basis.IDENTITY,position),"chunk":Stream.chunk_key(position),"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO,"mesh":cpu,"material_override":null,"surface_overrides":[],"cast_shadow":GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"extras":{"rmmo_collision":"none","surface_id":record.surface_id},"ground_batch_record":record})
		if i%2==0:library.back().material_override=override
	var map:=Node3D.new();root.add_child(map);map.set_meta("stream_library",library);map.set_meta("defer_source_upload",true)
	var index_data:Dictionary=Index.build(library)
	for key:String in index_data:map.set_meta(key,index_data[key])
	var saw_preparation:=false
	var deadline:=Time.get_ticks_msec()+60000
	while not map.has_meta("stream_chunk") and Time.get_ticks_msec()<deadline:
		Stream.sync(map,map,Vector3(4,0,4),Stream.LOAD_BUDGET)
		var batches:Node=map.get_node_or_null("GroundRenderBatches")
		if batches!=null and not batches._preparation.is_empty() and not saw_preparation:
			saw_preparation=true
			check(batches._preparation.cursor==0 and not map.has_meta("stream_chunk"),"loading queues batch preparation without a synchronous collection loop or premature settlement")
			var sources:Dictionary=map.get_meta("stream_meshes")
			check(sources.values().all(func(node):return node.mesh is Cpu and node.has_meta("deferred_gpu")),"unresolved membership retains CPU sources instead of uploading every source prematurely")
		await process_frame
	check(saw_preparation and map.has_meta("stream_chunk"),"sliced collection and source fallback eventually settle")
	var batches:Node=map.get_node("GroundRenderBatches")
	while (not batches.pending.is_empty() or not batches._workers.is_empty()) and Time.get_ticks_msec()<deadline:await process_frame
	var sources:Dictionary=map.get_meta("stream_meshes")
	check(sources.size()==785 and sources.source784.mesh.get_rid().is_valid() and not sources.source784.mesh is Cpu,"ineligible singleton gets its independent GPU mesh after membership is known")
	check(batches.groups.size()>0 and batches.groups.values().all(func(group):return is_instance_valid(group.get("visual")) and group.visual.mesh.get_rid().is_valid()),"eligible members publish complete real GPU batches")
	check(sources.values().all(func(node):return not node.has_meta("deferred_gpu")),"no deferred upload marker survives completed residency")
	check(batches.live_worker_joins==0,"frame callbacks perform zero live CPU-worker joins")
	check(original==var_to_bytes(cpu.surfaces),"batching and fallback preserve original CPU geometry bytes")
	await RenderingServer.frame_post_draw
	map.free();camera.free();await process_frame
	print("SLICED_LOADING_BATCHES checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
