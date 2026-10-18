extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Geometry=preload("res://scripts/world3d/ground_batch_geometry.gd")
const Probe=preload("res://scripts/world3d/runtime_probe_controls.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	var record:Dictionary={"uuid":"terrain","kind":"box","position":[0,0,0],"rotation":[0,0,0],"size":[8,2,8],"surface_id":"ground","collision":"walk","terrain_mesh":{"version":1,"floor":-.5,"columns":2,"rows":2,"heights":[0.,.1,.2,.1,.2,.3,.2,.3,.4],"holes":[false,false,false,false]},"terrain_saturation":.7}
	var document:=Doc.new();document.load_immutable_records=true
	var original:MeshInstance3D=document._mesh(record)
	var before:Mesh=Cpu.capture(original.mesh)
	Probe.discard_map_textures=true;Probe.enable_white_materials()
	var white_document:=Doc.new();white_document.load_immutable_records=true
	var white:MeshInstance3D=white_document._mesh(record);var after:Mesh=Cpu.capture(white.mesh)
	check(before.surfaces==after.surfaces and before.get_aabb()==after.get_aabb() and before.get_faces()==after.get_faces(),"white diagnostic preserves every vertex channel, exact bounds and collision faces")
	check(white.material_override==Probe.white_material() and not white.material_override is ShaderMaterial,"white rendering excludes terrain/custom shader construction")
	var keys:Array=[]
	for material:Material in after.materials:keys.append(Geometry.material_key(material))
	# Region data is deliberately present with a plain override: it has no
	# material mask image, and plain batching must never request that metadata.
	var source_record:Dictionary=record.duplicate(true);source_record.terrain_regions={"regions":[]}
	var materials:Array=[]
	for slot:int in after.get_surface_count():materials.append(Probe.white_material())
	var built:Dictionary=Geometry.build([{"record":source_record,"transform":Transform3D.IDENTITY,"surfaces":after.surfaces,"materials":materials,"keys":keys}],Vector3.ZERO,true)
	check(not built.is_empty() and built.images.is_empty() and built.masks.is_empty(),"plain terrain batch prepares no unused height or mask textures and needs no shader metadata")
	var uploaded:Dictionary=Geometry.upload(built)
	check(uploaded.has("mesh") and uploaded.mesh.get_rid().is_valid(),"plain terrain batch still publishes a real GPU mesh")
	check(uploaded.source_vertices>0 and uploaded.render_vertices>0,"plain material control retains real source and rendered geometry")
	var importer:=ImporterMesh.new();var arrays:Array=BoxMesh.new().get_mesh_arrays()
	var front:=StandardMaterial3D.new();front.cull_mode=BaseMaterial3D.CULL_FRONT;front.normal_enabled=true
	var double_sided:=StandardMaterial3D.new();double_sided.cull_mode=BaseMaterial3D.CULL_DISABLED
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{.5:PackedInt32Array([0,1,2])},front,"front")
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},double_sided,"double")
	var gltf_mesh:=GLTFMesh.new();gltf_mesh.mesh=importer
	var state:=GLTFState.new();state.meshes=[gltf_mesh]
	var serialized:=var_to_bytes([importer.get_surface_arrays(0),importer.get_surface_arrays(1),importer.get_surface_lod_indices(0,0)])
	Probe.white_materials=false;Probe.prepare_gltf_materials(state)
	check(importer.get_surface_material(0)==front and not state.has_meta("probe_white_materials"),"ordinary import materials remain untouched when diagnostic is off")
	Probe.white_materials=true;Probe.prepare_gltf_materials(state)
	check(importer.get_surface_material(0)==Probe.white_material(BaseMaterial3D.CULL_FRONT) and importer.get_surface_material(1)==Probe.white_material(BaseMaterial3D.CULL_DISABLED),"importer surfaces become shared white before a render mesh exists while preserving cull modes")
	check(serialized==var_to_bytes([importer.get_surface_arrays(0),importer.get_surface_arrays(1),importer.get_surface_lod_indices(0,0)]),"early white import preserves vertex channels and exact LOD indices")
	check(state.get_meta("probe_white_materials")==[front,double_sided],"private GLTFState keeps original renderer resources on its ordinary retirement lease")
	var generated:ArrayMesh=importer.get_mesh()
	check(generated.surface_get_material(0)==Probe.white_material(BaseMaterial3D.CULL_FRONT) and generated.surface_get_material(1)==Probe.white_material(BaseMaterial3D.CULL_DISABLED),"first actual GPU mesh already contains white surface materials")
	var cpu:=Cpu.new();cpu.surfaces=[arrays];cpu.materials=[front];cpu.lods=[{.5:PackedInt32Array([0,1,2])}]
	cpu.bounds=AABB(Vector3(-1,-1,-1),Vector3(2,2,2));cpu.collision_faces()
	var replacement:Array=[Probe.white_material(BaseMaterial3D.CULL_FRONT)]
	var projected:Mesh=Probe.prepare_cpu_materials(cpu,replacement)
	check(projected!=cpu and cpu.materials==[front] and projected.materials==replacement,"white CPU projection leaves the shared source material untouched")
	check(is_same(projected.surfaces,cpu.surfaces) and is_same(projected.lods,cpu.lods) and projected.get_aabb()==cpu.get_aabb() and projected._collision_faces==cpu._collision_faces,"CPU projection preserves exact geometry, LODs, bounds and prepared collision data")
	var first_gpu:Mesh=projected.restore()
	check(first_gpu.surface_get_material(0)==replacement[0],"CPU restoration binds white on its first GPU surface instead of an unused lit variant")
	check(Probe.prepare_cpu_materials(cpu,replacement)==projected and projected.restore()==first_gpu,"repeated white instances share the same CPU projection and actual GPU mesh")
	var gpu_watch:WeakRef=weakref(first_gpu);first_gpu=null
	check(gpu_watch.get_ref()==null and Probe.prepare_cpu_materials(cpu,replacement)==projected,"retaining the diagnostic CPU projection does not retain its last GPU resource")
	Probe.white_materials=false;Probe.discard_map_textures=false
	check(Probe.prepare_cpu_materials(cpu,replacement)==cpu,"ordinary CPU materials stay unchanged when diagnostic is disabled")
	original.free();white.free()
	print("WHITE_GEOMETRY_CONTROL checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
