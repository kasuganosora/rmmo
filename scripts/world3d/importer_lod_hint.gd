extends Resource
## Runtime-only data stamped when we create a private static importer's mesh.
## No importer/GLTFState ownership, and no exported state survives serialization.
const META:=&"_rmmo_importer_lod_hint"
var source_reference:WeakRef
var tables:Array=[]
func matches(source:ArrayMesh,slot:int)->bool:
	return source_reference!=null and source_reference.get_ref()==source and slot>=0 and slot<tables.size() and tables[slot] is Dictionary and tables.size()==source.get_surface_count()
func invalidate()->void:
	var source:Mesh=source_reference.get_ref() if source_reference!=null else null
	if source!=null and source.has_meta(META) and source.get_meta(META)==self:source.remove_meta(META)
	source_reference=null;tables=[]
static func create_mesh(importer:ImporterMesh)->ArrayMesh:
	var source:=importer.get_mesh()
	if source==null or source.resource_local_to_scene:return source
	var hint:=new();hint.source_reference=weakref(source)
	for slot:int in importer.get_surface_count():
		var lods:Dictionary={}
		for lod:int in importer.get_surface_lod_count(slot):
			lods[importer.get_surface_lod_size(slot,lod)]=importer.get_surface_lod_indices(slot,lod)
		hint.tables.append(lods)
	source.set_meta(META,hint)
	source.changed.connect(hint.invalidate,CONNECT_ONE_SHOT)
	return source
static func prepare(state:GLTFState,nodes:Array[GLTFNode],meshes:Array[GLTFMesh])->void:
	# Early cache creation is safe only for the same private static route used by
	# model preparation. Skeleton/morph processing retains the original path.
	if not state.skins.is_empty() or not state.animations.is_empty():return
	var used:Dictionary={}
	for node:GLTFNode in nodes:
		if node.skin>=0:return
		if node.mesh>=0:used[node.mesh]=true
	var began:=Time.get_ticks_usec();var surfaces:=0
	for id:int in used:
		var importer:ImporterMesh=meshes[id].mesh
		if importer==null or importer.get_surface_count()==0 or importer.get_blend_shape_count()!=0:continue
		# Populate the exact cache the built-in converter subsequently consumes.
		# Attach invalidation before generate_scene/extensions can change it.
		create_mesh(importer);surfaces+=importer.get_surface_count()
	preload("res://scripts/world3d/load_trace.gd").elapsed("model.importer_lod_prepare",began,{"meshes":used.size(),"surfaces":surfaces})
