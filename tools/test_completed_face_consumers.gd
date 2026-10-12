extends SceneTree
## Headless CPU snapshots and worker handoff only. No render mesh, active body,
## physics query, Recast bake, authored files or caches are created here.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Terrain=preload("res://scripts/world3d/terrain_collision_preparer.gd")
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
const SourceJob=preload("res://scripts/world3d/navigation_source_job.gd")
var passed:=0
var failed:=0

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if value:passed+=1
	else:failed+=1

func source(offset:Vector3=Vector3.ZERO)->Mesh:
	var floor_faces:=PackedVector3Array();var wall_faces:=PackedVector3Array()
	for z in 24:
		for x in 24:
			if x>=10 and x<14 and z>=10 and z<14:continue
			var a:=Vector3(x*.25,0,z*.25)+offset
			var b:=a+Vector3(.25,0,0);var c:=a+Vector3(.25,0,.25);var d:=a+Vector3(0,0,.25)
			floor_faces.append_array(PackedVector3Array([a,b,c,a,c,d]))
	for y in 12:
		for x in 24:
			if x>=8 and x<16 and y<10:continue
			var a:=Vector3(x*.25,y*.25,0)+offset
			var b:=a+Vector3(.25,0,0);var c:=a+Vector3(.25,.25,0);var d:=a+Vector3(0,.25,0)
			wall_faces.append_array(PackedVector3Array([a,b,c,a,c,d]))
	var vertices:=PackedVector3Array();vertices.resize(floor_faces.size())
	var indices:=PackedInt32Array();indices.resize(floor_faces.size())
	for at in floor_faces.size():
		vertices[floor_faces.size()-1-at]=floor_faces[at];indices[at]=floor_faces.size()-1-at
	var floor_surface:Array=[];floor_surface.resize(Mesh.ARRAY_MAX)
	floor_surface[Mesh.ARRAY_VERTEX]=vertices;floor_surface[Mesh.ARRAY_INDEX]=indices
	var wall_surface:Array=[];wall_surface.resize(Mesh.ARRAY_MAX);wall_surface[Mesh.ARRAY_VERTEX]=wall_faces
	var mesh:=Cpu.new();mesh.surfaces=[floor_surface,wall_surface];mesh.bounds=AABB(offset,Vector3(6,3,6))
	return mesh

func spec(mesh:Mesh,pose:Transform3D)->Dictionary:
	return {"uuid":"cpu_fixture","mesh":mesh,"collision_mesh":mesh,"transform":pose,"extras":{"rmmo_collision":"walk"}}

func exact_faces()->void:
	var mesh:=source();var arrays_before:=var_to_bytes(mesh.surfaces)
	var completed:PackedVector3Array=mesh.collision_faces();var before:=completed.duplicate()
	var shear:=Basis.IDENTITY;shear.x.y=.2
	var bases:Array[Basis]=[Basis.IDENTITY,Basis(Vector3.UP,-.7),Basis(Vector3.UP,.61).scaled_local(Vector3(1.4,.8,.9)),Basis.from_scale(Vector3(-1,2,.8)),Basis(Vector3.RIGHT,.3),shear]
	for basis:Basis in bases:
		var expanded:=Terrain._extract(mesh.surfaces,basis)
		# Empty source surfaces prove that this route cannot re-expand indices.
		var reused:=Terrain._extract([],basis,completed)
		check(reused==expanded,"prepared local faces preserve exact indexed/nonindexed multisurface order for basis "+str(basis))
		check(mesh._collision_faces==before and var_to_bytes(mesh.surfaces)==arrays_before,"private basis conversion preserves shared local faces and source arrays")
		var pose:=Transform3D(basis,Vector3(321.2,7,160.3))
		check(Transform3D(Basis.IDENTITY,pose.origin)*reused==pose*completed,"translation remains applied once after exact basis conversion")
	var static_pose:=Transform3D(bases[2],Vector3.ZERO)
	check(not Terrain._basis_variant(spec(mesh,static_pose)).key.is_empty(),"positive upright nonuniform/yaw source retains basis baking")
	for basis:Basis in [bases[3],bases[4],shear]:
		check(Terrain._basis_variant(spec(mesh,Transform3D(basis,Vector3.ZERO))).key.is_empty(),"negative scale, pitch and shear retain the previous body-transform fallback")
	var door:=spec(mesh,static_pose);door.extras.fixture={"kind":"door"}
	check(Terrain._basis_variant(door).key.is_empty(),"animated doors retain their independent body transform owner")

func finish_worker(preparer:RefCounted)->PackedVector3Array:
	var deadline:=Time.get_ticks_msec()+10000
	while preparer._thread!=null and preparer._thread.is_alive() and Time.get_ticks_msec()<deadline:await process_frame
	if preparer._thread==null:return PackedVector3Array()
	var packet:Dictionary=preparer._thread.wait_to_finish();preparer._thread=null
	Terrain.WorkerRetirement.complete(preparer._retirement)
	return packet.get("faces",PackedVector3Array())

func terrain_dispatch()->void:
	var host:=Node.new();root.add_child(host)
	var mesh:=source();var original:PackedVector3Array=mesh.collision_faces().duplicate()
	var basis:=Basis(Vector3.UP,.43).scaled_local(Vector3(1.2,1.3,.85))
	var pose:=Transform3D(basis,Vector3(21,2,37));var record:=spec(mesh,pose)
	var preparer:=Terrain.new()
	check(not preparer.prepare(record,host,1) and preparer._thread!=null and preparer._body==null,"rotated completed faces dispatch to the existing worker before body installation")
	check(preparer.prepared_face_transform_hits==1 and preparer.prepared_face_hits==1 and preparer.face_expansions==0,"rotated fast path reports reuse and performs zero surface expansions")
	var ready:PackedVector3Array=await finish_worker(preparer)
	check(ready==Terrain._extract(mesh.surfaces,basis) and mesh._collision_faces==original,"production worker transforms the private completed snapshot exactly")
	preparer.cancel()
	var replacement:=source(Vector3.UP*.37);replacement.collision_faces()
	record=spec(mesh,pose)
	preparer.prepare(record,host,1)
	# Change both capture and pose while the first result is still unpublished.
	var changed_pose:=Transform3D(Basis(Vector3.UP,1.1).scaled_local(Vector3(.9,1.4,1.1)),Vector3(-11,3,19))
	var changed:=spec(replacement,changed_pose)
	var deadline:=Time.get_ticks_msec()+10000
	while preparer._thread.is_alive() and Time.get_ticks_msec()<deadline:await process_frame
	check(not preparer.prepare(changed,host,1) and preparer._thread!=null and preparer._mesh==replacement,"replacement request discards the completed old source and dispatches the new snapshot")
	ready=await finish_worker(preparer)
	check(ready==Terrain._extract(replacement.surfaces,changed_pose.basis) and not record.has("prepared_body"),"old capture or basis cannot be relabelled as replacement geometry")
	preparer.cancel()
	for enabled:bool in [false,true]:
		var cold:=source()
		if not enabled:cold.collision_faces()
		Terrain.prepared_faces_enabled=enabled
		var fallback:=Terrain.new();var cold_record:=spec(cold,pose)
		check(not fallback.prepare(cold_record,host,1) and fallback.face_expansions==1 and fallback.prepared_face_hits==0,"empty or disabled completed cache retains the existing expansion worker")
		ready=await finish_worker(fallback)
		check(ready==Terrain._extract(cold.surfaces,basis),"fallback and completed paths produce the same transformed soup")
		fallback.cancel()
	Terrain.prepared_faces_enabled=true
	host.free()

func navigation_dispatch()->void:
	var mesh:=source();var local:PackedVector3Array=mesh.collision_faces().duplicate()
	for state:Array in [[true,true],[false,false],[false,true]]:
		var nav:=Navigation.new();nav.ready_for_queries=state[0];nav.covered_loading=state[1]
		var basis:=Basis(Vector3.UP,-.63).scaled_local(Vector3(-1.2,1.4,.8))
		var pose:=Transform3D(basis,Vector3(300,7,155));var record:=spec(mesh,pose)
		var target:=NavigationMeshSourceGeometryData3D.new()
		check(nav._add_source(target,record) and nav._face_worker==null and nav.prepared_face_hits==1 and nav.face_extractions==0,"navigation consumes completed local soup without extraction in state "+str(state))
		var result:NavigationMeshSourceGeometryData3D=nav._prepare_source(target)
		var deadline:=Time.get_ticks_msec()+10000
		while result==null and Time.get_ticks_msec()<deadline:
			await process_frame;result=nav._prepare_source(target)
		var expected:=SourceJob.build([[Terrain._extract(mesh.surfaces),pose]])
		check(result!=null and result.get_vertices()==expected.get_vertices() and result.get_indices()==expected.get_indices(),"navigation keeps exact negative-scale world transform and authored holes")
		check(mesh._collision_faces==local,"navigation never transforms the shared source in place")
		var translated:=spec(mesh,Transform3D(pose.basis,Vector3(-33,2,90)))
		check(nav._add_source(NavigationMeshSourceGeometryData3D.new(),translated) and nav.prepared_face_hits==1,"later instances retain navigation's existing geometry-key reuse")
		var door:=record.duplicate(true);door.extras.fixture={"kind":"door"}
		check(not nav._collides(door),"navigation still excludes dynamic door leaf faces from the static bake")
		nav.free()
	var nav:=Navigation.new();nav.covered_loading=false
	var cold:=source(Vector3.UP*.7);var cold_spec:=spec(cold,Transform3D.IDENTITY)
	var target:=NavigationMeshSourceGeometryData3D.new()
	check(not nav._add_source(target,cold_spec) and nav._face_worker!=null,"navigation without completed faces still prepares a large CPU source asynchronously")
	var deadline:=Time.get_ticks_msec()+10000
	while nav._face_worker.is_alive() and Time.get_ticks_msec()<deadline:await process_frame
	check(nav._add_source(target,cold_spec) and nav.face_extractions==1 and nav.prepared_face_hits==0,"navigation fallback joins one exact expansion without masquerading as reuse")
	check(cold._collision_faces.is_empty(),"fallback worker does not populate or mutate the live source cache")
	nav.free()

func run()->void:
	create_timer(60).timeout.connect(func():push_error("completed face CPU test timeout");quit(2))
	var previous:=Terrain.prepared_faces_enabled;Terrain.prepared_faces_enabled=true
	exact_faces()
	await terrain_dispatch()
	await navigation_dispatch()
	Terrain.prepared_faces_enabled=previous
	await process_frame
	print("COMPLETED_FACE_CONSUMERS passed=",passed," failures=",failed)
	quit(1 if failed else 0)
