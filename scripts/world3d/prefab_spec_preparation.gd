extends RefCounted
## Private projection of an already published native white prefab. The caller
## retains the existing job lease and geometry publication/retirement policy.
## No Node, resource read, geometry copy, cache, or scene-thread call is needed.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const Collision=preload("res://scripts/world3d/model_collision_requirements.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
var record:Dictionary={}
var geometry:Dictionary={}
var draw_order:=0
var complete:=false
var specs:Array=[]
var profile:Dictionary={"slices":0,"elapsed_us":0,"max_slice_us":0,"nodes_created":0,"nodes_visited":0,"nodes_freed":0,"subtree_free_calls":0,"meshes_projected":0}

static func supports(value:Dictionary,entry:Dictionary,local_collision:bool=false)->bool:
	if local_collision or not Controls.white_materials or not Controls.discard_map_textures:return false
	# Box prefabs already contain their authored dimensions. Asset scale uses a
	# Node3D decomposition, and paint has a separate geometry preparation path.
	if value.get("kind")!="box" or not value.has("house_prefab") or not value.get("surface_paint",[]).is_empty():return false
	if not entry.get("mesh") is Cpu or not entry.get("source") is Cpu:return false
	# Stream._spec creates a BoxMesh for this uncommon primitive source. Keep
	# that resource-producing branch on the existing main-thread adapter.
	if entry.source.box_size!=Vector3.ZERO and (not Collision.enabled or value.get("collision")!="none"):return false
	return true

static func project_fields(value:Dictionary,local_bounds:AABB,order:int)->Dictionary:
	# This stage consumes only record data and bounds, so a preparation worker
	# can produce it before the main thread binds the canonical shared owners.
	# The returned dictionaries belong to this instance, not a model cache.
	var pose:=Fixtures.transform(value)
	var bounds:AABB=pose*local_bounds
	var extras:Dictionary={"uuid":value.uuid,"kind":value.kind,"surface_id":value.surface_id,"rmmo_collision":value.collision}
	for field:String in ["building","fortification","fixture"]:
		if value.has(field):extras[field]=value[field].duplicate(true)
	var result:Dictionary={"native_visual":false,"uuid":str(value.uuid),"position":pose.origin,"rotation":pose.basis.get_euler(),"transform":pose,"chunk_min":Stream.chunk_key(bounds.position),"chunk_max":Stream.chunk_key(bounds.end),"chunk":Stream.chunk_key(pose.origin),"cast_shadow":GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"extras":extras,"map_draw_order":order,"ground_batch_record":value}
	if extras.has("fixture"):
		# Same swept hinge bounds as Fixtures.prepare_spec, using the supplied
		# CPU bounds so this field-only stage never needs a Mesh Resource.
		var fixture:Dictionary=extras.fixture
		result.closed_transform=pose*Fixtures.pose(Transform3D.IDENTITY,fixture,float(fixture.open)).affine_inverse()
		var pivot:Vector3=result.closed_transform*Fixtures.vec(fixture.pivot)
		var radius:=0.0
		for i:int in 8:radius=maxf(radius,(result.closed_transform*local_bounds.get_endpoint(i)).distance_to(pivot))
		result.chunk_min=Stream.chunk_key(pivot-Vector3.ONE*radius)
		result.chunk_max=Stream.chunk_key(pivot+Vector3.ONE*radius)
	return result

static func bind_geometry(fields:Dictionary,entry:Dictionary)->Dictionary:
	# Consume one private fields packet. Do not copy CPU arrays or substitute
	# another geometry owner: aliases and typed collision products stay intact.
	fields.mesh=entry.mesh
	fields.surface_overrides=[];fields.surface_overrides.resize(entry.mesh.surfaces.size())
	# Native surface getters return an Object-typed null, distinct from the
	# GDScript NIL Variant in array equality. ID zero supplies that exact empty
	# Object value without constructing a disposable MeshInstance3D.
	fields.material_override=instance_from_id(0)
	fields.surface_overrides.fill(fields.material_override)
	if Collision.needs_adopted_collision(fields.extras):fields.collision_mesh=entry.source
	return fields

func begin(value:Dictionary,entry:Dictionary,order:int)->void:
	record=value;geometry=entry;draw_order=order

func advance(_budget_usec:int)->bool:
	if complete:return true
	var began:=Time.get_ticks_usec()
	specs.append(bind_geometry(project_fields(record,geometry.mesh.bounds,draw_order),geometry))
	complete=true;record={};geometry={}
	var elapsed:=Time.get_ticks_usec()-began
	profile.slices+=1;profile.elapsed_us+=elapsed;profile.max_slice_us=elapsed;profile.meshes_projected=1
	return true

func dispose()->void:
	record={};geometry={};specs.clear();complete=true
