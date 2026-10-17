extends "res://tools/test_s12_residential_published_20261017.gd"
## Same current library/HTTP contract, limited to the new five-step model.
const Walk=preload("res://scripts/world_editor/walk_mode.gd")
var expected_pixels:Dictionary={}
func prepare_published_catalog()->bool:
	expected_ids=["s1_doorstep_stairs_5"]
	if not super.prepare_published_catalog():return false
	var proof:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(published.items[0].acceptance_report))
	expected_pixels=proof.expected_texture_rgba8
	return expected_pixels.size()==3

func base_pixels(texture:Texture2D)->String:
	if texture==null:return "missing"
	var pixels:=texture.get_image()
	if pixels==null:return "unreadable"
	if pixels.is_compressed() and pixels.decompress()!=OK:return "decompress_failed"
	pixels.clear_mipmaps();pixels.convert(Image.FORMAT_RGBA8)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(pixels.get_data());return hash.finish().hex_encode()

func model_evidence(uuid:String)->Dictionary:
	var result:=super.model_evidence(uuid)
	var model:Node3D=editor._view.get_node_or_null(NodePath(uuid))
	if model==null:return result
	var material_found:=false
	for mesh:MeshInstance3D in Paint.meshes(model):
		if not str(mesh.name).contains("original_stones"):continue
		var material:=mesh.get_active_material(0) as StandardMaterial3D
		if material==null:result.valid=false;continue
		var actual:Dictionary={"albedo":base_pixels(material.albedo_texture),"normal":base_pixels(material.normal_texture),"roughness":base_pixels(material.roughness_texture)}
		result.active_stone_material={"normal_enabled":material.normal_enabled,"normal_scale":material.normal_scale,"roughness":material.roughness,"roughness_channel":material.roughness_texture_channel,"metallic":material.metallic,"emission":material.emission_enabled,"rgba8_base_level_sha":actual}
		material_found=true
		result.valid=result.valid and material.normal_enabled and absf(material.normal_scale-.24)<.00001 and material.metallic==0 and not material.emission_enabled and actual==expected_pixels
	result.valid=result.valid and material_found
	result.central_tread_rays=[]
	for k in 5:
		var a:Vector3=model.global_transform*Vector3(0,1,-.2-k*.4);var b:Vector3=model.global_transform*Vector3(0,-.1,-.2-k*.4)
		var hit:=editor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,Walk.WALK_MASK))
		var height:float=(model.global_transform.affine_inverse()*hit.position).y if not hit.is_empty() else -99.
		result.central_tread_rays.append({"step":k+1,"local_y":height})
		result.valid=result.valid and absf(height-(k+1)*.16)<.006
	return result
