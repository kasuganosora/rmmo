extends "res://tools/test_s12_residential_published_20261017.gd"
## Production catalogue/HTTP contract, scoped to the dedicated S1 residence.
var expected_materials:Dictionary={}
const Walk=preload("res://scripts/world_editor/walk_mode.gd")

func verify_item(row:Dictionary,map_path:String)->void:
	await super.verify_item(row,map_path)
	var initial:=failed
	await call_tool("place_asset",{"asset_id":row.output_path,"position":[0,0,0]})
	if editor._doc.records.size()!=1:check(false,"floor fixture placed");return
	var uuid:String=editor._doc.records[0].uuid;await wait_loaded(uuid)
	var regions:Array=preload("res://scripts/world3d/imported_building.gd").regions(editor._doc.records[0])
	check(not regions.any(func(r):return r.floor==1 and r.rect.has_point(Vector2(-2.8,0))),"upper stair void excluded from indoor region")
	check(not regions.any(func(r):return r.floor==2 and r.rect.has_point(Vector2(.9,0))),"loft stair void excluded from indoor region")
	check(not regions.any(func(r):return r.floor==0 and r.rect.has_point(Vector2(-4,0))),"wall thickness excluded from indoor region")
	check(regions.any(func(r):return r.floor==2 and r.rect.has_point(Vector2(-1,0))),"real loft standing area retained")
	row.floor_probe=[]
	for floor_index in 3:
		await call_tool("set_floor_view",{"isolation":true,"base_height":floor_index*3.25,"floor_height":3.25,"outside":"hide"});await wait_loaded(uuid);await physics_frame;await physics_frame
		var visible_count:=0;var hidden_count:=0
		for body:StaticBody3D in editor._bodies_by_uuid.get(uuid,[]):
			var visual:MeshInstance3D=body.get_meta("visual");var extras:Dictionary=visual.get_meta("extras",{});var part:Dictionary=extras.get("rmmo_part",{})
			if part.is_empty():continue
			var expected:=int(part.floor)==floor_index
			if part.role in ["roof","ceiling"]:
				var bounds:AABB=visual.global_transform*visual.get_aabb()
				expected=bounds.position.y>=floor_index*3.25-.001 and bounds.end.y<(floor_index+1)*3.25-.001
			check(bool(body.collision_layer&1)==expected,"floor selection matches authored part "+str(floor_index)+" "+str(visual.name))
			check(bool(body.collision_layer&Walk.WALK_MASK)==Walk.physical(extras),"floor isolation retains physical mask "+str(visual.name))
			if expected:visible_count+=1
			else:hidden_count+=1
		check(visible_count>0 and hidden_count>0,"both visible and hidden parts at floor "+str(floor_index));row.floor_probe.append({"floor":floor_index,"selectable":visible_count,"hidden":hidden_count})
	await call_tool("set_floor_view",{"isolation":false});await wait_loaded(uuid)
	await call_tool("select_objects",{"ids":[uuid]});await call_tool("delete_selection");await wait_loaded()
	row.floor_probe_passed=failed==initial;row.http_passed=row.http_passed and row.floor_probe_passed
	write_json(output_dir.path_join("items").path_join(str(row.id)+".json"),row);flush_report()

func prepare_published_catalog()->bool:
	expected_ids=["s1_bridge_left_residence"]
	if not super.prepare_published_catalog():return false
	var proof:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(published.items[0].acceptance_report))
	expected_materials=proof.expected_material_textures
	return expected_materials.size()==5

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
	var found:Dictionary={}
	for mesh:MeshInstance3D in Paint.meshes(model):
		for slot in mesh.mesh.get_surface_count():
			var m:=mesh.get_active_material(slot) as StandardMaterial3D
			if m==null or not expected_materials.has(m.resource_name):continue
			var actual:Dictionary={"albedo":base_pixels(m.albedo_texture),"normal":base_pixels(m.normal_texture),"roughness":base_pixels(m.roughness_texture)}
			var expected:Dictionary=expected_materials[m.resource_name]
			found[m.resource_name]={"rgba8_base_sha":actual,"normal_enabled":m.normal_enabled,"normal_scale":m.normal_scale,"roughness_channel":m.roughness_texture_channel}
			result.valid=result.valid and m.normal_enabled and absf(m.normal_scale-float(expected.normal_scale))<.00001 and m.metallic==0 and not m.emission_enabled and actual==expected.textures
	result.material_evidence=found;result.valid=result.valid and found.size()==expected_materials.size()
	return result
