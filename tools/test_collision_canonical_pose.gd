extends SceneTree
## CPU-only real Node3D source hierarchy. Store ownership is intentionally an
## in-memory sealed fixture; the companion GPU test obtains real source proof.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Adapter=preload("res://scripts/world3d/collision_instance_preparation.gd")
const Residency=preload("res://scripts/world3d/collision_instance_residency.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const TestBase=preload("res://tools/test_prefab_texture_preparation.gd")
const SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func tree(random:RandomNumberGenerator)->Dictionary:
	var holder:=Node3D.new();holder.name="asset"
	holder.position=Vector3(321.2,.9,160.3);holder.rotation_degrees=Vector3(12.345,136.088,-4.321);holder.scale=Vector3(.7,.85,1.13)
	var parent:Node3D=holder;var local:=Transform3D.IDENTITY;var poses:Array=[]
	for depth:int in 3:
		var node:=Node3D.new();node.name="Level%d"%depth
		node.position=Vector3(random.randf_range(-10,10),random.randf_range(-2,4),random.randf_range(-10,10))
		node.rotation_degrees=Vector3(random.randf_range(-180,180),random.randf_range(-180,180),random.randf_range(-180,180))
		node.scale=Vector3(random.randf_range(.2,2),random.randf_range(.2,2),random.randf_range(.2,2))
		parent.add_child(node);parent=node;poses.append(node.transform);local=local*node.transform
	var mesh:=Cpu.new();mesh.bounds=AABB(Vector3(-6,0,-4),Vector3(12,4,8))
	mesh._collision_faces=PackedVector3Array([Vector3(-6,0,-4),Vector3(6,0,4),Vector3(6,0,-4)])
	var visual:=MeshInstance3D.new();visual.name="Solid";visual.mesh=mesh
	visual.set_meta("extras",{"uuid":"prop__Solid","rmmo_collision":"block"})
	parent.add_child(visual);local=local*visual.transform
	return {"holder":holder,"leaf":parent,"visual":visual,"mesh":mesh,"local":local,"expected":holder.transform*local,"poses":poses}

func run()->void:
	var errors:=TestBase.Errors.new();OS.add_logger(errors)
	var random:=RandomNumberGenerator.new();random.seed=20261011
	var mismatch:=0;var exact:=true;var spatial:=true;var unchanged:=true
	var first:Dictionary={}
	for sample:int in 256:
		var fixture:=tree(random);var holder:Node3D=fixture.holder
		var previous:Array=[];Deferred._collect(holder,Transform3D.IDENTITY,previous)
		var current:Array=[];Deferred._collect_collision_asset(holder,current)
		if previous[0].transform!=fixture.expected:mismatch+=1
		exact=exact and current.size()==1 and current[0].transform==fixture.expected and current[0].uuid=="prop__Solid"
		var spec:Dictionary=current[0];var bounds:AABB=fixture.expected*fixture.mesh.bounds
		spatial=spatial and spec.position==fixture.expected.origin and spec.rotation==fixture.expected.basis.get_euler() and spec.chunk==Stream.chunk_key(fixture.expected.origin) and spec.chunk_min==Stream.chunk_key(bounds.position) and spec.chunk_max==Stream.chunk_key(bounds.end)
		var node:Node3D=holder
		for pose:Transform3D in fixture.poses:
			node=node.get_child(0);unchanged=unchanged and node.transform==pose
		if sample==0:first=fixture;first.specs=current
		else:holder.free()
	check(mismatch>0,"fixture detects the original parent-first association mismatch")
	check(exact,"256 real multi-level source trees match flattened collision pose bit-for-bit")
	check(spatial,"position, rotation and all visual chunk bounds use the canonical world pose")
	check(unchanged,"collection never mutates the source hierarchy")
	await ownership(first)
	first.holder.free();OS.remove_logger(errors)
	check(errors.errors.is_empty(),"zero script or engine errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_CANONICAL_POSE checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func ownership(fixture:Dictionary)->void:
	var map:=Node3D.new();root.add_child(map);map.set_meta("source_map_sha256",SHA)
	var store:=Residency.new();map.add_child(store);store.configure(map,"res://fixture/map.gltf",SHA,1)
	var batch:=Adapter.Batch.new();batch._path="res://fixture/map.gltf";batch._sha=SHA;batch._bytes=1024;batch._sealed=true
	batch._instances=[{"uuid":"prop","record_index":0,"record_sha":SHA,"asset_path":"res://fixture/model.glb","source_sha":SHA,"pose":fixture.holder.transform,"record_identity":{},"rows":[{"uuid":"prop__Solid","selector":"root/0","transform":fixture.expected,"collision":"block","kind":"faces","faces":fixture.mesh._collision_faces,"box":Vector3.ZERO,"bounds":fixture.mesh.bounds}]}]
	check(store.enqueue(batch,1).ok,"independent exact collision row installs under the same namespace")
	store.step(1500)
	check(store.preflight_promotion(fixture.specs).ok,"canonical visual passes strict ownership and exact geometry validation")
	var leaf:Node3D=fixture.leaf;var original:Transform3D=leaf.transform;leaf.position.x+=.0001
	var altered:Array=[];Deferred._collect_collision_asset(fixture.holder,altered)
	check(not store.preflight_promotion(altered).ok,"a genuine source-local transform change remains rejected")
	leaf.transform=original
	var holder:Node3D=fixture.holder;var placement:Transform3D=holder.transform;holder.position.x+=.0001
	altered=[];Deferred._collect_collision_asset(holder,altered)
	check(not store.preflight_promotion(altered).ok,"a genuine 0.1 mm author placement change remains rejected")
	holder.transform=placement
	var wrong:=Cpu.new();wrong.bounds=fixture.mesh.bounds;wrong._collision_faces=fixture.mesh._collision_faces.duplicate();wrong._collision_faces[0].x+=.01
	altered=fixture.specs.duplicate(true);altered[0].collision_mesh=wrong
	check(not store.preflight_promotion(altered).ok,"identical pose and UUID cannot hide changed source triangles")
	check(store.debug_snapshot().owned_bodies==1 and not map.has_meta("stream_library"),"rejected publications retain collision without publishing a visual namespace")
	map.queue_free();await process_frame
