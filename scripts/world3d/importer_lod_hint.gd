extends Resource
## Runtime-only data stamped when we create a private static importer's mesh.
## No importer/GLTFState ownership, and no exported state survives serialization.
const META:=&"_rmmo_importer_lod_hint"
const DECODE_METHOD:=&"mesh_surface_arrays_from_arrays"
static var renderer_arrays_enabled:=true
var source_reference:WeakRef
var tables:Array=[]
# Arrays exactly as the renderer decodes this mesh's uploaded buffers (same
# encoder and decoder, no GPU download). Handed over once to the CPU capture.
var surfaces:Array=[]
func matches(source:ArrayMesh,slot:int)->bool:
	return source_reference!=null and source_reference.get_ref()==source and slot>=0 and slot<tables.size() and tables[slot] is Dictionary and tables.size()==source.get_surface_count()
static func of(source:Mesh)->Resource:
	if not preload("res://scripts/world3d/ground_cpu_mesh.gd").importer_lod_hints_enabled or not source is ArrayMesh or not source.has_meta(META):return null
	var hint:Variant=source.get_meta(META)
	return hint if hint is Resource and hint.get_script()==preload("res://scripts/world3d/importer_lod_hint.gd") else null
func has_arrays(source:ArrayMesh)->bool:
	if not matches(source,0) or surfaces.size()!=source.get_surface_count():return false
	return surfaces.all(func(arrays:Array):return not arrays.is_empty())
## Exact CPU mesh for the source, built without a renderer readback. The
## arrays are handed over once; later captures use the renderer path.
func take_cpu(source:ArrayMesh)->Mesh:
	if not has_arrays(source):return null
	var lods:Array=[]
	for table:Dictionary in tables:lods.append(table.duplicate())
	var arrays:Array=surfaces;surfaces=[]
	return preload("res://scripts/world3d/ground_cpu_mesh.gd").remember(source,arrays,lods)
func invalidate()->void:
	var source:Mesh=source_reference.get_ref() if source_reference!=null else null
	if source!=null and source.has_meta(META) and source.get_meta(META)==self:source.remove_meta(META)
	source_reference=null;tables=[];surfaces=[]
static func create_mesh(importer:ImporterMesh,profile:Dictionary={})->ArrayMesh:
	var source:=importer.get_mesh()
	if source==null or source.resource_local_to_scene:return source
	var hint:=new();hint.source_reference=weakref(source)
	var decode:=renderer_arrays_enabled and RenderingServer.has_method(DECODE_METHOD)
	for slot:int in importer.get_surface_count():
		var lods:Dictionary={}
		for lod:int in importer.get_surface_lod_count(slot):
			lods[importer.get_surface_lod_size(slot,lod)]=importer.get_surface_lod_indices(slot,lod)
		hint.tables.append(lods)
		var arrays:Array=[]
		if decode and importer.get_surface_primitive_type(slot)==Mesh.PRIMITIVE_TRIANGLES:
			var began:=Time.get_ticks_usec()
			arrays=RenderingServer.call(DECODE_METHOD,Mesh.PRIMITIVE_TRIANGLES,importer.get_surface_arrays(slot),importer.get_surface_format(slot))
			profile.decode_us=int(profile.get("decode_us",0))+Time.get_ticks_usec()-began
			profile.decoded_surfaces=int(profile.get("decoded_surfaces",0))+1
		hint.surfaces.append(arrays)
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
	var began:=Time.get_ticks_usec();var surfaces:=0;var profile:Dictionary={}
	for id:int in used:
		var importer:ImporterMesh=meshes[id].mesh
		if importer==null or importer.get_surface_count()==0 or importer.get_blend_shape_count()!=0:continue
		# Populate the exact cache the built-in converter subsequently consumes.
		# Attach invalidation before generate_scene/extensions can change it.
		create_mesh(importer,profile);surfaces+=importer.get_surface_count()
	preload("res://scripts/world3d/load_trace.gd").elapsed("model.importer_lod_prepare",began,{"meshes":used.size(),"surfaces":surfaces,"decode_us":int(profile.get("decode_us",0)),"decoded_surfaces":int(profile.get("decoded_surfaces",0))})
