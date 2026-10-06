extends RefCounted
## Runtime-only opaque shadow surfaces; visual materials and authoring stay intact.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
static var enabled:=true
static var builds:=0
static var attached:=0
static var saved_surfaces:=0
static var max_build_ms:=0.0
static var _materials:Dictionary={}

static func material_supported(material:Material)->bool:
	if material==null:return true
	if not material is StandardMaterial3D:return false
	if material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or material.next_pass!=null or material.blend_mode!=BaseMaterial3D.BLEND_MODE_MIX:return false
	if material.grow or material.fixed_size or material.use_point_size or material.no_depth_test or material.heightmap_enabled or material.proximity_fade_enabled or material.refraction_enabled:return false
	return material.billboard_mode==BaseMaterial3D.BILLBOARD_DISABLED and material.distance_fade_mode==BaseMaterial3D.DISTANCE_FADE_DISABLED and material.depth_draw_mode==BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY

static func attach(node:MeshInstance3D)->bool:
	if not enabled or node.has_meta("building_shadow_proxy"):return false
	if not node.mesh is ArrayMesh or node.mesh.get_surface_count()<2 or node.mesh.get_blend_shape_count()!=0:return false
	if node.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_ON or node.material_overlay!=null or node.transparency!=0 or node.skin!=null:return false
	# Only frozen building geometry has the immutable runtime material contract.
	var record:Dictionary=node.get_meta("ground_batch_record",{})
	if not record.has("house_prefab") or not record.has("building"):return false
	var culls:Array=[]
	for i in node.mesh.get_surface_count():
		var material:=node.get_active_material(i)
		if not material_supported(material):return false
		culls.append(material.cull_mode if material!=null else BaseMaterial3D.CULL_BACK)
	var partitions:Dictionary={}
	for i in culls.size():
		if not partitions.has(culls[i]):partitions[culls[i]]=[]
		partitions[culls[i]].append(i)
	if partitions.size()>=culls.size():return false
	if not node.mesh.has_meta("ground_cpu_cache"):return false # Never download GPU buffers while walking.
	var source:Mesh=Cpu.capture(node.mesh)
	var cache_key:StringName=StringName("opaque_shadow_"+str(culls).sha256_text())
	var shadow:Mesh=source.get_meta(cache_key) if source.has_meta(cache_key) else null
	if shadow==null:
		var began:=Time.get_ticks_usec()
		shadow=ArrayMesh.new()
		# Merge only surfaces with identical face culling. Transparent or vertex-
		# modified meshes were rejected above, so these positions fully define
		# their shadows. Preserve every triangle, including holes and backfaces.
		for cull:int in partitions:
			var part:=Cpu.new()
			for slot:int in partitions[cull]:part.surfaces.append(source.surfaces[slot])
			var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=part.collision_faces()
			if arrays[Mesh.ARRAY_VERTEX].is_empty():return false
			shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			if not _materials.has(cull):
				var material:=StandardMaterial3D.new();material.cull_mode=cull;_materials[cull]=material
			shadow.surface_set_material(shadow.get_surface_count()-1,_materials[cull])
		source.set_meta(cache_key,shadow);builds+=1
		max_build_ms=maxf(max_build_ms,(Time.get_ticks_usec()-began)/1000.)
	var proxy:=MeshInstance3D.new();proxy.name="OpaqueShadow";proxy.mesh=shadow
	proxy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	proxy.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;proxy.layers=node.layers
	proxy.extra_cull_margin=node.extra_cull_margin;proxy.custom_aabb=node.custom_aabb
	proxy.ignore_occlusion_culling=node.ignore_occlusion_culling
	proxy.visibility_range_begin=node.visibility_range_begin;proxy.visibility_range_end=node.visibility_range_end
	proxy.visibility_range_begin_margin=node.visibility_range_begin_margin;proxy.visibility_range_end_margin=node.visibility_range_end_margin
	proxy.visibility_range_fade_mode=node.visibility_range_fade_mode
	proxy.set_meta("stream_instance",true)
	node.add_child(proxy);node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("building_shadow_proxy",proxy)
	attached+=1;saved_surfaces+=node.mesh.get_surface_count()-shadow.get_surface_count()
	return true

static func stats()->Dictionary:
	return {"enabled":enabled,"builds":builds,"attached":attached,"saved_surfaces":saved_surfaces,"max_build_ms":max_build_ms}
