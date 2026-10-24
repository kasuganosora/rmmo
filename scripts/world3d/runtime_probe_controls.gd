extends RefCounted
## Diagnostic controls set by dedicated profiling tools before workers start.
## Never exposed in game/editor UI; ordinary production keeps all features.
static var discard_map_textures:=false
static var hud_enabled:=true
static var white_materials:=false
static var white_generation:=0
static var early_white_gltf_enabled:=true
static var _white:Dictionary={}
static func enable_white_materials()->void:
	# Called on main before any diagnostic workers start; workers only read it.
	for cull:int in [BaseMaterial3D.CULL_BACK,BaseMaterial3D.CULL_FRONT,BaseMaterial3D.CULL_DISABLED]:
		var material:=StandardMaterial3D.new();material.albedo_color=Color.WHITE
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.cull_mode=cull
		_white[cull]=material
	white_materials=true;white_generation+=1
static func white_material(cull:int=BaseMaterial3D.CULL_BACK)->StandardMaterial3D:
	return _white[cull]
static func prepare_cpu_materials(source:Mesh,replacements:Array)->Mesh:
	const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
	if not white_materials or not source is Cpu or source.materials==replacements:return source
	var cached:Variant=source.get_meta("probe_white_cpu_projection") if source.has_meta("probe_white_cpu_projection") else null
	if cached is Cpu and cached.materials==replacements and is_same(cached.surfaces,source.surfaces) and is_same(cached.lods,source.lods) and cached.bounds==source.bounds and cached.box_size==source.box_size:return cached
	# A white instance override is too late: restore() first binds the original
	# unused surface materials. Keep a private CPU material projection so the
	# first real GPU upload only sees the diagnostic materials too.
	var local:=Cpu.new();local.surfaces=source.surfaces;local.lods=source.lods
	local.bounds=source.bounds;local.box_size=source.box_size;local.source_reference=source.source_reference
	local.materials.assign(replacements);local._collision_faces=source._collision_faces
	if source.has_meta("static_batch_geometry_signature"):local.set_geometry_key(source.get_meta("static_batch_geometry_signature"))
	# Retain one tiny CPU projection with its immutable CPU source, preserving
	# cross-instance GPU reuse. Its GPU reference is weak; no GPU owner is added.
	source.set_meta("probe_white_cpu_projection",local)
	return local
static func configure_gltf(state:GLTFState)->void:
	if discard_map_textures:state.handle_binary_image=GLTFState.HANDLE_BINARY_DISCARD_TEXTURES

static func prepare_gltf_materials(state:GLTFState)->void:
	if not white_materials or not early_white_gltf_enabled or state.has_meta("probe_white_materials"):return
	# Replace importer materials before generate_scene builds render meshes.
	# A late instance override can still prepare unused original shader variants.
	# Keep original resources on the already main-retired GLTFState lease rather
	# than allowing a preparation worker to become their final owner.
	var originals:Array=[]
	for gltf_mesh:GLTFMesh in state.meshes:
		var mesh:ImporterMesh=gltf_mesh.mesh
		if mesh==null:continue
		for slot:int in mesh.get_surface_count():
			var material:Material=mesh.get_surface_material(slot)
			if material!=null:originals.append(material)
			mesh.set_surface_material(slot,white_material(material.cull_mode if material is BaseMaterial3D else BaseMaterial3D.CULL_BACK))
	state.set_meta("probe_white_materials",originals)

static func whiten_spec(spec:Dictionary)->void:
	const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
	var replacements:Array=[];var overrides:Array=[];var mesh:Mesh=spec.mesh
	var cpu:=mesh is Cpu;var count:int=mesh.surfaces.size() if cpu else mesh.get_surface_count()
	var global:Material=spec.get("material_override");var original:Array=spec.get("surface_overrides",[])
	var needs_override:=false
	for slot:int in count:
		var base:Material=mesh.materials[slot] if cpu else mesh.surface_get_material(slot)
		var material:Material=global
		if material==null:
			material=original[slot] if slot<original.size() and original[slot]!=null else base
		var white:Material=white_material(material.cull_mode if material is BaseMaterial3D else BaseMaterial3D.CULL_BACK)
		replacements.append(white)
		if not cpu:
			overrides.append(white if base!=white else null)
			needs_override=needs_override or base!=white
	spec.mesh=prepare_cpu_materials(mesh,replacements)
	# CPU projections already bind these materials on restore. Redundant instance
	# overrides made the white probe reconfigure the renderer for every surface.
	if not needs_override:overrides.clear()
	spec.material_override=null;spec.surface_overrides=overrides
