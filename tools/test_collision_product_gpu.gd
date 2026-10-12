extends "res://tools/test_collision_basis_preparation.gd"
## Private-desktop only. Real reference preparation -> prefab publication ->
## streamed physics, using temporary sources and exact authored openings.
const Products=preload("res://scripts/world3d/collision_product_cache.gd")
const Base=preload("res://tools/test_prefab_texture_preparation.gd")
const Chunk=preload("res://scripts/world3d/chunk_reference_preparation.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var files:SceneTree

func worker(callable:Callable)->Dictionary:
	var thread:=Thread.new();var error:int=thread.start(callable)
	if error!=OK:return {"error":"fixture worker start"}
	while thread.is_alive():await process_frame
	return thread.wait_to_finish()

func frozen_record()->Dictionary:
	var original:=source()
	var visual:Array=[];visual.resize(Mesh.ARRAY_MAX)
	visual[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK])
	# Render and collision slots deliberately differ. A render/paint substitution
	# would close or remove several of the physics test's openings.
	var data:Dictionary={"materials":[{"null":true}],"meshes":[
		{"bounds":AABB(Vector3.ZERO,Vector3.ONE),"box_size":Vector3.ZERO,"surfaces":[visual],"materials":[0]},
		{"bounds":original.bounds,"box_size":Vector3.ZERO,"surfaces":original.surfaces,"materials":[0]}],
		"entries":[[[0],[0,1]]],"specs":[]}
	var bytes:=var_to_bytes(data)
	var record:Dictionary=Base.Fixture.bridge("exact_collision_bridge",100,files.content_root)
	record.house_prefab={"version":1,"sha256":Index.Store._sha(bytes),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
	record.prefab_materials=[]
	return record

func compare_physics(ordinary:Mesh,cached:Mesh,pose:Transform3D,label:String)->void:
	var baseline:=world();var derived:=world()
	var reference:=reference_body(baseline.host,ordinary,pose)
	var record:=spec(cached,"product_"+label,pose)
	# Passing the actual distinct painted/render mesh must not replace solid data.
	record.mesh=BoxMesh.new();record.mesh.size=Vector3(.1,.1,.1)
	var body:=await prepared(derived,record)
	if body==null:baseline.viewport.free();derived.viewport.free();return
	check(derived.preparer.collision_product_hits==1,label+" consumes only the typed collision-solid handoff")
	geometry_equal(body,ordinary,pose,label)
	check(reference.global_transform.is_equal_approx(pose) and record.transform==pose,label+" preserves authored instance transform")
	await physics_frame;await physics_frame;await process_frame
	var before:=queries(baseline,pose);var after:=queries(derived,pose)
	check(before.rays.floor.hit and not before.rays.hole.hit and not before.rays.door_front.hit and not before.rays.door_back.hit,label+" reference includes actual floor, hole and doorway")
	var rays_equal:=true;var spheres_equal:=true
	for name_:String in before.rays:
		rays_equal=rays_equal and before.rays[name_].hit==after.rays[name_].hit
		if before.rays[name_].hit and after.rays[name_].hit:rays_equal=rays_equal and before.rays[name_].position.distance_to(after.rays[name_].position)<.0001
		for i:int in 2:spheres_equal=spheres_equal and absf(before.spheres[name_][i]-after.spheres[name_][i])<.002
	check(rays_equal,label+" ray hits, misses and positions remain exact")
	check(spheres_equal,label+" 0.2m sphere sweep retains safe/unsafe fractions")
	var start:=pose*Vector3(-3,0,-2)+Vector3.UP*.902
	var a:=player(baseline.host,start);var b:=player(derived.host,start)
	await physics_frame;await physics_frame
	var equal:=true;var grounded:=0
	for tick:int in 12:
		await physics_frame
		var velocity_:Vector3=pose.basis*Vector3(.3,0,0)+Vector3.DOWN*.5
		a.velocity=velocity_;b.velocity=velocity_;a.move_and_slide();b.move_and_slide()
		equal=equal and a.is_on_floor()==b.is_on_floor() and a.global_position.distance_to(b.global_position)<.002
		if a.is_on_floor() and b.is_on_floor():grounded+=1
	check(equal and grounded>=11,label+" capsule keeps floor contact and trajectory")
	baseline.viewport.free();derived.viewport.free()

func run()->void:
	create_timer(90).timeout.connect(func():push_error("collision product GPU timeout");quit(2))
	var errors:=Base.Errors.new();OS.add_logger(errors)
	var previous:=Products.enabled;Products.enabled=true
	files=Base.Files.new();files.content_root=Paths.external_root();files.folder=Paths.cache_directory("collision_product_gpu_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	var record:=frozen_record();var fixture:Dictionary=files.fixture("product",[record],Base.Fixture.metadata([record]))
	check(Index.build(fixture.path,files.content_root,[record]).ok,"temporary exact frozen prefab index builds")
	var index:=Index.read(fixture.path,files.content_root);var requests:Array=Index.select(index,[]).deferred_entries
	var old_packet:=await worker(Chunk.prepare.bind(index,requests,fixture.path,files.content_root))
	var key:String=record.house_prefab.sha256
	check(old_packet.error.is_empty() and Prefab.publish_prepared(record,old_packet.prefab_cpu[key]),"ordinary verified reference publishes without sidecar")
	var ordinary:Mesh=Prefab.geometry(record).source
	check(not ordinary.has_meta("runtime_collision_product"),"ordinary source has no product authority")
	Prefab._meshes.erase(key)
	var cold:=await worker(Chunk.prepare.bind(index,requests,fixture.path,files.content_root,null,null,{}, {},Products.WORKSPACE_BYTES))
	check(cold.error.is_empty() and cold.read_profile.collision_products.writes==1,"cold worker builds an optional charged exact product")
	var packet:=await worker(Chunk.prepare.bind(index,requests,fixture.path,files.content_root,null,null,{}, {},Products.WORKSPACE_BYTES))
	check(packet.error.is_empty() and packet.read_profile.collision_products.hits==1,"warm verified reference consumes persisted collision data")
	check(Prefab.publish_prepared(record,packet.prefab_cpu[key]),"main publishes the verified worker handoff")
	var geometry:=Prefab.geometry(record);var cached:Mesh=geometry.source
	check(cached!=ordinary and cached!=geometry.mesh and cached.get_meta("runtime_collision_product") is Products.Product,"typed product follows actual collision source, independently of render resources")
	check(not geometry.mesh.has_meta("runtime_collision_product"),"render-only source has no collision sidecar attached")
	check(cached.collision_faces()==ordinary.collision_faces(),"all collision vertices and winding equal original extraction")
	var visual:=MeshInstance3D.new();visual.name="product_adoption";visual.mesh=geometry.mesh
	visual.set_meta("collision_solid",cached)
	var adopted:=Stream._spec(visual)
	check(adopted.collision_mesh==cached and adopted.collision_mesh.get_meta("runtime_collision_product")==cached.get_meta("runtime_collision_product"),"real Stream adoption retains the actual immutable collision source and proof")
	visual.free()
	await compare_physics(ordinary,cached,Transform3D(Basis.IDENTITY,Vector3(0,0,0)),"identity")
	await compare_physics(ordinary,cached,Transform3D(Basis(Vector3.UP,.63).scaled_local(Vector3(1.3,1.1,.85)),Vector3(12,1,-8)),"basis_baked")
	var product:Products.Product=cached.get_meta("runtime_collision_product")
	var product_path:=Products.path_for(product.identity(),files.content_root)
	if FileAccess.file_exists(product_path):DirAccess.remove_absolute(product_path)
	Prefab._meshes.erase(key);Prefab._render_meshes.clear()
	Products.enabled=previous
	for path:String in files.created:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(fixture.path+".resources");DirAccess.remove_absolute(files.folder)
	files.free();files=null
	await process_frame;RenderingServer.force_sync();await process_frame
	OS.remove_logger(errors);check(errors.errors.is_empty(),"zero script/engine errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_PRODUCT_GPU checks=",checks," failures=",failures);quit(1 if failures else 0)
