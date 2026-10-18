extends Mesh
## Authoring/collision geometry without a RenderingServer mesh allocation.
var surfaces: Array = []
var lods: Array = [] # Per-surface distance/error -> index buffer; collision uses base surfaces.
var materials: Array[Material] = []
var bounds := AABB()
var box_size := Vector3.ZERO
var source_reference: WeakRef
var _collision_faces:=PackedVector3Array()
static var _unit_box_arrays: Array=[]

static func _bind_source(source:Mesh,owner:Mesh)->WeakRef:
	# Projections share this WeakRef, including its generation proof. Comparing
	# material slots alone cannot detect an editor changing the source geometry.
	var reference:WeakRef=weakref(source)
	reference.set_meta("cpu_owner",weakref(owner))
	source.set_meta("ground_cpu_cache",owner)
	source.changed.connect(invalidate.bind(reference),CONNECT_ONE_SHOT)
	return reference

static func plain_box(source:Mesh)->bool:
	return source is BoxMesh and not source.flip_faces and not source.add_uv2 and source.subdivide_width==0 and source.subdivide_height==0 and source.subdivide_depth==0 and source.size.x>0 and source.size.y>0 and source.size.z>0

static func primitive_arrays(source: Mesh, slot: int) -> Array:
	# PrimitiveMesh.surface_get_arrays also reads through RenderingServer.
	# An ordinary box has invariant topology/UVs; scale one canonical CPU copy.
	if plain_box(source):
		if _unit_box_arrays.is_empty():
			var unit:=BoxMesh.new(); unit.size=Vector3.ONE
			_unit_box_arrays=unit.surface_get_arrays(0)
		var arrays: Array=_unit_box_arrays.duplicate()
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
		for i in vertices.size(): vertices[i]*=source.size
		arrays[Mesh.ARRAY_VERTEX]=vertices
		return arrays
	return source.surface_get_arrays(slot)

static func remember(source: Mesh, arrays: Array, surface_lods:Array=[]) -> Mesh:
	# Procedural meshers already own these CPU arrays. Retain them at upload time
	# instead of synchronously downloading thousands of GPU buffers on first use.
	var result=load("res://scripts/world3d/ground_cpu_mesh.gd").new()
	result.bounds=source.get_aabb(); result.surfaces=arrays;result.lods=surface_lods
	for slot in source.get_surface_count(): result.materials.append(source.surface_get_material(slot))
	result.source_reference=_bind_source(source,result)
	return result

func geometry_key() -> String:
	if not has_meta("static_batch_geometry_signature"):
		set_meta("static_batch_geometry_signature",geometry_signature(surfaces,lods))
	return get_meta("static_batch_geometry_signature")

static func geometry_signature(arrays:Array,surface_lods:Array=[])->String:
	# Preserve old cache identities for geometry without any LOD. A different
	# distance/index table must not alias the same base geometry's GPU resource.
	var value:Variant=arrays
	if surface_lods.any(func(levels):return not levels.is_empty()):value=["mesh-lods-v1",arrays,surface_lods]
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func collision_faces() -> PackedVector3Array:
	if _collision_faces.is_empty():
		# Mesh.get_faces() builds a TriangleMesh (including a BVH) first. Physics
		# and Recast only need the existing triangle soup, not that extra tree.
		var count:=0
		for arrays:Array in surfaces:
			var indices:Variant=arrays[Mesh.ARRAY_INDEX]
			count+=indices.size() if indices!=null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
		_collision_faces.resize(count)
		var offset:=0
		for arrays:Array in surfaces:
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices:Variant=arrays[Mesh.ARRAY_INDEX]
			if indices!=null and not indices.is_empty():
				for index in indices:
					_collision_faces[offset]=vertices[index];offset+=1
			else:
				for vertex in vertices:
					_collision_faces[offset]=vertex;offset+=1
	return _collision_faces

static func capture(source: Mesh) -> Mesh:
	if source.get_script() == load("res://scripts/world3d/ground_cpu_mesh.gd"): return source
	if source.has_meta("ground_cpu_cache"): return source.get_meta("ground_cpu_cache")
	var traced:bool=source is ArrayMesh and preload("res://scripts/world3d/load_trace.gd").enabled
	var began:=Time.get_ticks_usec() if traced else 0
	var result = load("res://scripts/world3d/ground_cpu_mesh.gd").new()
	result.bounds = source.get_aabb()
	if plain_box(source): result.box_size = source.size
	for slot in source.get_surface_count():
		result.surfaces.append(primitive_arrays(source,slot))
		result.materials.append(source.surface_get_material(slot))
		if source is ArrayMesh:result.lods.append(capture_lods(source,slot))
	result.source_reference=_bind_source(source,result)
	if traced:preload("res://scripts/world3d/load_trace.gd").elapsed("mesh.renderer_array_capture",began,{"surfaces":result.surfaces.size()})
	return result

static func from_surfaces(arrays:Array,slot_materials:Array)->Mesh:
	# Immutable procedural preparation already owns its exact CPU buffers.
	# Building an ArrayMesh here only uploads buffers that indexing discards.
	var result=load("res://scripts/world3d/ground_cpu_mesh.gd").new()
	result.surfaces=arrays;result.materials.assign(slot_materials)
	var first:=true
	var bounds:=AABB()
	for surface:Array in arrays:
		for point:Vector3 in surface[Mesh.ARRAY_VERTEX]:
			bounds=AABB(point,Vector3.ZERO) if first else bounds.expand(point)
			first=false
	result.bounds=bounds
	return result

static func invalidate(reference: WeakRef) -> void:
	var source: Mesh=reference.get_ref()
	if source != null and source.has_meta("ground_cpu_cache"): source.remove_meta("ground_cpu_cache")

static func capture_lods(source:ArrayMesh,slot:int)->Dictionary:
	# Imported native ArrayMeshes lack the procedural CPU owner from remember().
	# Preserve index LODs across source retirement and per-instance material forks.
	var surface:Dictionary=RenderingServer.mesh_get_surface(source.get_rid(),slot)
	var result:Dictionary={}
	if surface.get("lods",[]).is_empty():return result
	var stride:int=RenderingServer.mesh_surface_get_format_index_stride(surface.format,surface.vertex_count)
	for row:Dictionary in surface.lods:
		var bytes:PackedByteArray=row.index_data;var indices:=PackedInt32Array();indices.resize(bytes.size()/stride)
		for i in indices.size():indices[i]=bytes.decode_u16(i*2) if stride==2 else bytes.decode_u32(i*4)
		result[float(row.edge_length)]=indices
	return result

func restore() -> Mesh:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_cpu_mesh.restore") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var original: Mesh=source_reference.get_ref() if source_reference!=null else null
	var owner:WeakRef=source_reference.get_meta("cpu_owner") if source_reference!=null and source_reference.has_meta("cpu_owner") else null
	if original!=null and (owner==null or owner.get_ref()==null or not original.has_meta("ground_cpu_cache") or original.get_meta("ground_cpu_cache")!=owner.get_ref()):original=null
	if original!=null:
		var compatible:=original.get_surface_count()==materials.size()
		for slot in materials.size():
			if not compatible or original.surface_get_material(slot)!=materials[slot]: compatible=false; break
		if compatible: return original
	if box_size != Vector3.ZERO:
		var box := BoxMesh.new(); box.size = box_size; box.material = materials[0]
		source_reference=_bind_source(box,self)
		return box
	var result := ArrayMesh.new()
	for slot in surfaces.size():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[slot],[],_surface_get_lods(slot))
		result.surface_set_material(slot, materials[slot])
	var cached: Mesh=remember(result,surfaces,lods)
	# Repeated instances share this CPU object after loading. Remember the first
	# restored GPU mesh weakly so each instance does not upload the same buffers.
	source_reference=cached.source_reference
	cached._collision_faces=_collision_faces
	if has_meta("static_batch_geometry_signature"): cached.set_meta("static_batch_geometry_signature",geometry_key())
	return result

func _get_aabb() -> AABB: return bounds
func _get_surface_count() -> int: return surfaces.size()
func _get_blend_shape_count() -> int: return 0
func _surface_get_arrays(index: int) -> Array: return surfaces[index]
func _surface_get_array_len(index: int) -> int: return surfaces[index][Mesh.ARRAY_VERTEX].size()
func _surface_get_array_index_len(index: int) -> int: return surfaces[index][Mesh.ARRAY_INDEX].size() if surfaces[index][Mesh.ARRAY_INDEX] != null else 0
func _surface_get_primitive_type(_index: int) -> int: return Mesh.PRIMITIVE_TRIANGLES
func _surface_get_format(index: int) -> int:
	var format := 0
	for i in Mesh.ARRAY_MAX:
		if surfaces[index][i] != null and surfaces[index][i].size() > 0: format |= 1 << i
	return format
func _surface_get_material(index: int) -> Material: return materials[index]
func _surface_set_material(index: int, material: Material) -> void: materials[index] = material
func _surface_get_lods(index: int) -> Dictionary: return lods[index] if index<lods.size() else {}
func _surface_get_blend_shape_arrays(_index: int) -> Array[Array]: return []
