extends RefCounted
## Exact snapshots of private imported meshes. Initial loading advances on main;
## deferred private workers retain the complete synchronous implementation.
const CollisionGeometry=preload("res://scripts/world3d/model_collision_requirements.gd")
static func begin(scene:Node,faces_required:bool,geometry_mode:int=CollisionGeometry.ALL)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.static_mesh_cpu_preparation.begin") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var nodes:Array[Node]=[scene]
	return {"nodes":nodes,"seen":{},"faces_required":faces_required,"geometry_mode":geometry_mode,"verify_indices":not preload("res://scripts/world3d/runtime_package_policy.gd").trusted(),"profile":{"error":"","capture_us":0,"face_us":0,"capture_bytes":0,"face_bytes":0,"captured_meshes":0,"importer_surfaces":0,"renderer_surfaces":0,"skipped_geometry_nodes":0,"index_validation_us":0,"indices_checked":0,"elapsed_us":0,"slices":0,"max_slice_us":0}}

static func capture(scene:Node,faces_required:bool,token:RefCounted=null,geometry_mode:int=CollisionGeometry.ALL)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.static_mesh_cpu_preparation.capture") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var cursor:=begin(scene,faces_required,geometry_mode)
	var batch=preload("res://scripts/world3d/mesh_readback_batch.gd")
	if batch.enabled and not Thread.is_main_thread() and DisplayServer.get_name()!="headless":
		var readback:Dictionary=batch.capture(_readback_sources(scene,token,geometry_mode),token)
		if readback.get("handled",false):
			for key:String in ["readback_wait_us","readback_main_us","readback_meshes"]:cursor.profile[key]=readback[key]
			cursor.profile.capture_us+=readback.readback_main_us
			if readback.cancelled:
				cursor.profile.error="素材准备已取消";cursor.profile.cancelled=true;return cursor.profile
	advance(cursor,0,token)
	return cursor.profile

static func _readback_sources(scene:Node,token:RefCounted,geometry_mode:int)->Array:
	var nodes:Array[Node]=[scene];var seen:Dictionary={};var meshes:Array=[]
	while not nodes.is_empty():
		if token!=null and token.is_cancelled():return []
		var node:Node=nodes.pop_back();nodes.append_array(node.get_children())
		if not node is MeshInstance3D or not node.mesh is ArrayMesh or node.skin!=null:continue
		if not node.has_meta("ground_batch_record") and not CollisionGeometry.needs_geometry(node.get_meta("extras",{}),geometry_mode):continue
		var mesh:ArrayMesh=node.mesh;var id:int=mesh.get_instance_id()
		if seen.has(id) or mesh.has_meta("ground_cpu_cache") or mesh.get_blend_shape_count()!=0 or _has_importer_arrays(mesh) or preload("res://scripts/world3d/native_mesh_cpu_hint.gd").of(mesh)!=null:continue
		seen[id]=true
		var triangles:=true
		for slot:int in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(slot)!=Mesh.PRIMITIVE_TRIANGLES:triangles=false;break
		if triangles and preload("res://scripts/world3d/mesh_readback_batch.gd").accepts(mesh):meshes.append(mesh)
	return meshes

static func _has_importer_arrays(mesh:ArrayMesh)->bool:
	var hint:Resource=preload("res://scripts/world3d/importer_lod_hint.gd").of(mesh)
	return hint!=null and hint.has_arrays(mesh)

static func _capture(mesh:ArrayMesh,profile:Dictionary)->Mesh:
	var native_hint:Resource=preload("res://scripts/world3d/native_mesh_cpu_hint.gd").of(mesh) if not mesh.has_meta("ground_cpu_cache") else null
	if native_hint!=null:
		var native_cpu:Mesh=native_hint.take_cpu(mesh)
		if native_cpu!=null:
			profile.native_surfaces=int(profile.get("native_surfaces",0))+mesh.get_surface_count();return native_cpu
	var hint:Resource=preload("res://scripts/world3d/importer_lod_hint.gd").of(mesh)
	var cpu:Mesh=hint.take_cpu(mesh) if hint!=null and not mesh.has_meta("ground_cpu_cache") else null
	if cpu!=null:
		profile.importer_surfaces+=mesh.get_surface_count();return cpu
	if not mesh.has_meta("ground_cpu_cache"):profile.renderer_surfaces+=mesh.get_surface_count()
	return preload("res://scripts/world3d/ground_cpu_mesh.gd").capture(mesh)

static func _finish_slice(cursor:Dictionary,started:int)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.static_mesh_cpu_preparation._finish_slice") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var elapsed:=Time.get_ticks_usec()-started
	cursor.profile.elapsed_us+=elapsed;cursor.profile.slices+=1
	cursor.profile.max_slice_us=maxi(int(cursor.profile.max_slice_us),elapsed)
	return cursor.nodes.is_empty() or not cursor.profile.error.is_empty()

static func advance(cursor:Dictionary,budget_usec:int,token:RefCounted=null)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.static_mesh_cpu_preparation.advance") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var nodes:Array[Node]=cursor.nodes;var seen:Dictionary=cursor.seen;var profile:Dictionary=cursor.profile
	var faces_required:bool=cursor.faces_required;var geometry_mode:int=cursor.geometry_mode
	var visited:=0
	var started:=Time.get_ticks_usec()
	while not nodes.is_empty() and (visited==0 or budget_usec<=0 or Time.get_ticks_usec()-started<budget_usec):
		if token!=null and token.is_cancelled():
			profile.error="素材准备已取消";profile.cancelled=true;return _finish_slice(cursor,started)
		var candidate:Variant=nodes.pop_back();visited+=1
		if not is_instance_valid(candidate):profile.error="素材节点已释放";return _finish_slice(cursor,started)
		var node:Node=candidate
		nodes.append_array(node.get_children())
		if not node is MeshInstance3D or not node.mesh is ArrayMesh or node.skin!=null:continue
		# Filter before the shared-mesh seen set: any colliding use still wins,
		# regardless of traversal order. Distance LOD never suppresses a solid.
		if not node.has_meta("ground_batch_record") and not CollisionGeometry.needs_geometry(node.get_meta("extras",{}),geometry_mode):
			profile.skipped_geometry_nodes+=1;continue
		var mesh:ArrayMesh=node.mesh
		if seen.has(mesh.get_instance_id()):continue
		seen[mesh.get_instance_id()]=true
		if mesh.get_blend_shape_count()!=0:continue
		var triangles:=true
		for slot in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(slot)!=Mesh.PRIMITIVE_TRIANGLES:triangles=false;break
		if not triangles:continue
		var began:=Time.get_ticks_usec()
		var cpu:Mesh=_capture(mesh,profile)
		profile.capture_us+=Time.get_ticks_usec()-began;profile.captured_meshes+=1
		for arrays:Array in cpu.surfaces:
			for channel:Variant in arrays:
				if channel!=null:profile.capture_bytes+=packed_payload_bytes(channel)
		if not faces_required:continue
		# Authored packages have already passed the importer. Keep the constant
		# surface shape check; scanning every index again is diagnostic-only.
		began=Time.get_ticks_usec()
		for arrays:Array in cpu.surfaces:
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices:Variant=arrays[Mesh.ARRAY_INDEX]
			var count:int=indices.size() if indices!=null and not indices.is_empty() else vertices.size()
			if count%3!=0:profile.error="后台素材三角面记录不完整";return _finish_slice(cursor,started)
			if cursor.verify_indices and indices!=null:
				profile.indices_checked+=indices.size()
				for index:int in indices:
					if index<0 or index>=vertices.size():profile.error="后台素材三角面索引越界";return _finish_slice(cursor,started)
		profile.index_validation_us+=Time.get_ticks_usec()-began
		if token!=null and token.is_cancelled():
			profile.error="素材准备已取消";profile.cancelled=true;return _finish_slice(cursor,started)
		began=Time.get_ticks_usec()
		var faces:PackedVector3Array=cpu.collision_faces()
		profile.face_us+=Time.get_ticks_usec()-began;profile.face_bytes+=faces.size()*12
	return _finish_slice(cursor,started)

static func packed_payload_bytes(value:Variant)->int:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.static_mesh_cpu_preparation.packed_payload_bytes") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Packed buffer payload only, excluding Resource/container overhead. No extra
	# to_byte_array copies just to collect diagnostics (standard single precision).
	match typeof(value):
		TYPE_PACKED_BYTE_ARRAY:return value.size()
		TYPE_PACKED_INT32_ARRAY,TYPE_PACKED_FLOAT32_ARRAY:return value.size()*4
		TYPE_PACKED_INT64_ARRAY,TYPE_PACKED_FLOAT64_ARRAY,TYPE_PACKED_VECTOR2_ARRAY:return value.size()*8
		TYPE_PACKED_VECTOR3_ARRAY:return value.size()*12
		TYPE_PACKED_VECTOR4_ARRAY,TYPE_PACKED_COLOR_ARRAY:return value.size()*16
	return 0
