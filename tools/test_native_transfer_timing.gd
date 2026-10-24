extends SceneTree
## Exercises the same background native PackedScene load used by white maps.
## This is a diagnostic fixture, not map performance or asset-delivery evidence.
const WORKERS:=2
const MESHES_PER_WORKER:=12
const TRIANGLES_PER_MESH:=256
var samples:Array=[]
var destination:=""
var began:=0
var completed_draws:=0
var native_inputs:Array=[]
var native_input_generation:Dictionary={}
const LOAD_MODE:="CACHE_MODE_IGNORE_DEEP"

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):destination=arg.trim_prefix("--output=")
	run.call_deferred()

func prepare_native_inputs()->bool:
	# Only the caller's unique external output prefix may own fixture input files.
	var normalized:=destination.simplify_path().replace("\\","/")
	var project:=ProjectSettings.globalize_path("res://").simplify_path().replace("\\","/").trim_suffix("/")
	if not normalized.is_absolute_path() or normalized.get_extension()!="json" or normalized.to_lower().begins_with(project.to_lower()+"/") or FileAccess.file_exists(normalized):return false
	for index:int in WORKERS:
		var path:=normalized.get_basename()+".input"+str(index)+".scn"
		if FileAccess.file_exists(path):return false
		native_inputs.append({"worker_index":index,"path":path})
	var started:=Time.get_ticks_usec()
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	vertices.resize(TRIANGLES_PER_MESH*3)
	normals.resize(vertices.size())
	for triangle:int in TRIANGLES_PER_MESH:
		var offset:=Vector3((triangle%16)*0.016,(triangle/16)*0.016,0)
		vertices[triangle*3]=offset
		vertices[triangle*3+1]=offset+Vector3(0.012,0,0)
		vertices[triangle*3+2]=offset+Vector3(0,0.012,0)
		for corner:int in 3:normals[triangle*3+corner]=Vector3.BACK
	var arrays:Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var scene:=Node3D.new()
	var instance:=MeshInstance3D.new()
	scene.add_child(instance);instance.owner=scene;instance.mesh=mesh
	var packed:=PackedScene.new()
	var error:=packed.pack(scene)
	if error==OK:
		for input:Dictionary in native_inputs:
			error=ResourceSaver.save(packed,input.path,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)
			if error!=OK:break
			input.sha256=FileAccess.get_sha256(input.path)
	scene.free();packed=null;mesh=null
	native_input_generation={"begin_ticks_us":started,"end_ticks_us":Time.get_ticks_usec(),"meshes":1,"surfaces":1,"material_present":false,"save_error":error}
	return error==OK

func build_meshes(worker_index:int,input_path:String)->Dictionary:
	var start:=Time.get_ticks_usec()
	var meshes:Array[ArrayMesh]=[]
	var mesh_ids:Array[int]=[]
	var errors:Array[String]=[]
	for mesh_index:int in MESHES_PER_WORKER:
		var loaded:Resource=ResourceLoader.load(input_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		if not loaded is PackedScene:
			errors.append("native_load_failed:"+str(mesh_index));break
		var state:SceneState=loaded.get_state()
		var found:Array[ArrayMesh]=[]
		for node:int in state.get_node_count():
			for property:int in state.get_node_property_count(node):
				if state.get_node_property_name(node,property)!=&"mesh":continue
				var mesh:Variant=state.get_node_property_value(node,property)
				if mesh is ArrayMesh:found.append(mesh)
		if found.size()!=1:
			errors.append("native_mesh_count:"+str(found.size()));break
		meshes.append(found[0]);mesh_ids.append(found[0].get_instance_id())
	return {"worker_index":worker_index,"godot_thread_id":OS.get_thread_caller_id(),
		"begin_ticks_us":start,"end_ticks_us":Time.get_ticks_usec(),"meshes":meshes,
		"input_path":input_path,"mesh_instance_ids":mesh_ids,"resource_load_mode":LOAD_MODE,"errors":errors}

func run()->void:
	if DisplayServer.get_name()=="headless":
		push_error("Native transfer fixture requires the private desktop GPU runner")
		quit(2);return
	if not prepare_native_inputs():
		push_error("Native fixture input preparation failed or output prefix already exists")
		quit(2);return
	began=Time.get_ticks_usec()
	root.size=Vector2i(320,240)
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED,root.get_window_id())
	var world:=Node3D.new()
	root.add_child(world)
	var camera:=Camera3D.new()
	world.add_child(camera)
	camera.position=Vector3(0,0,4)
	camera.current=true
	RenderingServer.frame_pre_draw.connect(pre_draw)
	RenderingServer.frame_post_draw.connect(post_draw)
	var workers:Array[Thread]=[]
	var results:Array=[]
	var meshes_created:=0
	var surfaces_valid:=true
	var unique_mesh_instances:=true
	var seen_mesh_ids:Dictionary={}
	for index:int in WORKERS:
		var worker:=Thread.new()
		if worker.start(build_meshes.bind(index,str(native_inputs[index].path)))!=OK:
			push_error("Unable to start transfer fixture worker")
			for previous:Thread in workers:previous.wait_to_finish()
			world.free();quit(2);return
		workers.append(worker)
	var frame_count:=0
	var rendered_after_publication:=0
	var publication_draw_origin:=-1
	while frame_count<600 and (frame_count<120 or rendered_after_publication<30):
		await process_frame
		frame_count+=1
		for index:int in workers.size():
			var worker:Thread=workers[index]
			if worker==null or worker.is_alive():continue
			# Join only finished threads; the main thread never waits for live uploads.
			var result:Dictionary=worker.wait_to_finish()
			workers[index]=null
			if not result.errors.is_empty():surfaces_valid=false
			for mesh:ArrayMesh in result.meshes:
				var id:=mesh.get_instance_id()
				if seen_mesh_ids.has(id):unique_mesh_instances=false
				seen_mesh_ids[id]=true
				surfaces_valid=surfaces_valid and mesh.get_surface_count()==1 and mesh.surface_get_array_len(0)==TRIANGLES_PER_MESH*3
				var instance:=MeshInstance3D.new()
				instance.mesh=mesh
				instance.position=Vector3((meshes_created%6)*0.32-0.96,(meshes_created/6)*0.32-0.64,0)
				world.add_child(instance)
				meshes_created+=1
			result.erase("meshes")
			result.published_ticks_us=Time.get_ticks_usec()
			results.append(result)
		if results.size()==WORKERS:
			if publication_draw_origin<0:publication_draw_origin=completed_draws
			rendered_after_publication=completed_draws-publication_draw_origin
	var timed_out:=results.size()!=WORKERS
	for worker:Thread in workers:
		if worker!=null:worker.wait_to_finish()
	RenderingServer.frame_pre_draw.disconnect(pre_draw)
	RenderingServer.frame_post_draw.disconnect(post_draw)
	world.free()
	var valid:=not timed_out and surfaces_valid and unique_mesh_instances and meshes_created==WORKERS*MESHES_PER_WORKER and samples.size()>=200 and rendered_after_publication>=30
	var report:={"synthetic_fixture":true,"not_map_performance_evidence":true,
		"accepted":valid,"display":DisplayServer.get_name(),"began_ticks_us":began,
		"samples":samples,"godot_thread_id":OS.get_thread_caller_id(),"workers":results,
		"meshes_created":meshes_created,"surfaces_valid":surfaces_valid,
		"native_inputs":native_inputs,"native_input_generation":native_input_generation,
		"resource_load_mode":LOAD_MODE,"unique_mesh_instances":unique_mesh_instances,
		"rendered_after_publication":rendered_after_publication,"timed_out":timed_out,
		"engine":OS.get_executable_path(),"script_sha":FileAccess.get_sha256(get_script().resource_path)}
	if not destination.is_empty():
		var file:=FileAccess.open(destination,FileAccess.WRITE)
		if file==null:quit(2);return
		file.store_string(JSON.stringify(report))
	print("NATIVE_TRANSFER_RENDER_FIXTURE ",valid," meshes=",meshes_created," markers=",samples.size())
	quit(0 if valid else 1)

func pre_draw()->void:
	samples.append({"stage":"pre","ticks_us":Time.get_ticks_usec(),"engine_frame":Engine.get_process_frames()})

func post_draw()->void:
	completed_draws+=1
	samples.append({"stage":"post","ticks_us":Time.get_ticks_usec(),"engine_frame":Engine.get_process_frames()})
