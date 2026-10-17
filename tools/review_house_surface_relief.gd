extends "res://tools/build_medieval_material_demo.gd"
## Isolated normal/PBR review. No formal map, catalog, or material writes.
## --variant=baseline|candidate --label=balanced|strong --candidates=<family -> material.json mapping JSON>
## --only=roofs/terracotta_plain,... --syntax-only
const INVENTORY="D:/code/rmmo_runtime/review_artifacts/house_surface_relief_20261014/baseline_inventory.json"
const OUTPUT="D:/code/rmmo_runtime/review_artifacts/house_surface_relief_20261014/gallery"
const FORMAL="D:/code/rmmo_runtime/packs/default/assets/materials"
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Compiler=preload("res://scripts/world_editor/building_tools.gd")
var variant:="baseline"
var output_label:=""
var candidates:Dictionary={}
var chosen:PackedStringArray=[]
var fixture_root:=""
var previous_override:=""
var inventory:Dictionary={}
var guards:Dictionary={}
var evidence:Dictionary={"checks":[],"items":[],"formal_writes":false,"manual_visual_acceptance":"pending"}
var active_family:=""
var current_folder:=""
var channels:Dictionary={}
var fixed_env:Dictionary={"preset":"day","sky_enabled":false,"sun_rotation":[-38,145,0],"sun_color":[1,.97,.93],"sun_energy":1.1,"ambient_color":[.76,.8,.86],"ambient_energy":.38,"background_color":[.12,.15,.19],"sun_shadows":true,"ambient_occlusion":true,"fog_enabled":false,"outline_enabled":false,"wind_speed":0.,"time_speed":0.,"celestial_cycle":false,"surface_wetness":false}

func check(ok:bool,label:String)->void:
	print("%s: %s"%["PASS" if ok else "FAIL",label])
	evidence.checks.append({"ok":ok,"label":label})
	if not ok:failed+=1

func put(path:String,value:Variant)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:push_error("Cannot write review report "+path);failed+=1;return
	file.store_string(JSON.stringify(value,"  ",true,true));file.close()

func flush()->void:
	evidence.failures=failed;evidence.passed=failed==0;evidence.variant=variant
	evidence.output_label=output_label
	put(output_directory().path_join("report.json"),evidence)

func output_directory()->String:
	return OUTPUT.path_join(variant) if output_label.is_empty() else OUTPUT.path_join(variant).path_join(output_label)

func sha(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()

func copy_definition(family:String,source:String)->void:
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(source))
	check(data is Dictionary and data.get("material") is Dictionary,"valid descriptor "+family)
	if not data is Dictionary:return
	guards[source]=FileAccess.get_sha256(source)
	var target:=fixture_root.path_join("packs/default/assets/materials").path_join(family)
	DirAccess.make_dir_recursive_absolute(target)
	var costs:Dictionary={"definition_path":source,"definition_sha256":guards[source],"channels":{},"definition":data.material.duplicate(true)}
	for field:String in Paint.MAP_FIELDS:
		var source_path:=str(data.material.get(field,""))
		if source_path.is_empty():continue
		if not source_path.is_absolute_path():source_path=source.get_base_dir().path_join(source_path).simplify_path()
		var destination:=target.path_join(source_path.get_file())
		check(FileAccess.file_exists(source_path) and DirAccess.copy_absolute(source_path,destination)==OK,"copy isolated material channel "+family+" "+field)
		guards[source_path]=FileAccess.get_sha256(source_path)
		var image:=Image.load_from_file(destination)
		check(image!=null and not image.is_empty(),"channel decodes "+family+" "+field)
		if image==null:continue
		var file:=FileAccess.open(destination,FileAccess.READ);var bytes:=file.get_length();file.close()
		costs.channels[field]={"source":source_path,"source_sha256":guards[source_path],"test_path":destination,"test_sha256":FileAccess.get_sha256(destination),"encoded_bytes":bytes,"width":image.get_width(),"height":image.get_height(),"decoded_format":image.get_format(),"decoded_bytes":image.get_data().size(),"rgba8_full_mips_budget_bytes":ceili(image.get_width()*image.get_height()*4.*4./3.)}
		data.material[field]=destination.get_file()
	put(target.path_join("material.json"),data)
	costs.copied_definition_path=target.path_join("material.json")
	costs.copied_definition_sha256=FileAccess.get_sha256(costs.copied_definition_path)
	channels[family]=costs

func prepare_fixture()->void:
	inventory=JSON.parse_string(FileAccess.get_file_as_string(INVENTORY))
	check(inventory.items.size()==10,"exact two roofs and eight exterior wall families")
	guards=inventory.protected_files.duplicate(true);guards[INVENTORY]=FileAccess.get_sha256(INVENTORY)
	fixture_root=Paths.cache_directory("house_surface_relief_%s_%d"%[variant,Time.get_ticks_usec()])
	check(not DirAccess.dir_exists_absolute(fixture_root),"new isolated content root")
	DirAccess.make_dir_recursive_absolute(fixture_root)
	put(fixture_root.path_join("packs/default/metadata.json"),{"id":"default","name":"默认","version":"review-only"})
	var copied:Dictionary={}
	for item:Dictionary in inventory.items:
		check(FileAccess.get_sha256(item.definition_path)==item.definition_sha256,"formal baseline descriptor unchanged "+item.id)
		guards[item.definition_path]=item.definition_sha256
		for channel:Dictionary in item.channels.values():
			check(FileAccess.get_sha256(channel.path)==channel.sha256,"formal baseline channel unchanged "+item.id);guards[channel.path]=channel.sha256
		var source:=str(candidates.get(item.id,item.definition_path)) if variant=="candidate" else str(item.definition_path)
		copy_definition(item.id,source);copied[item.id]=true
	for id:String in IDS.values():
		var family:=id.trim_prefix("pack:default:").trim_suffix("/material")
		# Interior wall families are intentionally excluded from this review.
		if family=="walls/interior_limewash" or copied.has(family):continue
		copy_definition(family,FORMAL.path_join(family).path_join("material.json"));copied[family]=true
	# Existing authored door components are input dependencies of the house
	# generator; copy those two small geometry recipes without changing them.
	for relative:String in ["timber_door/timber_door_mesh.json","interior_timber_door/interior_timber_door_mesh.json"]:
		var source:=Paths.external_root().path_join("assets").path_join(relative)
		var destination:=fixture_root.path_join("assets").path_join(relative)
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		check(DirAccess.copy_absolute(source,destination)==OK,"isolated unchanged generator dependency "+relative)
		guards[source]=FileAccess.get_sha256(source)
	var manager:=root.get_node("AssetManager");previous_override=manager.content_root_override;manager.content_root_override=fixture_root
	check(Paths.external_root()==fixture_root,"real material discovery uses only isolated content root")
	evidence.fixture_root=fixture_root;evidence.inventory_sha256=guards[INVENTORY]
	evidence.render={"window":[1440,1000],"msaa":"4x","taa":true,"exposure":1.,"tonemap":"ACES","environment":fixed_env,"webp_quality":.92,"cost_note":"RGBA8 mip budgets are conservative estimates, not RSS/VRAM."}

func ready_editor()->void:
	for i in 1800:
		await process_frame
		if i>12 and editor._load_job!=null and not editor._load_job.active and not editor.saving() and editor._view!=null:return
	check(false,"editor readiness timeout")

func setup_editor()->void:
	var path:=fixture_root.path_join("maps/start/map.gltf")
	var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.1,0),Vector3(70,.2,30));check(doc.save(path)==OK,"create owned starter map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=fixture_root.path_join("drafts");root.add_child(editor)
	await ready_editor();editor._safety.enabled=false
	var probe:=TCPServer.new();port=30020
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"isolated real 3D HTTP start")
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var tools_:Array=(await rpc("tools/list")).get("result",{}).get("tools",[])
	for name_:String in ["list_surface_materials","paint_surface","list_object_surfaces","save_world","open_world","undo","redo","set_environment"]:check(tools_.any(func(row):return row.name==name_),"tool discovered by name "+name_)
	var listing:=await call_tool("list_surface_materials",{"limit":200})
	for row:Dictionary in listing.materials:definitions[row.material_id]=row.material
	definitions[IDS.interior]={"name":"测试用内墙中性色","color":[.78,.76,.7,1.],"roughness":.95}
	for item:Dictionary in inventory.items:check(definitions.has(item.material_id),"normal shared catalog discovers "+item.id)

func register_house(records:Array,parameters:Dictionary,baked:bool)->void:
	var registry:Dictionary={"version":Blueprint.VERSION,"parameters":parameters,"position":[0,0,0],"yaw":0.,"parts":{},"signatures":{},"baked":baked,"source_part_count":records.size()}
	for i in records.size():
		var record:Dictionary=records[i];record.uuid="review_house_%d"%i;record.building.id="review_house"
		registry.parts[record.building.part]=record.uuid;registry.signatures[record.building.part]=Blueprint.geometry_signature(record)
	editor._doc.map_meta.building_instances={"review_house":registry}
	editor._doc.records.append_array(records)

func geometry_digest(records:Array)->String:
	var identities:Array=[]
	for record:Dictionary in records:identities.append(Blueprint.geometry_signature(record))
	return sha(var_to_bytes(identities))

func paint_house(family:String)->Dictionary:
	var parameters:Dictionary=Blueprint.medieval_presets()[0].parameters.duplicate(true);parameters.eaves=.45
	var plan:Dictionary=Blueprint.generate(parameters)
	check(plan.get("ok",false),"real generator creates temporary sample house")
	if not plan.get("ok",false):return {}
	register_house(plan.records,plan.parameters,false)
	editor._rebuild();await ready_editor()
	var geometry_before:=geometry_digest(plan.records)
	var old_roof:Dictionary=definitions[IDS.roof];var old_wall:Dictionary=definitions[IDS.plaster]
	if family.begins_with("roofs/"):definitions[IDS.roof]=definitions["pack:default:"+family+"/material"]
	else:definitions[IDS.plaster]=definitions["pack:default:"+family+"/material"]
	var validation:Dictionary={};var faces_count:=0
	for record:Dictionary in editor._doc.records:
		if not record.has("building") or record.get("building_shape") in ["candle_sconce","timber_door","interior_door","interior_door_frame"]:continue
		var visual:MeshInstance3D=editor._view.get_node(NodePath(record.uuid))
		var geometry:Dictionary=Paint.geometry(visual)
		if not geometry.get("ok",false):check(false,"sample author geometry");continue
		var entries:Array=[]
		for slot in geometry.surfaces.size():
			var surface:Dictionary=geometry.surfaces[slot]
			for face_key:Variant in surface.faces:
				var normal:Vector3=(visual.global_basis.inverse().transposed()*surface.faces[face_key].normal).normalized()
				var face:Dictionary={"normal":[normal.x,normal.y,normal.z],"target":{"mesh":".","surface":slot,"face":face_key,"geometry":surface.signature}}
				var role:=material_role(record,face)
				var entry:Dictionary=face.target.duplicate(true);entry.merge({"mapping":"meters","scale":[1,1],"rotation":0.,"offset":[0,0]});entry.merge(settings_for(record,face,role));entry.material=definitions[IDS[role]].duplicate(true);entries.append(entry);faces_count+=1
		record.surface_paint=entries;check(Paint.valid(record,false,"",validation),"sample face materials validate "+record.uuid)
	definitions[IDS.roof]=old_roof;definitions[IDS.plaster]=old_wall
	var own:Array=editor._doc.records.filter(func(record):return record.has("building"))
	check(geometry_digest(own)==geometry_before,"material assignment preserves authored house geometry")
	var frozen:Dictionary={"position":[0,0,0],"yaw":0.,"records":own}
	var baked:=Compiler.new().freeze_plan(frozen);check(baked.get("ok",false),"production house freeze with current material definitions "+str(baked))
	if not baked.get("ok",false):return {}
	var materials:Dictionary={};var packed_geometry:Array=[]
	for record:Dictionary in frozen.records:
		if record.has("house_prefab"):
			var decoded:=Prefab.decode(record.house_prefab)
			for mesh:Dictionary in decoded.meshes:packed_geometry.append({"surfaces":mesh.surfaces,"lods":mesh.get("lods",[]),"bounds":mesh.bounds})
		for definition:Dictionary in record.get("prefab_materials",[]):
			for field:String in Paint.MAP_FIELDS:
				var path:=str(definition.get(field,""))
				if not path.is_empty():materials[path]=FileAccess.get_sha256(path)
	editor._doc.records=editor._doc.records.filter(func(record):return not record.has("building"))
	register_house(frozen.records,plan.parameters,true)
	editor._rebuild();await ready_editor()
	return {"authored_geometry_sha256":geometry_before,"frozen_geometry_and_lods_sha256":sha(var_to_bytes(packed_geometry)),"source_parts":own.size(),"frozen_parts":frozen.records.size(),"painted_faces":faces_count,"material_channel_hashes":materials,"note":"Actual production house freeze; no added geometry or changed LOD scheme for material relief."}

func configure_render()->void:
	editor._grid.hide();editor._city.overlay.hide();editor._authoring.marker.hide()
	var viewport:Viewport=editor._camera.get_viewport();viewport.msaa_3d=Viewport.MSAA_4X;viewport.use_taa=true
	editor._camera.environment.tonemap_mode=Environment.TONE_MAPPER_ACES;editor._camera.environment.tonemap_exposure=1.
	if editor._camera.attributes is CameraAttributesPractical:editor._camera.attributes.auto_exposure_enabled=false
	# Test light is intentionally fixed; camera motion does not affect the clock.

func capture_webp(label:String,at:Vector3,target:Vector3,size_:float,raking:bool=false)->Dictionary:
	configure_render();editor._camera.projection=Camera3D.PROJECTION_ORTHOGONAL;editor._camera.size=size_;editor._camera.position=at;editor._camera.look_at(target)
	editor._sun.rotation_degrees=Vector3(-14,-65,0) if raking else Vector3(-38,145,0)
	for frame in 32:await process_frame
	await RenderingServer.frame_post_draw
	var image:Image=editor._camera.get_viewport().get_texture().get_image()
	var path:=current_folder.path_join(label+".webp");check(image.save_webp(path,true,.92)==OK,"direct WebP capture "+active_family+" "+label)
	return {"path":path,"sha256":FileAccess.get_sha256(path),"width":image.get_width(),"height":image.get_height(),"position":[at.x,at.y,at.z],"target":[target.x,target.y,target.z],"orthographic_size":size_,"sun_rotation":[editor._sun.rotation_degrees.x,editor._sun.rotation_degrees.y,editor._sun.rotation_degrees.z]}

func review_family(item:Dictionary)->void:
	active_family=item.id;current_folder=output_directory().path_join(active_family);DirAccess.make_dir_recursive_absolute(current_folder)
	evidence.active=active_family;flush()
	var before_failures:=failed;var map_path:=fixture_root.path_join("maps").path_join(active_family.replace("/","_")).path_join("map.gltf")
	var doc:=Doc.new();doc.add_box("ground",Vector3(10,-.12,0),Vector3(64,.24,26));var panel:String=doc.add_box("block",Vector3(28,1.5,0),Vector3(4,3,.2))
	check(doc.save(map_path)==OK,"owned per-family map");await call_tool("open_world",{"path":map_path,"discard_changes":true});await ready_editor()
	await call_tool("set_environment",fixed_env)
	var surfaces:=await call_tool("list_object_surfaces",{"id":panel})
	var front:Dictionary=surfaces.faces.filter(func(face):return float(face.normal[2])>.99)[0]
	var arguments:Dictionary={"id":panel,"target":front.target,"material_id":item.material_id,"mapping":"meters"}
	var before:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	await call_tool("paint_surface",arguments);var painted:Dictionary=editor._doc.recovery_snapshot()
	check(editor._doc._undo.size()==history+1,"one HTTP brush undo transaction "+active_family)
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"brush undo restores author state "+active_family)
	await call_tool("redo");check(equivalent(painted,editor._doc.recovery_snapshot()),"brush redo restores all channels "+active_family)
	history=editor._doc._undo.size()
	await call_tool("paint_surface",arguments.merged({"mapping":"invalid"},true),false)
	await call_tool("paint_surface",arguments.merged({"material_id":"pack:default:does_not_exist"},true),false)
	check(equivalent(painted,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"invalid materials/mapping have no side effects "+active_family)
	var row:Dictionary={"id":active_family,"material":channels[active_family],"captures":[],"http":true}
	var with_house:bool=active_family in ["roofs/terracotta_plain","roofs/terracotta_warm","walls/earthen_plaster"]
	if with_house:
		row.house=await paint_house(active_family)
		if row.house.is_empty():row.passed=false;evidence.items.append(row);flush();return
	var expected:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("save_world",{"path":map_path,"background":true})
	while editor.saving():await process_frame
	check(editor._save_job.result.get("saved",false),"actual native reference map save "+active_family)
	await call_tool("open_world",{"path":map_path});await ready_editor()
	check(equivalent(expected.records,editor._doc.records) and equivalent(expected.map_meta,editor._doc.map_meta) and Paint.missing(editor._doc.records).is_empty(),"save/reopen retains complete geometry/material/channel state "+active_family)
	row.map_path=map_path;row.map_sha256=FileAccess.get_sha256(map_path)
	row.captures.append(await capture_webp("panel_front",Vector3(28,1.5,8),Vector3(28,1.5,0),4.6))
	row.captures.append(await capture_webp("panel_raking",Vector3(31.7,2.8,6),Vector3(28,1.5,0),3.8,true))
	row.captures.append(await capture_webp("panel_macro",Vector3(29.1,2.2,4),Vector3(28,1.5,0),1.55,true))
	if with_house:
		row.captures.append(await capture_webp("house_near",Vector3(19,13,-24),Vector3(0,3.9,-.2),18.8))
		row.captures.append(await capture_webp("house_mid",Vector3(19,13,-24),Vector3(0,3.9,-.2),32.))
		row.captures.append(await capture_webp("house_far",Vector3(19,13,-24),Vector3(0,3.9,-.2),55.))
		row.captures.append(await capture_webp("roof_detail",Vector3(12,16,4),Vector3(1.6,8.4,0),5.2,true))
		row.captures.append(await capture_webp("facade_detail",Vector3(12,7,-16),Vector3(-.2,3.5,-5.7),7.,true))
	row.passed=failed==before_failures;put(current_folder.path_join("report.json"),row);evidence.items.append(row);flush()

func run()->void:
	if "--syntax-only" in OS.get_cmdline_user_args():print("HOUSE_SURFACE_RELIEF syntax only");quit();return
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="):variant=arg.trim_prefix("--variant=")
		if arg.begins_with("--label="):output_label=arg.trim_prefix("--label=")
		if arg.begins_with("--only="):chosen=arg.trim_prefix("--only=").split(",",false)
		if arg.begins_with("--candidates="):candidates=JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--candidates=")))
	if DisplayServer.get_name()=="headless" or variant not in ["baseline","candidate"] or (not output_label.is_empty() and not output_label.is_valid_filename()):push_error("Private GPU runner and valid variant/label required");quit(2);return
	Engine.max_fps=60;rpc_timeout_ms=240000;root.size=Vector2i(1440,1000);root.content_scale_size=root.size
	create_timer(3600).timeout.connect(func():evidence.timeout=true;flush();quit(2))
	prepare_fixture();if failed>0:flush();quit(1);return
	await setup_editor();if failed>0:flush();quit(1);return
	for item:Dictionary in inventory.items:
		if not chosen.is_empty() and not item.id in chosen:continue
		await review_family(item)
		if failed>0:break
	editor._mcp.stop();editor.queue_free();await settle()
	root.get_node("AssetManager").content_root_override=previous_override
	for path:String in guards:check(FileAccess.get_sha256(path)==guards[path],"formal/source file remains unchanged "+path.get_file())
	evidence.erase("active");evidence.completed=true;flush()
	print("HOUSE_SURFACE_RELIEF complete failures=",failed);quit(0 if failed==0 else 1)
