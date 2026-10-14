extends "res://tools/review_house_surface_relief.gd"
## Read-only reopening of the already verified isolated maps.
## Bind actual GPU textures, inspect tangents, and relight facing surfaces.
const DIAGNOSTIC=OUTPUT+"/diagnostic"
var diagnostic:Dictionary={"checks":[],"items":[],"formal_writes":false,"manual_visual_acceptance":"pending"}
var original_geometry:Dictionary={}
var diagnostic_folder:=DIAGNOSTIC
var candidate_run:=OUTPUT+"/candidate/strong/report.json"
var candidate_name:="strong"

func check(ok:bool,label:String)->void:
	print("%s: %s"%["PASS" if ok else "FAIL",label])
	diagnostic.checks.append({"ok":ok,"label":label})
	if not ok:failed+=1

func pixels(source:Image)->Dictionary:
	if source==null:return {}
	var copy:=source.duplicate()
	if copy.is_compressed():copy.decompress()
	copy.clear_mipmaps();copy.convert(Image.FORMAT_RGBA8)
	return {"width":copy.get_width(),"height":copy.get_height(),"rgba8_sha256":sha(copy.get_data())}

func audit_bound_materials(item:Dictionary)->Dictionary:
	var expected:Dictionary=item.material.channels
	var base_path:String=expected.texture_path.test_path
	var seen:Dictionary={};var matches:Array=[];var surfaces:=0;var tangent_surfaces:=0
	for child:Node in editor._view.find_children("*","MeshInstance3D",true,false):
		var visual:MeshInstance3D=child
		if visual.mesh==null:continue
		for slot in visual.mesh.get_surface_count():
			var material:=visual.get_active_material(slot)
			if not material is StandardMaterial3D:continue
			var definition:Dictionary=material.get_meta("runtime_paint_definition",{})
			if definition.get("texture_path")!=base_path:continue
			surfaces+=1
			var arrays:Array=visual.mesh.surface_get_arrays(slot)
			var tangents:int=0 if arrays[Mesh.ARRAY_TANGENT]==null else arrays[Mesh.ARRAY_TANGENT].size()
			if tangents==arrays[Mesh.ARRAY_VERTEX].size()*4:tangent_surfaces+=1
			var key:=material.get_instance_id()
			if seen.has(key):continue
			seen[key]=true
			var binding:Dictionary={"normal_enabled":material.normal_enabled,"normal_scale":material.normal_scale,"roughness":material.roughness,"definition":definition,"channels":{},"mesh":str(child.name),"slot":slot,"vertices":arrays[Mesh.ARRAY_VERTEX].size(),"tangent_floats":tangents}
			for pair:Array in [["texture_path",material.albedo_texture],["normal_path",material.normal_texture],["roughness_path",material.roughness_texture]]:
				if not expected.has(pair[0]):continue
				var source:Image=Image.load_from_file(expected[pair[0]].test_path)
				var actual:Image=null if pair[1]==null else pair[1].get_image()
				binding.channels[pair[0]]={"expected":pixels(source),"actual_gpu_texture":pixels(actual)}
				check(binding.channels[pair[0]].expected==binding.channels[pair[0]].actual_gpu_texture,"GPU bound pixels match candidate "+item.id+" "+pair[0])
			if expected.has("normal_path"):
				check(material.normal_enabled and is_equal_approx(material.normal_scale,float(item.material.definition.get("normal_strength",1.))),"enabled intended normal amplitude "+item.id)
			matches.append(binding)
	check(surfaces>0,"actual visible material binding found "+item.id)
	if expected.has("normal_path"):check(tangent_surfaces==surfaces,"all bound normal surfaces carry full tangent channel "+item.id)
	return {"bindings":matches,"matched_surfaces":surfaces,"surfaces_with_complete_tangents":tangent_surfaces}

func audit_geometry()->Dictionary:
	var records:Array=[];var channel_totals:Dictionary={}
	for record:Dictionary in editor._doc.records:
		if not record.has("house_prefab"):continue
		var meshes:Array=[]
		for mesh:Dictionary in Prefab.decode(record.house_prefab).meshes:
			var surfaces:Array=[]
			for slot in mesh.surfaces.size():
				var arrays:Array=mesh.surfaces[slot]
				var hashes:Array=[]
				for channel in arrays.size():
					hashes.append(sha(var_to_bytes(arrays[channel])))
					channel_totals[str(channel)]=int(channel_totals.get(str(channel),0))+(0 if arrays[channel]==null else arrays[channel].size())
				var lods:Variant=mesh.get("lods",[])
				surfaces.append({"all":sha(var_to_bytes(arrays)),"channels":hashes,"lods_sha256":sha(var_to_bytes({} if lods.is_empty() else lods[slot]))})
			surfaces.sort_custom(func(a,b):return a.all<b.all)
			meshes.append({"bounds":str(mesh.bounds),"surfaces":surfaces})
		records.append({"part":record.building.part,"position":record.position,"rotation":record.rotation,"size":record.size,"meshes":meshes})
	return {"canonical_geometry_sha256":sha(var_to_bytes(records)),"records":records,"channel_element_totals":channel_totals}

func diagnostic_capture(label:String,at:Vector3,target:Vector3,size_:float,rotation_:Vector3,face_normal:Vector3)->Dictionary:
	configure_render();editor._camera.projection=Camera3D.PROJECTION_ORTHOGONAL;editor._camera.size=size_;editor._camera.position=at;editor._camera.look_at(target)
	editor._sun.rotation_degrees=rotation_
	for frame in 48:await process_frame
	await RenderingServer.frame_post_draw
	var image:Image=editor._camera.get_viewport().get_texture().get_image()
	var path:=current_folder.path_join(label+".webp")
	check(image.save_webp(path,true,.94)==OK,"diagnostic WebP capture "+label)
	var incoming:Vector3=editor._sun.global_basis.z.normalized()
	return {"path":path,"sha256":FileAccess.get_sha256(path),"width":image.get_width(),"height":image.get_height(),"position":[at.x,at.y,at.z],"target":[target.x,target.y,target.z],"orthographic_size":size_,"sun_rotation":[rotation_.x,rotation_.y,rotation_.z],"light_to_surface_normal_dot":incoming.dot(face_normal),"note":"Normal is exact panel/facade face; roof uses approximate +X/up slope normal."}

func run()->void:
	if "--syntax-only" in OS.get_cmdline_user_args():print("DIAGNOSTIC syntax only");quit();return
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--candidate-run="):candidate_run=arg.trim_prefix("--candidate-run=")
		if arg.begins_with("--label="):
			candidate_name=arg.trim_prefix("--label=")
			if not candidate_name.is_valid_filename():quit(2);return
			diagnostic_folder=DIAGNOSTIC.path_join(candidate_name)
		if arg.begins_with("--only="):chosen=arg.trim_prefix("--only=").split(",",false)
	if DisplayServer.get_name()=="headless":quit(2);return
	Engine.max_fps=60;rpc_timeout_ms=240000;root.size=Vector2i(1440,1000);root.content_scale_size=root.size
	inventory=JSON.parse_string(FileAccess.get_file_as_string(INVENTORY))
	guards=inventory.protected_files.duplicate(true)
	previous_override=root.get_node("AssetManager").content_root_override
	fixed_env.ambient_energy=.10;fixed_env.sun_energy=1.4;fixed_env.ambient_occlusion=false
	diagnostic.environment=fixed_env;diagnostic.exposure=1.;diagnostic.msaa="4x";diagnostic.taa=true
	for variant_name:String in ["baseline",candidate_name]:
		var source_path:=OUTPUT.path_join("baseline/report.json") if variant_name=="baseline" else candidate_run
		var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_path))
		check(report.completed and report.passed,"use complete isolated source run "+variant_name)
		fixture_root=report.fixture_root;root.get_node("AssetManager").content_root_override=fixture_root
		await setup_editor()
		for item:Dictionary in report.items:
			if not item.id in ["roofs/terracotta_plain","roofs/terracotta_warm","walls/earthen_plaster"]:continue
			if not chosen.is_empty() and not item.id in chosen:continue
			await call_tool("open_world",{"path":item.map_path,"discard_changes":true});await ready_editor()
			await call_tool("set_environment",fixed_env)
			current_folder=diagnostic_folder.path_join(variant_name).path_join(item.id);DirAccess.make_dir_recursive_absolute(current_folder)
			var row:Dictionary={"id":item.id,"variant":variant_name,"source_report_sha256":FileAccess.get_sha256(source_path),"definition_sha256":item.material.definition_sha256,"bound_material":audit_bound_materials(item),"geometry":audit_geometry(),"captures":[]}
			if variant_name=="baseline":original_geometry[item.id]=row.geometry
			else:row.geometry_matches_baseline=row.geometry==original_geometry[item.id]
			row.captures.append(await diagnostic_capture("panel_light_left",Vector3(29.1,2.2,4),Vector3(28,1.5,0),1.55,Vector3(-8,-75,0),Vector3.FORWARD*-1))
			row.captures.append(await diagnostic_capture("panel_light_right",Vector3(29.1,2.2,4),Vector3(28,1.5,0),1.55,Vector3(-8,75,0),Vector3.FORWARD*-1))
			if item.id.begins_with("roofs/"):
				row.captures.append(await diagnostic_capture("roof_facing_raking",Vector3(12,16,4),Vector3(1.6,8.4,0),5.2,Vector3(-8,175,0),Vector3(.55,.84,0).normalized()))
				row.captures.append(await diagnostic_capture("roof_facing_raking_close",Vector3(12,16,4),Vector3(1.6,8.4,0),1.9,Vector3(-8,175,0),Vector3(.55,.84,0).normalized()))
			else:
				row.captures.append(await diagnostic_capture("facade_facing_raking",Vector3(12,7,-16),Vector3(-.2,3.5,-5.7),7.,Vector3(-8,105,0),Vector3.FORWARD))
				row.captures.append(await diagnostic_capture("facade_facing_raking_close",Vector3(12,7,-16),Vector3(-.2,3.5,-5.7),2.2,Vector3(-8,105,0),Vector3.FORWARD))
			put(current_folder.path_join("report.json"),row);diagnostic.items.append(row)
			put(diagnostic_folder.path_join("report.json"),diagnostic)
		editor._mcp.stop();editor.queue_free();await settle()
	root.get_node("AssetManager").content_root_override=previous_override
	for path:String in guards:check(FileAccess.get_sha256(path)==guards[path],"formal data unchanged "+path)
	diagnostic.completed=true;diagnostic.failures=failed;diagnostic.passed=failed==0
	put(diagnostic_folder.path_join("report.json"),diagnostic);quit(0 if failed==0 else 1)
