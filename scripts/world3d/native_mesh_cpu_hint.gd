extends Resource
## A private native read can hand its exact serialized surface bytes to the
## existing CPU mesh consumer. The engine checks geometry revision before take;
## no scene instantiation, renderer download or second file read is needed.
const META:=&"_rmmo_native_cpu_hint"
var source:WeakRef
var capture:RefCounted

static func attach(packed:PackedScene,context:RefCounted)->int:
	var scene:=packed.get_state();var seen:Dictionary={};var count:=0
	for node:int in scene.get_node_count():
		if scene.get_node_type(node)!=&"MeshInstance3D":continue
		for property:int in scene.get_node_property_count(node):
			if scene.get_node_property_name(node,property)!=&"mesh":continue
			var mesh:Variant=scene.get_node_property_value(node,property)
			if not mesh is ArrayMesh or mesh.resource_local_to_scene or mesh.get_blend_shape_count()!=0:break
			var id:int=mesh.get_instance_id()
			if seen.has(id):break
			seen[id]=true
			var hint:=new();hint.source=weakref(mesh);hint.capture=context
			mesh.set_meta(META,hint);count+=1
			break
	return count

static func of(mesh:Mesh)->Resource:
	if not mesh is ArrayMesh or not mesh.has_meta(META):return null
	var hint:Variant=mesh.get_meta(META)
	return hint if hint is Resource and hint.get_script()==load("res://scripts/world3d/native_mesh_cpu_hint.gd") and hint.source!=null and hint.source.get_ref()==mesh and hint.capture!=null else null

func take_cpu(mesh:ArrayMesh)->Mesh:
	if source==null or source.get_ref()!=mesh or capture==null:return null
	# One consumer takes a surface generation. Mutated or unsupported meshes
	# fall back to the existing renderer path, never to stale saved arrays.
	var result:Dictionary=capture.take(mesh)
	if mesh.get_meta(META,null)==self:mesh.remove_meta(META)
	capture=null;source=null
	if result.get("status")!="ok":return null
	return load("res://scripts/world3d/ground_cpu_mesh.gd").remember(mesh,result.arrays,result.lods)
