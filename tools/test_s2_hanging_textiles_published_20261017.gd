extends "res://tools/test_s12_residential_published_20261017.gd"
## Reuses existing HTTP/persistence contract, with the exact four S2 products.
const Banner=preload("res://scripts/world3d/streetlamp_banner.gd")
func http_runtime_identity()->Dictionary:
	var result:=super.http_runtime_identity()
	result["scripts/world3d/streetlamp_banner.gd"]=FileAccess.get_sha256("res://scripts/world3d/streetlamp_banner.gd")
	return result

func prepare_published_catalog()->bool:
	expected_ids=["s2_yellow_rectangular_festoon_8m","s2_wall_to_wall_white_laundry_36m","s2_ochre_long_banner","s2_bronze_lamp_long_ochre_banner"]
	return super.prepare_published_catalog()

func model_evidence(uuid:String)->Dictionary:
	var result:=super.model_evidence(uuid)
	var holder:Node=editor._view.get_node_or_null(NodePath(uuid));var cloth:Array=[]
	if holder!=null:
		for node:MeshInstance3D in Paint.meshes(holder):
			var config:Dictionary=node.get_meta("extras",{}).get("rmmo_wind",{})
			if config.is_empty():continue
			var surfaces:Array=[]
			for slot in node.mesh.get_surface_count():
				var mat:Material=Paint.source_material(node,slot)
				if not mat is StandardMaterial3D:continue
				var normal:Texture2D=mat.normal_texture
				var pixels:=normal.get_image() if normal!=null else null
				if pixels!=null:pixels.clear_mipmaps();pixels.convert(Image.FORMAT_RGBA8)
				surfaces.append({"normal_enabled":mat.normal_enabled,"normal_scale":mat.normal_scale,"normal_pixel_sha256":digest(pixels.get_data()) if pixels!=null else "","roughness":mat.roughness,"metallic":mat.metallic})
			cloth.append({"name":str(node.name),"config":config,"surfaces":surfaces})
	result.cloth=cloth
	return result

func verify_item(row:Dictionary,map_path:String)->void:
	await super.verify_item(row,map_path)
	if not row.has("after_reopen"):return
	check(equivalent(row.before_save.cloth,row.after_reopen.cloth),"cloth wind and actual normal pixels survive formal save/reopen "+row.id)
	var proof:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(row.prior_visual_review))
	var gpu:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(proof.gpu_report.path))
	check(row.after_reopen.cloth.size()==gpu.wind_mesh_count,"formal cloth count equals reviewed native "+row.id)
	var expected:Array=gpu.active_cloth_materials.map(func(m):return m.normal_pixel_sha256)
	var reviewed:Node=load(proof.native.path).instantiate()
	var configs:Dictionary={}
	for mesh:MeshInstance3D in Paint.meshes(reviewed):
		if mesh.get_meta("extras",{}).has("rmmo_wind"):configs[str(mesh.name)]=mesh.get_meta("extras").rmmo_wind
	for node:Dictionary in row.after_reopen.cloth:
		check(equivalent(node.config,configs.get(node.name,{})),"formal wind parameters equal reviewed native "+row.id+"/"+node.name)
		for s:Dictionary in node.surfaces:check(s.normal_enabled and s.normal_pixel_sha256 in expected and s.metallic==0,"formal cloth real material channels "+row.id+"/"+node.name)
	reviewed.free()
	if row.id=="s2_bronze_lamp_long_ochre_banner":await verify_banner_toggle(row,map_path)
	row.http_passed=failed==0
	write_json(output_dir.path_join("items").path_join(str(row.id)+".json"),row)

func slot_fingerprint(uuid:String)->Dictionary:
	var node:=Banner.slot(editor._view.get_node(NodePath(uuid)));var result:Dictionary={"surfaces":[]}
	for i in node.mesh.get_surface_count():
		var mat:StandardMaterial3D=Paint.source_material(node,i)
		var row:Dictionary={"vertices":digest(var_to_bytes(node.mesh.surface_get_arrays(i))),"albedo":var_to_str(mat.albedo_color),"roughness":mat.roughness,"metallic":mat.metallic,"normal_scale":mat.normal_scale}
		for key:String in ["albedo_texture","roughness_texture","normal_texture"]:
			var tex:Texture2D=mat.get(key)
			var pixels:=tex.get_image() if tex!=null else null
			if pixels!=null:pixels.clear_mipmaps();pixels.convert(Image.FORMAT_RGBA8)
			row[key]=digest(pixels.get_data()) if pixels!=null else ""
		result.surfaces.append(row)
	return result

func verify_banner_toggle(row:Dictionary,map_path:String)->void:
	# Parent deleted only the owned test instance; undo restores it for this
	# affected editor operation, without introducing another source/library.
	var uuid:String=row.test_uuid
	await call_tool("undo");await wait_loaded(uuid)
	var before:=slot_fingerprint(uuid);var snapshot:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("select_objects",{"ids":[uuid]})
	check(editor._inspector.banner_panel.visible,"imported single-surface printed cloth exposes existing UI controls")
	await call_tool("set_streetlamp_banner",{"ids":[uuid],"settings":{"shape":"invalid"}},false)
	check(equivalent(snapshot,editor._doc.recovery_snapshot()),"invalid printed-banner edit has no side effects")
	await call_tool("set_streetlamp_banner",{"ids":[uuid],"settings":{"wind_enabled":false}});await wait_loaded(uuid)
	row.banner_toggle_disabled_fingerprint=slot_fingerprint(uuid)
	check(equivalent(before,slot_fingerprint(uuid)),"wind-only edit preserves printed cloth geometry and all PBR channels")
	check(model_evidence(uuid).cloth.is_empty(),"printed cloth wind disabled through real HTTP")
	await call_tool("undo");await wait_loaded(uuid)
	check(equivalent(row.after_reopen.cloth,model_evidence(uuid).cloth),"wind edit undo restores reviewed authored parameters")
	await call_tool("redo");await wait_loaded(uuid)
	await call_tool("save_world",{"path":map_path})
	while editor._save_job.active:await process_frame
	await call_tool("open_world",{"path":map_path});await wait_loaded(uuid)
	check(model_evidence(uuid).cloth.is_empty() and equivalent(before,slot_fingerprint(uuid)),"disabled wind and unchanged printed PBR survive save/reopen")
	await call_tool("set_streetlamp_banner",{"ids":[uuid],"settings":{"wind_enabled":true}});await wait_loaded(uuid)
	check(equivalent(row.after_reopen.cloth,model_evidence(uuid).cloth) and equivalent(before,slot_fingerprint(uuid)),"re-enable wind preserves reviewed parameters and printed PBR")
	row.banner_toggle_fingerprint=before
	await call_tool("select_objects",{"ids":[uuid]});await call_tool("delete_selection");await wait_loaded()
