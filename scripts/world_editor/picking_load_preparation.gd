extends RefCounted
## Capture is main-only. The worker owns just a private CPU mesh and output soup.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const MIN_VERTICES:=65536

static func snapshot(source:Mesh)->Dictionary:
	if source is BoxMesh:return {}
	var cpu:Mesh=Cpu.capture(source)
	if not cpu._collision_faces.is_empty():return {}
	var count:=0
	for arrays:Array in cpu.surfaces:
		var indices:Variant=arrays[Mesh.ARRAY_INDEX]
		count+=indices.size() if indices!=null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
	if count<MIN_VERTICES:return {}
	# Copy nested Array containers; PackedArray buffers remain copy-on-write.
	return {"source":source,"cpu":cpu,"surfaces":cpu.surfaces.duplicate(true)}

static func extract(surfaces:Array)->Dictionary:
	var started:=Time.get_ticks_usec();var private_mesh:=Cpu.new()
	private_mesh.surfaces=surfaces
	return {"faces":private_mesh.collision_faces(),"elapsed_us":Time.get_ticks_usec()-started}

static func publish(snapshot:Dictionary,faces:PackedVector3Array)->bool:
	# A material or geometry edit invalidates capture, even if an old live body
	# retains its old CPU resource. Never publish the old snapshot into the new one.
	if Cpu.capture(snapshot.source)!=snapshot.cpu:return false
	snapshot.cpu._collision_faces=faces
	return true
