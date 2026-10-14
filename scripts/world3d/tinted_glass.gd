extends RefCounted
## Explicit thin stained-glass optics. Multiplication transmits the actual
## background colour; a separate dielectric PBR pass supplies reflection.
## Both passes stay native StandardMaterial3D. No intrinsic emission or refraction.
const KEY := "rmmo_tinted_glass"
const STAMP := "rmmo_tinted_glass_recipe_v1"

static func valid(raw:Variant)->bool:
	if not raw is Dictionary or raw.get("version")!=1 or not raw.get("materials") is Dictionary:return false
	if raw.materials.is_empty() or raw.materials.size()>64:return false
	for name_:Variant in raw.materials:
		if not name_ is String or name_.is_empty() or name_.length()>256:return false
		var spec:Variant=raw.materials[name_]
		if not spec is Dictionary or not spec.get("transmittance") is Array or spec.transmittance.size()!=3:return false
		for value:Variant in spec.transmittance:
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or value<=0 or value>1:return false
		var rough:Variant=spec.get("roughness",.13)
		if typeof(rough) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(rough)) or rough<.02 or rough>.6:return false
	return true

static func make(source:StandardMaterial3D,spec:Dictionary)->StandardMaterial3D:
	var transmitted:=source.duplicate() as StandardMaterial3D
	transmitted.next_pass=null
	transmitted.resource_name=source.resource_name
	transmitted.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	transmitted.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	transmitted.blend_mode=BaseMaterial3D.BLEND_MODE_MUL
	var tint:Array=spec.transmittance
	transmitted.albedo_color=Color(tint[0]*.96,tint[1]*.96,tint[2]*.96,1).linear_to_srgb()
	transmitted.albedo_texture=null
	transmitted.emission_enabled=false
	transmitted.emission_texture=null
	transmitted.normal_enabled=false
	transmitted.clearcoat_enabled=false
	transmitted.refraction_enabled=false
	transmitted.metallic=0
	var reflected:=source.duplicate() as StandardMaterial3D
	reflected.next_pass=null
	reflected.resource_name=source.resource_name+" dielectric reflection"
	reflected.shading_mode=BaseMaterial3D.SHADING_MODE_PER_PIXEL
	reflected.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	reflected.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
	reflected.albedo_color=Color(0,0,0,1)
	reflected.albedo_texture=null
	reflected.metallic=0
	reflected.metallic_specular=.5
	reflected.roughness=float(spec.get("roughness",.13))
	reflected.clearcoat_enabled=false
	reflected.emission_enabled=false
	reflected.emission_texture=null
	reflected.refraction_enabled=false
	transmitted.next_pass=reflected
	transmitted.set_meta(STAMP,JSON.stringify(spec,"",true))
	return transmitted

static func apply(root:Node)->void:
	var shared:Dictionary={}
	for mesh:MeshInstance3D in preload("res://scripts/world3d/surface_materials.gd").meshes(root):
		var raw:Variant=mesh.get_meta("extras",{}).get(KEY)
		if not valid(raw):continue
		for slot in mesh.mesh.get_surface_count():
			var source:=mesh.get_active_material(slot) as StandardMaterial3D
			if source==null or not raw.materials.has(source.resource_name):continue
			var spec:Dictionary=raw.materials[source.resource_name]
			var stamp:=JSON.stringify(spec,"",true)
			if source.get_meta(STAMP,"")==stamp:continue
			var key:=str(source.get_instance_id())+":"+stamp
			if not shared.has(key):shared[key]=make(source,spec)
			mesh.set_surface_override_material(slot,shared[key])
