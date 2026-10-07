extends SceneTree
## Exact frozen source geometry; no authored edits, material uploads or visuals.
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	Engine.max_fps=60
	var args:=OS.get_cmdline_user_args()
	var source:="D:/code/rmmo_runtime/cache/world3d/bridge_perf_20261006/map.gltf"
	var uuid:="stone_e_0be972769041dbc9"
	var parsed:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source));var record:Dictionary={}
	for node in parsed.nodes:
		for candidate in node.get("extras",{}).get("rmmo_records",[]):
			if candidate.uuid==uuid:record=candidate;break
	if record.is_empty():quit(1);return
	var data:=Prefab.decode(record.house_prefab)
	if data.is_empty():quit(1);return
	var value:Dictionary=data.meshes[data.entries[0][1][1]]
	var mesh:=Cpu.new();mesh.surfaces=value.surfaces;mesh.bounds=value.bounds;mesh.box_size=value.box_size;mesh.materials.resize(mesh.surfaces.size())
	var pose:Transform3D=preload("res://scripts/world3d/building_fixtures.gd").transform(record)
	if record.kind=="asset":pose.basis=pose.basis.scaled(Vector3(record.size[0],record.size[1],record.size[2]))
	var spec:={"uuid":uuid,"mesh":mesh,"collision_mesh":mesh,"transform":pose,"position":pose.origin,"ground_batch_record":record,"extras":{"rmmo_collision":record.collision,"kind":record.kind,"surface_id":record.surface_id}}
	var host:=Node3D.new();root.add_child(host)
	var preparer=preload("res://scripts/world3d/terrain_collision_preparer.gd").new();preparer.profile_enabled=true
	# Match a returning initial-load bridge: an old exact monolithic shape exists.
	spec.shape=Stream._triangle_shape(mesh);mesh.set_meta("runtime_concave_shape",spec.shape)
	var outcomes:Array=[]
	for pass_ in 2:
		preparer.profile_rows=[]
		var deadline:=Time.get_ticks_msec()+30000
		while not preparer.prepare(spec,host):
			if Time.get_ticks_msec()>deadline:quit(1);return
			await process_frame
		var body:StaticBody3D=spec.prepared_body
		outcomes.append({"pass":pass_,"shapes":body.get_child_count(),"rows":preparer.profile_rows.duplicate(true)})
		body.free();spec.erase("prepared_body")
		await process_frame
	var output:={"uuid":uuid,"source_geometry_bytes":record.house_prefab.length,"outcomes":outcomes}
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(output,"\t"));print("STREAM_COLLISION_PROFILE ",JSON.stringify(output))
	preparer.finish();host.queue_free();await process_frame;quit()
