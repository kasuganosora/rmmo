extends SceneTree
## Isolated real authored collision microbenchmark; never loads or saves a map.
const Snapshot=preload("res://scripts/world3d/document_source_snapshot.gd")
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Preparer=preload("res://scripts/world3d/terrain_collision_preparer.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const CameraRig=preload("res://scripts/world3d/third_person_camera.gd")
const MAP="D:/code/rmmo_runtime/cache/world3d/reference_load_checkpoint_26004507/map.gltf"
const FORMAL="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const CONTENT="D:/code/rmmo_runtime"
const ID="town_terrain_5_4"
const SPAWN=Vector3(321.2,.9,160.3)
const SAMPLES=100
var output="D:/code/rmmo_runtime/review_artifacts/town_terrain_queries_20261009.json"
var report:Dictionary={"failures":[],"runs":[],"checks":[]}
var holder:Node3D
var player:CharacterBody3D
var rig:Node3D
var faces:=PackedVector3Array()
var record:Dictionary
var pose:Transform3D
var ray_cases:Array=[]
var reference_rays:Array=[]
var reference_sweeps:Array=[]

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	report.checks.append({"ok":value,"label":label})
	if not value:report.failures.append(label);push_error(label)
func vec(v:Vector3)->Array:return [v.x,v.y,v.z]
func bounds_json(a:AABB)->Dictionary:return {"position":vec(a.position),"size":vec(a.size)}
func stats(values:Array)->Dictionary:
	var sorted:=values.duplicate();sorted.sort()
	var total:=0.0
	for v in sorted:total+=float(v)
	return {"count":sorted.size(),"p50_ms":sorted[sorted.size()/2]/1000.,"p95_ms":sorted[mini(sorted.size()-1,int(sorted.size()*.95))]/1000.,"p99_ms":sorted[mini(sorted.size()-1,int(sorted.size()*.99))]/1000.,"max_ms":sorted.back()/1000.,"mean_ms":total/maxi(1,sorted.size())/1000.}
func persist()->void:
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	report.map=MAP;report.formal_sha=FileAccess.get_sha256(FORMAL)
	report.engine=Engine.get_version_info();report.renderer=RenderingServer.get_current_rendering_method();report.physics_engine=ProjectSettings.get_setting("physics/3d/physics_engine","GodotPhysics3D")
	var snapshot=Snapshot.read_file(MAP)
	check(snapshot.error.is_empty(),"checkpoint snapshot readable")
	if not snapshot.error.is_empty():persist();quit(1);return
	var native:=Cursor.native_root(snapshot._data)
	check(native>=0,"native compact checkpoint header valid")
	if native<0:persist();quit(1);return
	var compact:Dictionary={}
	for candidate:Dictionary in snapshot._data.nodes[native].extras.rmmo_records:
		if candidate.uuid==ID:compact=candidate;break
	check(not compact.is_empty(),"single target compact record found")
	if compact.is_empty():persist();quit(1);return
	var dependencies:Dictionary={compact.rmmo_ref.uri:compact.rmmo_ref.sha256}
	var read:=Store.read_records([compact],MAP,CONTENT,dependencies,1)
	check(read.ok and read.records.size()==1,"only one complete authored definition hydrated with closure verification")
	if not read.ok:persist();quit(1);return
	record=read.records[0];pose=Terrain.transform(record)
	check(Terrain.valid(record),"authored terrain is valid")
	var cpu:=Cpu.new();cpu.surfaces=Terrain.arrays(record);cpu.bounds=Terrain.bounds(record)
	faces=cpu.collision_faces()
	var holes:Array=record.terrain_mesh.holes
	var heights:Array=record.terrain_mesh.heights
	var world_bounds:=pose*cpu.bounds
	report.geometry={"id":ID,"definition_sha":compact.rmmo_ref.sha256,"face_vertices":faces.size(),"triangles":faces.size()/3,"slice_vertices":Preparer.SLICE_VERTICES,"slice_triangles":Preparer.SLICE_VERTICES/3,"expected_slices":ceili(float(faces.size())/Preparer.SLICE_VERTICES),"local_aabb":bounds_json(cpu.bounds),"world_aabb":bounds_json(world_bounds),"position":record.position,"rotation":record.rotation,"size":record.size,"columns":record.terrain_mesh.columns,"rows":record.terrain_mesh.rows,"hole_cells":holes.count(true),"height_min":heights.min(),"height_max":heights.max(),"sample_height_at_spawn":Terrain.sample(record,pose.affine_inverse()*SPAWN)}
	report.spawn=vec(SPAWN);report.capsule={"radius":.3,"height":1.9,"center_offset_y":.05,"floor_snap_length":.2,"safe_margin":.001,"basis":"identity"}
	report.scope="Only the complete authored town_terrain_5_4 collision exists. No full map, nearby buildings, navigation, renderer meshes or gameplay services. Default 6 m / 18 degree / yaw 0 camera arm; every mode uses identical exact faces and transform."
	holder=Node3D.new();root.add_child(holder)
	player=CharacterBody3D.new();player.floor_snap_length=.2;holder.add_child(player)
	var collider:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.9;collider.shape=capsule;collider.position.y=.05;player.add_child(collider)
	rig=CameraRig.new();var camera:=Camera3D.new();camera.name="Camera3D";rig.add_child(camera);holder.add_child(rig);rig.exclude_body(player.get_rid());camera.position=Vector3(0,2,6)
	_make_rays(world_bounds)
	for mode in ["monolithic","sliced","monolithic","sliced"]:
		var spec:Dictionary={"uuid":ID,"mesh":cpu,"transform":pose,"extras":{},"ground_batch_record":record}
		var body:StaticBody3D
		var begun:=Time.get_ticks_usec()
		if mode=="monolithic":
			body=Stream._body_shell(spec);body.collision_layer=0;body.collision_mask=0;holder.add_child(body)
			var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces)
			var child:=CollisionShape3D.new();child.shape=shape;body.add_child(child)
			body.collision_layer=1;body.collision_mask=1
		else:
			# Exercise the existing exact CPU extraction, cooking and publication.
			cpu.remove_meta("runtime_terrain_shapes") if cpu.has_meta("runtime_terrain_shapes") else false
			var preparer:=Preparer.new()
			while not preparer.prepare(spec,holder):await process_frame
			body=Stream._make_body(holder,spec)
			preparer.finish()
		var build_ms:=(Time.get_ticks_usec()-begun)/1000.
		var restored:=PackedVector3Array();var shape_bounds:Array=[]
		for child:CollisionShape3D in body.get_children():
			var local_faces:PackedVector3Array=child.shape.get_faces();restored.append_array(local_faces)
			var shape_aabb:=AABB(local_faces[0],Vector3.ZERO)
			for point:Vector3 in local_faces:shape_aabb=shape_aabb.expand(point)
			shape_bounds.append(bounds_json(pose*shape_aabb))
		check(restored==faces,mode+" complete ordered exact faces match")
		player.position=SPAWN;player.velocity=Vector3.ZERO
		for warm in 12:
			await physics_frame;player.velocity=Vector3(0,-9.8/60.,0);player.move_and_slide()
		var row:Dictionary={"mode":mode,"shape_count":body.get_child_count(),"shape_world_aabbs":shape_bounds,"build_wall_ms":build_ms}
		await _measure(row)
		var rays:=_rays();var sweeps:=_sweeps()
		if reference_rays.is_empty():reference_rays=rays;reference_sweeps=sweeps
		else:
			check(_same_rays(reference_rays,rays),mode+" solid/hole/outer-edge local rays match monolithic")
			check(_same_sweeps(reference_sweeps,sweeps),mode+" local sphere sweeps match monolithic")
		row.rays=rays;row.sweeps=sweeps;report.runs.append(row);persist()
		print("TERRAIN_QUERY ",mode," ",JSON.stringify(row.timing))
		body.free();await physics_frame
	check(snapshot.matches_disk(),"checkpoint source unchanged")
	check(Store.verify_dependencies(dependencies,MAP,CONTENT,1),"authored definition closure unchanged")
	check(FileAccess.get_sha256(FORMAL)==report.formal_sha,"formal map unchanged")
	report.ray_case_count=ray_cases.size();report.success=report.failures.is_empty();persist()
	holder.free();await process_frame
	print("TERRAIN_QUERY_FINISHED ",output," failures=",report.failures.size());quit(0 if report.success else 1)

func _measure(row:Dictionary)->void:
	var move_us:Array=[];var camera_us:Array=[];var cast_us:Array=[];var ray_us:Array=[]
	var floor_count:=0;var contacts:Dictionary={};var fractions:Array=[]
	for i in SAMPLES:
		await physics_frame
		player.velocity=Vector3(0,-9.8/60.,0)
		var started:=Time.get_ticks_usec();player.move_and_slide();move_us.append(Time.get_ticks_usec()-started)
		if player.is_on_floor():floor_count+=1
		for j in player.get_slide_collision_count():
			var hit:=player.get_slide_collision(j);contacts[str(hit.get_collider().get_meta("uuid","unknown"))]=vec(hit.get_normal())
		var focus:=player.position+Vector3(0,1.9*.84-.9,0)
		var wanted:=focus+Vector3(0,sin(deg_to_rad(18)),cos(deg_to_rad(18)))*6
		started=Time.get_ticks_usec();rig._shorten(focus,wanted);camera_us.append(Time.get_ticks_usec()-started)
		var query:=_sphere_query(focus,wanted)
		started=Time.get_ticks_usec();var result:=holder.get_world_3d().direct_space_state.cast_motion(query);cast_us.append(Time.get_ticks_usec()-started)
		if i==0:fractions=Array(result);row.camera={"focus":vec(focus),"wanted":vec(wanted),"radius":.2,"margin":.015,"fractions":fractions}
		var ray:=PhysicsRayQueryParameters3D.create(player.position+Vector3.UP*5,player.position-Vector3.UP*10,1,[player.get_rid()])
		started=Time.get_ticks_usec();holder.get_world_3d().direct_space_state.intersect_ray(ray);ray_us.append(Time.get_ticks_usec()-started)
	row.timing={"move_and_slide":stats(move_us),"camera_shorten_with_allocation":stats(camera_us),"cast_motion_only":stats(cast_us),"standing_ray":stats(ray_us)}
	row.floor_samples=floor_count;row.final_player=vec(player.position);row.contacts=contacts
	check(floor_count==SAMPLES,"all "+row.mode+" samples stand on real terrain")
	check(contacts.has(ID),row.mode+" movement contacts identify requested terrain")

func _sphere_query(from:Vector3,to:Vector3)->PhysicsShapeQueryParameters3D:
	var query:=PhysicsShapeQueryParameters3D.new();var sphere:=SphereShape3D.new();sphere.radius=.2
	query.shape=sphere;query.transform=Transform3D(Basis.IDENTITY,from);query.motion=to-from;query.margin=.015;query.collide_with_areas=false;query.exclude=[player.get_rid()]
	return query

func _make_rays(world_bounds:AABB)->void:
	for z in range(-3,4):
		for x in range(-3,4):ray_cases.append({"name":"local_%s_%s"%[x,z],"xz":SPAWN+Vector3(x*.37,0,z*.37)})
	# Sample every authored hole (if present), their adjacent solid cells and edges.
	var t:Dictionary=record.terrain_mesh
	for z in int(t.rows):
		for x in int(t.columns):
			if not t.holes[z*int(t.columns)+x]:continue
			var center:=pose*((Terrain.point(record,x,z)+Terrain.point(record,x+1,z+1))*.5)
			ray_cases.append({"name":"authored_hole_%s_%s"%[x,z],"xz":center})
	for x in [-.01,.01,world_bounds.size.x-.01,world_bounds.size.x+.01]:
		for z in [world_bounds.size.z*.25,world_bounds.size.z*.75]:ray_cases.append({"name":"boundary_%s_%s"%[x,z],"xz":world_bounds.position+Vector3(x,0,z)})

func _rays()->Array:
	var result:Array=[];var space:=holder.get_world_3d().direct_space_state
	for c:Dictionary in ray_cases:
		var point:Vector3=c.xz
		var query:=PhysicsRayQueryParameters3D.create(Vector3(point.x,100,point.z),Vector3(point.x,-100,point.z),1,[player.get_rid()])
		var hit:=space.intersect_ray(query);var row:Dictionary={"case":c.name,"hit":not hit.is_empty()}
		if not hit.is_empty():row.position=vec(hit.position);row.normal=vec(hit.normal)
		result.append(row)
	return result

func _sweeps()->Array:
	var result:Array=[];var space:=holder.get_world_3d().direct_space_state
	var focus:=SPAWN+Vector3(0,.696,0)
	for yaw in [0.,45.,90.,135.,180.,225.,270.,315.]:
		for pitch in [18.,-10.]:
			var arm:=Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(pitch)),sin(deg_to_rad(pitch)),cos(deg_to_rad(yaw))*cos(deg_to_rad(pitch)))*6
			var query:=_sphere_query(focus,focus+arm);var started:=Time.get_ticks_usec();var fractions:=space.cast_motion(query)
			result.append({"yaw":yaw,"pitch":pitch,"fractions":Array(fractions),"ms":(Time.get_ticks_usec()-started)/1000.})
	return result

func _same_rays(a:Array,b:Array)->bool:
	if a.size()!=b.size():return false
	for i in a.size():
		if a[i].hit!=b[i].hit:return false
		if a[i].hit:
			for axis in 3:
				if absf(a[i].position[axis]-b[i].position[axis])>.0001 or absf(a[i].normal[axis]-b[i].normal[axis])>.0001:return false
	return true

func _same_sweeps(a:Array,b:Array)->bool:
	if a.size()!=b.size():return false
	for i in a.size():
		for j in 2:
			if absf(a[i].fractions[j]-b[i].fractions[j])>.0001:return false
	return true
