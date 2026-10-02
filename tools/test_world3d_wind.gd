extends "res://tools/test_world3d_mcp.gd"
const Settings = preload("res://scripts/world3d/environment_settings.gd")
const Response = preload("res://scripts/world3d/wind_response.gd")
const Net = preload("res://scripts/net/net.gd")
const Review = preload("res://scripts/asset/art_paths.gd")

func cloth_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array(); var uv := PackedVector2Array(); var normals := PackedVector3Array(); var indices := PackedInt32Array()
	for y in 25:
		for x in 17:
			vertices.append(Vector3(float(x)/16*1.5,float(y)/24*2.5,0)); uv.append(Vector2(float(x)/16,float(y)/24)); normals.append(Vector3.BACK)
	for y in 24:
		for x in 16:
			var i := y*17+x
			indices.append_array(PackedInt32Array([i,i+17,i+1,i+1,i+17,i+18]))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := StandardMaterial3D.new(); material.albedo_color=Color(.8,.07,.035); material.roughness=.8; material.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0,material); return mesh

func shot() -> Image:
	await settle(); await RenderingServer.frame_post_draw
	return editor._canvas.get_child(0).get_texture().get_image()

func red_center(image: Image, low: float, high: float) -> Vector2:
	var sum := Vector2.ZERO; var count := 0
	for y in range(int(image.get_height()*low),int(image.get_height()*high)):
		for x in image.get_width():
			var c := image.get_pixel(x,y)
			if c.r > c.g*1.65 and c.r > c.b*1.65 and c.r > .15: sum += Vector2(x,y); count += 1
	return sum/maxi(count,1)

func run() -> void:
	create_timer(180).timeout.connect(func():push_error("wind test timeout");quit(2))
	root.size=Vector2i(1280,800); root.content_scale_size=root.size
	var directory := Paths.external_root().path_join("__wind_test_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var metadata := FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE); metadata.store_string('{"id":"wind_test","name":"风场验收"}'); metadata.close()
	var source := Node3D.new(); source.name="FlexibleModel"
	var cloth := MeshInstance3D.new(); cloth.name="Cloth"; cloth.mesh=cloth_mesh(); source.add_child(cloth)
	var pole := MeshInstance3D.new(); pole.name="Pole"; var cylinder:=CylinderMesh.new(); cylinder.top_radius=.04; cylinder.bottom_radius=.04; cylinder.height=3
	pole.mesh=cylinder; pole.position=Vector3(-.08,1.5,0); source.add_child(pole)
	var asset_path := directory.path_join("cloth.glb"); check(Io.save_scene(source,asset_path)==OK,"create independent subdivided cloth and rigid pole"); source.free()
	var doc := Doc.new(); doc.add_box("ground",Vector3(0,-.2,0),Vector3(30,.4,30))
	var id: String=doc.add_asset({"asset_path":asset_path,"bounds_position":[-.15,0,-.1],"bounds_size":[1.7,3,.2]},Vector3.ZERO)
	var other: String=doc.add_asset({"asset_path":asset_path,"bounds_position":[-.15,0,-.1],"bounds_size":[1.7,3,.2]},Vector3(5,0,0))
	var path := directory.path_join("maps/test/map.gltf"); check(doc.save(path)==OK,"save isolated wind map")
	Net.session().world3d_editor_path=path; Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new(); while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"start actual wind HTTP MCP")
	var discovery:=await rpc("tools/list")
	var tool: Dictionary=discovery.result.tools.filter(func(t):return t.name=="set_object_properties")[0]
	check(tool.inputSchema.properties.wind.properties.profile.enum==["off","foliage","cloth"],"discover wind response schema without adding 2D tools")
	var info:=await call_tool("get_object",{"id":id})
	var mesh_path: String=info.wind_meshes.filter(func(row):return str(row.mesh).ends_with("Cloth"))[0].mesh
	var wind := {"profile":"cloth","mesh":mesh_path,"amplitude":1.2,"stiffness":.15,"anchor":"bottom","shelter":true}
	var before:=doc.recovery_snapshot(); var history:int=doc._undo.size()
	for invalid in [{"profile":"water"},{"amplitude":-1},{"amplitude":2},{"stiffness":1.1},{"anchor":"center"},{"mesh":"../../outside"},{"shelter":"yes"}]:
		var args: Dictionary=wind.merged(invalid,true)
		await call_tool("set_object_properties",{"ids":[id],"wind":args},false)
	await call_tool("set_object_properties",{"ids":[id],"wind":wind,"hidden":true},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"invalid settings and mixed transactions are atomic")
	await call_tool("set_object_properties",{"ids":[other],"locked":true})
	before=doc.recovery_snapshot(); history=doc._undo.size()
	await call_tool("set_object_properties",{"ids":[id,other],"wind":wind},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"batch rejects locked member before changing any object")
	await call_tool("set_object_properties",{"ids":[other],"locked":false})
	history=doc._undo.size(); await call_tool("set_object_properties",{"ids":[id],"wind":wind})
	check(doc._undo.size()==history+1 and doc._find(id).wind_response.profile=="cloth","wind authoring has one undo transaction")
	await call_tool("undo"); check(not doc._find(id).has("wind_response"),"undo removes response")
	await call_tool("redo"); await call_tool("select_objects",{"ids":[id]})
	check(editor._inspector.wind_panel.form.fields.profile.get_selected_metadata()=="cloth","MCP synchronizes inspector wind form")
	editor._inspector.wind_panel.form.fields.amplitude.value=.8; editor._inspector.wind_panel.apply()
	check(is_equal_approx(doc._find(id).wind_response.amplitude,.8),"UI shares validated wind operation")
	await call_tool("undo")
	await call_tool("set_environment",{"wind_speed":12,"wind_direction":0,"weather_transition":0})
	await call_tool("save_world"); await call_tool("open_world",{"path":path,"discard_changes":true})
	check(equivalent(Response.resolve(editor._doc._find(id)),wind),"save/reopen preserves target mesh, pinning and response")
	# Give newly restored GPU pipelines a frame before starting the HTTP deadline.
	await settle()
	await call_tool("select_objects",{"ids":[id]})
	var prefab:=await call_tool("save_prefab",{"name":"受风旗帜","pack_root":directory})
	await call_tool("place_asset",{"asset_id":prefab.asset_id,"position":[-5,0,0]})
	check(editor._doc._find(editor._selection_tools.ids[0]).wind_response.profile=="cloth","prefab retains wind response and independent identity")
	if DisplayServer.get_name()!="headless": await visuals(id,other,mesh_path)
	editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(path)
	var loaded:Array=await loader.finished
	var map:Node3D=loaded[0]; check(map!=null,"runtime loads wind-authored map")
	if map!=null:
		var host:=Node3D.new(); root.add_child(host); host.add_child(map)
		var Stream=preload("res://scripts/world3d/world_stream.gd")
		Stream.sync(map,host,Vector3.ZERO)
		var tagged:Array=get_nodes_in_group(Response.GROUP)
		check(tagged.size()==1 and tagged[0].get_meta("extras").rmmo_wind.profile=="cloth","streamed mesh retains targeted wind metadata")
		Stream.sync(map,host,Vector3(300,0,300)); check(get_nodes_in_group(Response.GROUP).is_empty(),"stream unload removes wind receiver")
		Stream.sync(map,host,Vector3.ZERO); check(get_nodes_in_group(Response.GROUP).size()==1,"stream reload registers receiver again")
		host.free()
	Net.session().world3d_editor_doc=null; Net.session().world3d_editor_path=""
	if failed==0:Io._remove_tree(directory)
	else:print("fixture="+directory)
	print("test_world3d_wind: "+("PASS" if failed==0 else "FAIL")); quit(0 if failed==0 else 1)

func visuals(id:String, other:String, mesh_path:String) -> void:
	editor._camera.position=Vector3(.7,1.6,8); editor._camera.look_at(Vector3(.7,1.6,0)); editor._camera.projection=Camera3D.PROJECTION_ORTHOGONAL; editor._camera.size=5
	var rig=editor._weather; rig.set_process(false)
	var runtime=rig.wind_objects; runtime.set_physics_process(false); runtime.refresh()
	var root_node:Node3D=editor._view.get_node(NodePath(id))
	var visual:MeshInstance3D=root_node.get_node(NodePath(mesh_path))
	var original_mesh:Mesh=visual.mesh; var transform:Transform3D=visual.transform
	check(visual.has_meta("wind_original") and visual.get_active_material(0) is ShaderMaterial,"wind uses instance-only GPU material")
	check(not editor._view.get_node(NodePath(other)).get_node(NodePath(mesh_path)).has_meta("wind_original"),"shared model's unmarked copy stays rigid")
	var materials:Array=runtime.receivers[visual.get_instance_id()].materials
	check(materials[0].get_shader_parameter("tint")==Response.base_material(visual,0).albedo_color,"original PBR albedo survives wind binding")
	runtime.advance(Vector3.ZERO,1)
	var calm:=await shot(); calm.save_png(Review.review_path("weather3d/wind_calm.png"))
	runtime.advance(Vector3(16,0,0),1)
	var windy:=await shot(); windy.save_png(Review.review_path("weather3d/wind_right.png"))
	check(red_center(windy,.15,.55).x>red_center(calm,.15,.55).x+5,"GPU moves the free edge downwind")
	var pin_y:float=editor._camera.unproject_position(Vector3(.75,.025,0)).y / calm.get_height()
	check(absf(red_center(windy,pin_y-.003,pin_y).x-red_center(calm,pin_y-.003,pin_y).x)<2,"pinned lower edge stays fixed")
	runtime.advance(Vector3(-16,0,0),1)
	var reversed:=await shot(); reversed.save_png(Review.review_path("weather3d/wind_left.png"))
	check(red_center(reversed,.15,.55).x<red_center(calm,.15,.55).x-5,"wind direction reversal reverses deformation")
	check(visual.mesh==original_mesh and visual.transform==transform,"source geometry, transforms and collision basis remain unchanged")
	var paint_preview:Dictionary=Response.Paint.painted_mesh(visual,[])
	check(paint_preview.ok and paint_preview.mesh.surface_get_material(0) is StandardMaterial3D,"surface painting reads authored material instead of baking wind shader")
	runtime.advance(Vector3.ZERO,4); var reset:=await shot()
	check(absf(red_center(reset,.15,.55).x-red_center(calm,.15,.55).x)<1,"zero wind restores rest pose exactly")
	visual.rotation_degrees.y=28; visual.scale=Vector3(.8,1.1,1.3)
	var rotated_calm:=await shot()
	runtime.advance(Vector3(16,0,0),1); var rotated_wind:=await shot()
	check(red_center(rotated_wind,.25,.55).x>red_center(rotated_calm,.25,.55).x+5,"rotated and nonuniform-scaled mesh still bends in world wind direction")
	visual.transform=transform
	var leaf_source:=StandardMaterial3D.new(); leaf_source.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR; leaf_source.cull_mode=BaseMaterial3D.CULL_DISABLED
	leaf_source.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST; leaf_source.roughness=.63; leaf_source.metallic=.2
	var tex_image:=Image.create(8,8,false,Image.FORMAT_RGBA8); tex_image.fill(Color(.1,.6,.1,1)); tex_image.set_pixel(0,0,Color(0,0,0,0))
	leaf_source.albedo_texture=ImageTexture.create_from_image(tex_image); leaf_source.normal_enabled=true
	var normal_image:=Image.create(4,4,false,Image.FORMAT_RGBA8); normal_image.fill(Color(.5,.5,1)); leaf_source.normal_texture=ImageTexture.create_from_image(normal_image)
	var leaf_material=preload("res://scripts/world3d/wind_material.gd").make(leaf_source,Response.defaults().merged({"profile":"foliage"},true),visual.get_aabb())
	check(leaf_material.get_shader_parameter("albedo_tex")==leaf_source.albedo_texture and leaf_material.get_shader_parameter("normal_tex")==leaf_source.normal_texture and is_equal_approx(leaf_material.get_shader_parameter("roughness"),.63),"cutout foliage retains color, normal texture and PBR values")
	var leaf:=MeshInstance3D.new(); leaf.mesh=original_mesh; leaf.material_override=leaf_material; leaf.position=Vector3(2,0,0); editor.add_child(leaf)
	leaf_material.set_shader_parameter("wind_velocity",Vector3(8,0,0)); await shot(); leaf.free()
	leaf_source.next_pass=StandardMaterial3D.new(); check(not Response.material_error(leaf_source).is_empty(),"unsupported multipass material is rejected explicitly")
	# Add an independent collider above the cloth: exposure affects only this receiver.
	var roof:=StaticBody3D.new(); roof.position=Vector3(.75,3.5,0); editor.add_child(roof)
	var shape:=CollisionShape3D.new(); var box:=BoxShape3D.new(); box.size=Vector3(3,.2,3); shape.shape=box; roof.add_child(shape)
	await physics_frame; await physics_frame; runtime.refresh(); runtime.advance(Vector3(16,0,0),2)
	check(materials[0].get_shader_parameter("wind_velocity")==Vector3.ZERO,"sheltered cloth receives no outdoor wind")
	roof.free(); await physics_frame; runtime.refresh()
	# Sky inspection captures stable celestial directions and the three authored times.
	editor._camera.projection=Camera3D.PROJECTION_PERSPECTIVE; editor._camera.rotation_degrees=Vector3(16,28,0)
	for preset in ["day","sunset","night"]:
		rig.configure(Settings.updated({}, {"preset":preset,"weather":"clear","wind_speed":6}),true); rig._process(1)
		var sky_image:=await shot(); sky_image.save_png(Review.review_path("weather3d/sky_"+preset+".png"))
		check(rig.sky_material.get_shader_parameter("night_amount")== (1.0 if preset=="night" else 0.0),"sky celestial state matches "+preset)
	await call_tool("set_object_properties",{"ids":[id],"wind":{"profile":"off"}})
	check(not editor._view.get_node(NodePath(id)).get_node(NodePath(mesh_path)).has_meta("wind_original"),"disabling wind restores original materials")
