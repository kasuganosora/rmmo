extends "res://tools/benchmark_town_terrain_queries.gd"
## Diagnose exact imported courtyard walls without changing authored resources.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const WALL_IDS=["obj_310008","obj_310009"]
var selected_modes:Array=["monolithic","sliced","scale_baked","scale_baked_sliced","monolithic_repeat"]
var spatial_centroids:=PackedVector3Array()
var spatial_leaves:Array=[]
var spatial_leaf_limit:=1024

func run()->void:
	output="D:/code/rmmo_runtime/review_artifacts/garden_wall_queries_20261009.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--modes="):selected_modes=Array(arg.trim_prefix("--modes=").split(","))
	report.map=MAP;report.formal_sha=FileAccess.get_sha256(FORMAL)
	report.engine=Engine.get_version_info();report.renderer=RenderingServer.get_current_rendering_method()
	var snapshot=Snapshot.read_file(MAP);var native:=Cursor.native_root(snapshot._data)
	var compact:Array=[];var dependencies:Dictionary={}
	for candidate:Dictionary in snapshot._data.nodes[native].extras.rmmo_records:
		if candidate.uuid in WALL_IDS or candidate.uuid==ID:
			compact.append(candidate);dependencies[candidate.rmmo_ref.uri]=candidate.rmmo_ref.sha256
	var read:=Store.read_records(compact,MAP,CONTENT,dependencies,1)
	check(read.ok and read.records.size()==3,"only two walls and ground hydrated from verified compact definitions")
	if not read.ok or read.records.size()!=3:persist();quit(1);return
	var document:=Doc.new();var walls:Array=[];var model_hashes:Dictionary={};var holders:Array=[]
	for authored:Dictionary in read.records:
		if authored.uuid==ID:record=authored;continue
		model_hashes[authored.asset_path]=FileAccess.get_sha256(authored.asset_path)
		var scene:=document._asset(authored);holders.append(scene)
		var specs:Array=[];Deferred._collect(scene,Transform3D.IDENTITY,specs)
		check(specs.size()==1,"one complete wall render/collision mesh per namespace")
		for spec:Dictionary in specs:
			var source:Mesh=spec.get("collision_mesh",spec.mesh)
			var cpu:=Cpu.capture(source);var wall_faces:PackedVector3Array=cpu.collision_faces()
			walls.append({"spec":spec,"cpu":cpu,"faces":wall_faces,"record":authored})
			var row:=_geometry_diagnostics(wall_faces)
			row.uuid=spec.uuid;row.asset_path=authored.asset_path;row.source_sha=model_hashes[authored.asset_path];row.authored_scale=authored.size;row.basis_scale=vec(spec.transform.basis.get_scale());row.basis_determinant=spec.transform.basis.determinant();row.rotation=authored.rotation;row.world_aabb=bounds_json(spec.transform*cpu.bounds)
			if not report.has("walls"):report.walls=[]
			report.walls.append(row)
	holder=Node3D.new();root.add_child(holder)
	var ground_cpu:=Cpu.new();ground_cpu.surfaces=Terrain.arrays(record);ground_cpu.bounds=Terrain.bounds(record)
	var ground_spec:Dictionary={"uuid":ID,"mesh":ground_cpu,"transform":Terrain.transform(record),"extras":{},"ground_batch_record":record}
	var ground:=Stream._make_body(holder,ground_spec)
	player=CharacterBody3D.new();player.floor_snap_length=.2;holder.add_child(player)
	var collider:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.9;collider.shape=capsule;collider.position.y=.05;player.add_child(collider)
	rig=CameraRig.new();var camera:=Camera3D.new();camera.name="Camera3D";rig.add_child(camera);holder.add_child(rig);rig.exclude_body(player.get_rid());camera.position=Vector3(0,2,6)
	report.scope="Exact real wall meshes and instance transforms from compact checkpoint via production asset loader and Deferred._collect, plus exact terrain. No other map objects. Scale-baked cases preserve the same world triangles within 0.1 mm. No shape simplification or source edits."
	for mode:String in selected_modes:
		var bodies:Array=[];var shape_count:=0;var begun:=Time.get_ticks_usec()
		for wall:Dictionary in walls:
			var spec:Dictionary=wall.spec.duplicate();spec.erase("shape");spec.erase("prepared_body")
			var cpu:Mesh=wall.cpu;var wall_faces:PackedVector3Array=wall.faces
			if mode.begins_with("spatial_sliced"):
				var limit:=128 if mode.ends_with("128") else 1024
				var reordered:=_spatial_faces(wall_faces,limit)
				var source_hash:=_triangle_multiset_hash(wall_faces);var reordered_hash:=_triangle_multiset_hash(reordered)
				check(source_hash==reordered_hash,"spatial exact oriented triangle multiset unchanged "+spec.uuid)
				var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=reordered
				var replacement:=Cpu.new();replacement.surfaces=[arrays];replacement.bounds=cpu.bounds;cpu=replacement;wall_faces=reordered
				if not report.has("spatial_partition"):report.spatial_partition=[]
				report.spatial_partition.append({"uuid":spec.uuid,"triangle_multiset_sha256":source_hash,"leaf_triangle_limit":limit,"leaves":spatial_leaves.duplicate(true),"algorithm":"longest centroid axis median snapped to leaf boundaries; no triangle deletion, rotation, scaling or winding change"})
			if mode.begins_with("scale_baked") or mode.begins_with("basis_baked"):
				var source_pose:Transform3D=spec.transform;var scale_:Vector3=source_pose.basis.get_scale()
				var baked:=PackedVector3Array();baked.resize(wall_faces.size())
				var entire_basis:=mode.begins_with("basis_baked")
				var rotated_pose:=Transform3D(Basis.IDENTITY if entire_basis else source_pose.basis.orthonormalized(),source_pose.origin);var maximum_error:=0.
				for i in wall_faces.size():
					baked[i]=source_pose.basis*wall_faces[i] if entire_basis else wall_faces[i]*scale_;maximum_error=maxf(maximum_error,(source_pose*wall_faces[i]).distance_to(rotated_pose*baked[i]))
				check(maximum_error<.0001,mode+" world triangles equal within 0.1 mm "+spec.uuid)
				if not report.has("baked_geometry"):report.baked_geometry=[]
				report.baked_geometry.append({"mode":mode,"uuid":spec.uuid,"max_world_vertex_error_m":maximum_error,"body_basis":str(rotated_pose.basis)})
				var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=baked
				var replacement:=Cpu.new();replacement.surfaces=[arrays];replacement.bounds=cpu.bounds;cpu=replacement;wall_faces=baked;spec.transform=rotated_pose
			spec.mesh=cpu;spec.collision_mesh=cpu
			var body:StaticBody3D
			if mode=="production_sliced":
				# Explicitly opt into current production behavior. Other diagnostic
				# modes keep their historical geometry/transform meaning as it evolves.
				var preparer:=Preparer.new()
				while not preparer.prepare(spec,holder):await process_frame
				body=Stream._make_body(holder,spec);preparer.finish()
			elif mode.ends_with("128") or mode.ends_with("sliced"):
				body=Stream._body_shell(spec);body.collision_layer=0;body.collision_mask=0;holder.add_child(body)
				var slice_vertices:=384 if mode.ends_with("128") else 3072
				for start in range(0,wall_faces.size(),slice_vertices):
					var shape:=ConcavePolygonShape3D.new();shape.set_faces(wall_faces.slice(start,mini(start+slice_vertices,wall_faces.size())))
					var child:=CollisionShape3D.new();child.shape=shape;body.add_child(child)
				body.collision_layer=1;body.collision_mask=1
			else:body=Stream._make_body(holder,spec)
			var restored:=PackedVector3Array()
			for child:CollisionShape3D in body.get_children():restored.append_array(child.shape.get_faces())
			if mode=="production_sliced":
				var max_error:=0. if restored.size()==wall_faces.size() else INF
				if restored.size()==wall_faces.size():
					for i in wall_faces.size():max_error=maxf(max_error,(spec.transform*wall_faces[i]).distance_to(body.global_transform*restored[i]))
				check(max_error<.0001,"production exact ordered world triangles retained "+spec.uuid)
				if not report.has("production_geometry"):report.production_geometry=[]
				report.production_geometry.append({"uuid":spec.uuid,"max_world_vertex_error_m":max_error,"basis_baked":body.get_meta("collision_basis_baked",false)})
			else:check(restored==wall_faces,mode+" exact ordered faces retained "+spec.uuid)
			shape_count+=body.get_child_count();bodies.append(body)
		var row:Dictionary={"mode":mode,"shape_count":shape_count,"build_wall_ms":(Time.get_ticks_usec()-begun)/1000.}
		player.position=SPAWN;player.velocity=Vector3.ZERO
		for warm in 12:await physics_frame;player.velocity=Vector3(0,-9.8/60.,0);player.move_and_slide()
		await _measure(row)
		var sweeps:=_sweeps();row.sweeps=sweeps
		if reference_sweeps.is_empty():reference_sweeps=sweeps
		else:check(_same_sweeps(reference_sweeps,sweeps),mode+" sphere sweep fractions match original")
		report.runs.append(row);persist();print("GARDEN_QUERY ",mode," ",JSON.stringify(row.timing))
		for body:StaticBody3D in bodies:body.free()
		await physics_frame
	check(snapshot.matches_disk(),"checkpoint unchanged")
	check(Store.verify_dependencies(dependencies,MAP,CONTENT,1),"definition closure unchanged")
	for path:String in model_hashes:check(FileAccess.get_sha256(path)==model_hashes[path],"model source SHA unchanged")
	check(FileAccess.get_sha256(FORMAL)==report.formal_sha,"formal map unchanged")
	report.success=report.failures.is_empty();persist()
	holder.free()
	for scene:Node in holders:scene.free()
	await process_frame
	print("GARDEN_QUERY_FINISHED ",output," failures=",report.failures.size());quit(0 if report.success else 1)

func _geometry_diagnostics(input:PackedVector3Array)->Dictionary:
	var degenerates:=0;var tiny:=0;var duplicates:=0;var seen:Dictionary={};var min_area:=INF;var max_area:=0.;var total_area:=0.
	for start in range(0,input.size(),3):
		var a:Vector3=input[start];var b:Vector3=input[start+1];var c:Vector3=input[start+2]
		var area:=(b-a).cross(c-a).length()*.5
		if area<=.0000000001:degenerates+=1
		if area<.000001:tiny+=1
		min_area=minf(min_area,area);max_area=maxf(max_area,area);total_area+=area
		var points:Array=[var_to_bytes(a).hex_encode(),var_to_bytes(b).hex_encode(),var_to_bytes(c).hex_encode()];points.sort()
		var key:String="|".join(points)
		if seen.has(key):duplicates+=1
		seen[key]=true
	return {"triangles":input.size()/3,"degenerate_at_1e_10_m2":degenerates,"tiny_below_1e_6_m2":tiny,"exact_duplicates_ignoring_winding":duplicates,"min_area_m2":min_area,"max_area_m2":max_area,"sum_area_m2":total_area}

func _spatial_faces(input:PackedVector3Array,leaf_limit:int=1024)->PackedVector3Array:
	spatial_centroids.clear();spatial_leaves.clear()
	spatial_leaf_limit=leaf_limit
	var indices:Array=[]
	for index in input.size()/3:
		indices.append(index);spatial_centroids.append((input[index*3]+input[index*3+1]+input[index*3+2])/3.)
	var ordered:=_spatial_order(indices)
	var result:=PackedVector3Array();result.resize(input.size());var cursor:=0
	for triangle:int in ordered:
		for corner in 3:result[cursor]=input[triangle*3+corner];cursor+=1
	return result

func _spatial_order(indices:Array)->Array:
	var bounds:=AABB(spatial_centroids[indices[0]],Vector3.ZERO)
	for index:int in indices:bounds=bounds.expand(spatial_centroids[index])
	if indices.size()<=spatial_leaf_limit:
		spatial_leaves.append({"triangles":indices.size(),"centroid_aabb":bounds_json(bounds)})
		return indices
	var axis:=bounds.size.max_axis_index()
	indices.sort_custom(func(a:int,b:int)->bool:return spatial_centroids[a][axis]<spatial_centroids[b][axis] if spatial_centroids[a][axis]!=spatial_centroids[b][axis] else a<b)
	# Full leaves align with fixed-size physical shape chunks.
	var split:=clampi(roundi(float(indices.size())/(spatial_leaf_limit*2))*spatial_leaf_limit,spatial_leaf_limit,indices.size()-1)
	var result:=_spatial_order(indices.slice(0,split));result.append_array(_spatial_order(indices.slice(split)))
	return result

func _triangle_multiset_hash(input:PackedVector3Array)->String:
	var encoded:Array=[]
	for start in range(0,input.size(),3):encoded.append(var_to_bytes(input.slice(start,start+3)).hex_encode())
	encoded.sort()
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256)
	for triangle:String in encoded:context.update(triangle.to_ascii_buffer())
	return context.finish().hex_encode()
