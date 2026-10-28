extends "res://tools/test_world3d_mcp.gd"
const MaterialLibrary=preload("res://scripts/world_editor/surface_material_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const River=preload("res://scripts/world3d/river_materials.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const CpuMesh=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var delayed_gate:=Semaphore.new()
var pending_result:Dictionary={}

func _start_delayed(thread:Thread,task:Callable)->int:
	return thread.start(_gated.bind(task),Thread.PRIORITY_LOW)
func _gated(task:Callable)->Variant:
	delayed_gate.wait()
	return task.call()
func _import_http(path:String)->void:
	pending_result=await call_tool("import_surface_material",{"path":path,"name":"HTTP texture","compression":"dds"})

func run()->void:
	rpc_timeout_ms=30000
	var fixture:=Paths.external_root().path_join("review_artifacts/surface_import_http_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	if DirAccess.dir_exists_absolute(fixture):push_error("fixture already exists");quit(1);return
	DirAccess.make_dir_recursive_absolute(fixture)
	var source:=fixture.path_join("source.png")
	var image:=Image.create(32,32,false,Image.FORMAT_RGBA8);image.fill(Color(.2,.6,.4))
	check(image.save_png(source)==OK,"create HTTP import source")
	var png:=image.save_png_to_buffer();var hash_:=HashingContext.new()
	hash_.start(HashingContext.HASH_SHA256);hash_.update(png)
	var library_dir:=fixture.path_join("materials");DirAccess.make_dir_recursive_absolute(library_dir)
	var expected_texture:=library_dir.path_join(hash_.finish().hex_encode()+".png")
	check(MaterialLibrary._write(expected_texture,png)==OK,"publish a prior PNG owner under the canonical path")
	Paint.refresh_sources()
	check(not Paint.has_compressed_sidecar(expected_texture),"initial sidecar negative lookup is cached")
	var definition:={"name":"old owner","color":[1,1,1,1],"roughness":0.9,"texture_path":expected_texture}
	var old_material:StandardMaterial3D=Paint.make_material(definition)
	var old_texture:Texture2D=old_material.albedo_texture
	check(old_texture!=null,"retain an old PNG material owner")
	var other_path:=fixture.path_join("unrelated.png");image.fill(Color(.7,.1,.1));image.save_png(other_path)
	var unrelated:Texture2D=Paint.texture({"texture_path":other_path})
	var river_record:={"terrain_material":definition}
	var old_river:ShaderMaterial=River.terrain(river_record)
	var other_definition:={"name":"unrelated","color":[1,1,1,1],"roughness":0.9,"texture_path":other_path}
	var other_river:ShaderMaterial=River.terrain({"terrain_material":other_definition})
	var affected_mesh:=CpuMesh.new();affected_mesh.materials=[old_material]
	var other_material:StandardMaterial3D=Paint.make_material(other_definition)
	var unrelated_mesh:=CpuMesh.new();unrelated_mesh.materials=[other_material]
	Prefab._render_meshes["test_affected"]=affected_mesh
	Prefab._render_meshes["test_unrelated"]=unrelated_mesh
	var doc:=Doc.new();doc.add_box("block",Vector3(0,1,0),Vector3(2,2,2))
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path=fixture.path_join("map.gltf");session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false;editor._material_directory=fixture.path_join("materials")
	root.add_child(editor);await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start isolated HTTP server")
	var queue:Node=editor._surface_texture_imports._queue
	queue.thread_starter=Callable(self,"_start_delayed")
	_import_http.call_deferred(source)
	var deadline:=Time.get_ticks_msec()+10000
	while editor._mcp._pending_imports.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(not editor._mcp._pending_imports.is_empty(),"HTTP request remains pending while worker is gated")
	var state:=await call_tool("editor_state")
	check(state.get("ok",false),"another HTTP client is served while import is pending")
	queue.thread_starter=Callable();delayed_gate.post()
	deadline=Time.get_ticks_msec()+30000
	while pending_result.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(pending_result.get("ok",false) and not pending_result.get("pending",false),"HTTP returns the final material rather than pending")
	if pending_result.get("ok",false):
		check(FileAccess.file_exists(pending_result.material.texture_path),"HTTP result references published PNG")
		var library:=MaterialLibrary.new(editor._material_directory)
		check(library.find(pending_result.material_id).texture_path==pending_result.material.texture_path,"shared catalog reopens HTTP material")
		if pending_result.get("dds_ready",false):
			var new_material:StandardMaterial3D=Paint.make_material(definition)
			check(new_material!=old_material and new_material.albedo_texture!=old_texture,"new owner uses refreshed DDS representation")
			check(old_material.albedo_texture==old_texture,"existing material owner remains unchanged")
			check(Paint.texture({"texture_path":other_path})==unrelated,"unrelated cached texture remains reusable")
			var new_river:ShaderMaterial=River.terrain(river_record)
			check(new_river!=old_river and old_river.get_shader_parameter("base_albedo")==old_texture,"river cache refreshes the affected source and preserves its old owner")
			check(River.terrain({"terrain_material":other_definition})==other_river,"unrelated river material stays cached")
			check(not Prefab._render_meshes.has("test_affected") and Prefab._render_meshes.get("test_unrelated")==unrelated_mesh,"prefab refresh evicts only affected mesh aliases")
			var sidecar:String=Paint.compressed_sidecar_path(expected_texture)
			var digest:String=pending_result.dds_sha
			new_material.albedo_texture.set_meta("runtime_texture_representation","dds:"+digest)
			Paint.refresh_texture_source_if_needed(expected_texture,sidecar,digest,false)
			check(Paint.make_material(definition)==new_material,"repeat verified DDS preserves the digest-identified material")
			Paint.refresh_texture_source_if_needed(expected_texture,sidecar,"0".repeat(64),false)
			check(Paint.make_material(definition)!=new_material and new_material.albedo_texture!=null,"changed DDS identity refreshes only future owners")
	var invalid:=await call_tool("import_surface_material",{"path":"C:/outside.png"},false)
	check(not invalid.get("ok",false),"outside-root request has no success")
	# Exercise the real editor LoadJob and import service concurrently. A test
	# semaphore holds the import worker so overlap does not depend on timing.
	var map_path:=fixture.path_join("concurrent/map.gltf")
	var load_doc:=Doc.new()
	for i in 80:load_doc.add_box("block",Vector3(i*3,1,0),Vector3(2,2,2))
	check(load_doc.save(map_path)==OK,"create isolated map for concurrent open")
	queue.thread_starter=Callable(self,"_start_delayed")
	var load_start:Dictionary=editor._load_job.start(map_path)
	editor._material_panel._import()
	var dialog:FileDialog
	for child:Node in editor.get_children():
		if child is FileDialog:dialog=child
	check(dialog!=null,"UI import creates its file picker")
	if dialog!=null:dialog.file_selected.emit(source)
	check(load_start.get("ok",false) and editor._surface_texture_imports.snapshot().requests>0,"open and actual UI import both start")
	deadline=Time.get_ticks_msec()+30000
	var shared_seen:=false;var worker_seen:=false
	while Time.get_ticks_msec()<deadline and editor._load_job.active and not (shared_seen and worker_seen):
		await process_frame
		if is_instance_valid(editor._load_job._preparation):
			shared_seen=editor._load_job._preparation.ledger==queue.ledger
		worker_seen=queue.ledger.active_workers()>0
	check(shared_seen and worker_seen,"actual editor open and import use the same live admission ledger")
	queue.thread_starter=Callable();delayed_gate.post()
	deadline=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline and (editor._load_job.active or editor._surface_texture_imports.snapshot().requests>0):await process_frame
	check(not editor._load_job.active and editor._surface_texture_imports.snapshot().requests==0,"concurrent open and import both complete")
	check(queue.ledger.reserved_bytes==0,"concurrent operation leases return after completion")
	editor.queue_free();await settle()
	print("SURFACE_IMPORT_HTTP failures=%d fixture=%s"%[failed,fixture]);quit(1 if failed else 0)
