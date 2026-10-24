extends SceneTree
const Geometry=preload("res://scripts/world3d/ground_batch_geometry.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
static func compact(arrays:Array)->Array:
	return Geometry.compact_terrain_sides(arrays)
static func legacy(arrays:Array,record:Dictionary)->Array:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	append_surface(st,arrays,Transform3D.IDENTITY,0,false,record,1)
	st.index();return st.commit_to_arrays()
func record_for(n:int)->Dictionary:
	var heights:Array=[];var holes:Array=[]
	for z:int in n+1:
		for x:int in n+1:heights.append(sin(float(x)*.3)*cos(float(z)*.2))
	holes.resize(n*n);holes.fill(false)
	return {"kind":"box","size":[32.,1.,32.],"terrain_mesh":{"version":1,"columns":n,"rows":n,"floor":-8.,"heights":heights,"holes":holes}}
func run()->void:
	var timings:Array=[]
	for n:int in [4,16,32,64]:
		var record:=record_for(n);var arrays:Array=Terrain.arrays(record)[1]
		var saved:=var_to_bytes(arrays);var expected:=legacy(arrays,record)
		var actual:=compact(arrays)
		check(var_to_bytes(actual)==var_to_bytes(expected),"all channels/index order match old terrain submission n=%d"%n)
		check(var_to_bytes(arrays)==saved,"source geometry untouched n=%d"%n)
		var old_us:=0;var new_us:=0
		for trial:int in 6:
			var began:=Time.get_ticks_usec();legacy(arrays,record);old_us+=Time.get_ticks_usec()-began
			began=Time.get_ticks_usec();compact(arrays);new_us+=Time.get_ticks_usec()-began
		timings.append({"n":n,"old_us":old_us,"new_us":new_us,"source_vertices":arrays[Mesh.ARRAY_VERTEX].size(),"output_vertices":actual[Mesh.ARRAY_VERTEX].size()})
		# Exercise optional channels, nonunit attributes and non-indexed input.
		var uv2:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV].duplicate();arrays[Mesh.ARRAY_TEX_UV2]=uv2
		var colors:=PackedColorArray();colors.resize(arrays[Mesh.ARRAY_VERTEX].size());colors.fill(Color(.2,.3,.4,1));arrays[Mesh.ARRAY_COLOR]=colors
		var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL].duplicate()
		for i:int in normals.size():normals[i]*=2.
		arrays[Mesh.ARRAY_NORMAL]=normals
		var st:=SurfaceTool.new();st.create_from_arrays(arrays);st.deindex();arrays=st.commit_to_arrays()
		check(var_to_bytes(compact(arrays))==var_to_bytes(legacy(arrays,record)),"UV2/color/nonunit/nonindexed match n=%d"%n)
	print("TERRAIN_BATCH_SUBMISSION ",JSON.stringify({"timings":timings,"failures":failures}));quit(1 if failures else 0)

# Frozen pre-optimization reference, retained only as the regression oracle.
static func append_surface(st: SurfaceTool, arrays: Array, transform: Transform3D, layer: int, layered: bool, record: Dictionary, slot: int) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batch_geometry.append_surface") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(vertices.size())
		for i in vertices.size(): indices[i] = i
	# Only the sealed, flat underside can be reduced without changing silhouettes,
	# painted faces, holes or the top heightfield. Source arrays stay untouched.
	var compact: bool = slot == 1 and record.has("terrain_mesh") and not record.terrain_mesh.holes.has(true) and not record.has("surface_paint")
	var bottom_corners := {}
	var low := Vector3(INF, INF, INF); var high := Vector3(-INF, -INF, -INF)
	for face in range(0, indices.size(), 3):
		var a := indices[face]; var b := indices[face+1]; var c := indices[face+2]
		if compact and normals[a].y < -.999 and normals[b].y < -.999 and normals[c].y < -.999:
			for at in [a,b,c]:
				low = low.min(vertices[at]); high = high.max(vertices[at]); bottom_corners[Vector2(vertices[at].x,vertices[at].z)] = at
			continue
		for at in [a,b,c]: emit_vertex(st, arrays, at, transform, layer, layered)
	if not bottom_corners.is_empty():
		for p in [Vector2(low.x,low.z),Vector2(high.x,high.z),Vector2(high.x,low.z),Vector2(low.x,low.z),Vector2(low.x,high.z),Vector2(high.x,high.z)]:
			emit_vertex(st, arrays, bottom_corners[p], transform, layer, layered)

static func emit_vertex(st: SurfaceTool, arrays: Array, at: int, transform: Transform3D, layer: int, layered: bool) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.ground_batch_geometry.emit_vertex") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	st.set_normal((transform.basis * arrays[Mesh.ARRAY_NORMAL][at]).normalized())
	if arrays[Mesh.ARRAY_TEX_UV] != null: st.set_uv(arrays[Mesh.ARRAY_TEX_UV][at])
	if arrays[Mesh.ARRAY_TEX_UV2] != null: st.set_uv2(arrays[Mesh.ARRAY_TEX_UV2][at])
	if arrays[Mesh.ARRAY_COLOR] != null: st.set_color(arrays[Mesh.ARRAY_COLOR][at])
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var t: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]; var v := transform.basis * Vector3(t[at*4], t[at*4+1], t[at*4+2])
		st.set_tangent(Plane(v.normalized(), t[at*4+3]))
	if layered: st.set_custom(0, Color(float(layer),0,0,0))
	st.add_vertex(transform * arrays[Mesh.ARRAY_VERTEX][at])
