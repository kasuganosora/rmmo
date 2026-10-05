extends RefCounted
## Blender modules are deformed inside the planner's existing exact footprints.
## Detail stays in mesh surfaces, never separate editor objects or collision bodies.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
const MODULES=["wall","parapet","battlement","gate_lintel","door","round_tower","corner_tower","joint","hinge","hinge_mount","embrasure","tower_stair"]
static var kits: Dictionary={}
static var cache: Dictionary={}
static var cache_sizes: Dictionary={}
static var cache_bytes:=0
const CACHE_BYTES:=32*1024*1024
var record: Dictionary
var size_: Vector3
var spans: Array=[]
var total:=0.0
func kit(path: String) -> Dictionary:
	if kits.has(path): return kits[path]
	if not Paths.allowed(path) or not FileAccess.file_exists(path): return {}
	var root: Node3D=preload("res://scripts/world_editor/asset_library.gd").instantiate_preview(path)
	if root==null: return {}
	var result:={}
	for node in Paint.meshes(root): result[str(node.name)]={"mesh":node.mesh,"transform":node.transform}
	root.free()
	for name_ in MODULES:
		if name_=="tower_stair": continue
		if not result.has(name_): return {}
	if kits.size()>=4: kits.erase(kits.keys()[0])
	kits[path]=result; return result
func point(p: Vector3) -> Vector3:
	if spans.is_empty(): return p*size_
	var distance: float=clampf(p.x+.5,0,1)*total
	var span: Dictionary=spans[-1]
	for candidate in spans:
		if distance<=candidate.end: span=candidate; break
	var t:=clampf((distance-span.start)/(span.end-span.start),0,1)
	var outside: Vector2=span.poly[0].lerp(span.poly[1],t)
	var inside: Vector2=span.poly[3].lerp(span.poly[2],t)
	var q:=outside.lerp(inside,p.z+.5)
	return Vector3(q.x,p.y*size_.y,q.y)
func build(r: Dictionary) -> ArrayMesh:
	record=r; size_=Data.vec(r.size); spans=[]; total=0
	var key:=Data.token([r.get("channel_mesh",{}),r.size,r.fortification_art,r.fortification_materials])
	if cache.has(key): return cache[key]
	if r.fortification_art.module=="tower_stair": return remember(key,preload("res://scripts/world3d/fortification_stair_mesh.gd").build(r))
	var source:=kit(r.fortification_art.asset_path)
	if source.is_empty(): return null
	var name_: String=r.fortification_art.module
	if r.has("channel_mesh") and name_!="round_tower":
		for poly in r.channel_mesh.polygons:
			if poly.size()!=4: return null
			var q: Array=poly.map(func(p):return Vector2(p[0]*size_.x,p[1]*size_.z))
			var length_: float=((q[0]+q[3])*.5).distance_to((q[1]+q[2])*.5)
			spans.append({"poly":q,"start":total,"end":total+length_}); total+=length_
	var length_: float=total if total>0 else size_.x
	var repeats: int=maxi(1,ceili(length_/4)) if name_=="wall" else 1
	var piece: Dictionary=source[name_]; var mesh: Mesh=piece.mesh
	var importer:=ImporterMesh.new()
	for slot in mesh.get_surface_count():
		var role: String=mesh.surface_get_material(slot).resource_name
		if not r.fortification_materials.has(role): return null
		var material: Material=Paint.make_material(r.fortification_materials[role])
		var st:=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var a: Array=mesh.surface_get_arrays(slot); var verts: PackedVector3Array=a[Mesh.ARRAY_VERTEX]; var norms: PackedVector3Array=a[Mesh.ARRAY_NORMAL]; var indices: PackedInt32Array=a[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in verts.size(): indices.append(i)
		var tile: Array=r.fortification_materials[role].get("tile_size",[2,2])
		for repeat in repeats:
			for i in indices:
				var p: Vector3=piece.transform*verts[i]; p.x=clampf((p.x+.5+repeat)/repeats-.5,-.5,.5)
				var normal: Vector3=piece.transform.basis*norms[i]; normal.x*=repeats
				var v:=point(p)
				if spans.is_empty(): normal=(normal/size_).normalized()
				else:
					var x0:=point(Vector3(maxf(-.5,p.x-.0001),p.y,p.z)); var x1:=point(Vector3(minf(.5,p.x+.0001),p.y,p.z))
					var dx: Vector3=(x1-x0)/(.0001 if absf(p.x)>.49995 else .0002)
					var dz:=point(Vector3(p.x,p.y,.5))-point(Vector3(p.x,p.y,-.5))
					normal=(Basis(dx,Vector3(0,size_.y,0),dz).inverse().transposed()*normal).normalized()
				var uv: Vector2
				if absf(normal.y)>.7: uv=Vector2(v.x,v.z)
				elif absf(norms[i].z)>.6: uv=Vector2((p.x+.5)*length_,v.y)
				else: uv=Vector2(v.z,v.y)
				st.set_normal(normal); st.set_uv(uv/Vector2(tile[0],tile[1])); st.add_vertex(v)
		st.generate_tangents(); st.index(); importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,st.commit_to_arrays(),[],{},material,role)
	importer.generate_lods(60,25,[])
	var arrays: Array=[]
	for slot in importer.get_surface_count(): arrays.append(importer.get_surface_arrays(slot))
	var result:=importer.get_mesh()
	preload("res://scripts/world3d/ground_cpu_mesh.gd").remember(result,arrays)
	return remember(key,result)
func remember(key: String,result: ArrayMesh) -> ArrayMesh:
	var bytes:=0
	for i in result.get_surface_count(): bytes+=result.surface_get_array_len(i)*48+result.surface_get_array_index_len(i)*8
	if bytes<=CACHE_BYTES:
		while not cache.is_empty() and (cache.size()>=1024 or cache_bytes+bytes>CACHE_BYTES):
			var oldest: String=cache.keys()[0]; cache_bytes-=cache_sizes[oldest]; cache_sizes.erase(oldest); cache.erase(oldest)
		cache[key]=result; cache_sizes[key]=bytes; cache_bytes+=bytes
	return result
