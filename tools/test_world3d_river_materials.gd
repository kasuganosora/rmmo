extends "res://tools/test_world3d_roads.gd"
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const River=preload("res://scripts/world3d/river_materials.gd")
const SAND="pack:default:terrain/bright_desert_sand/material"
const ROCK="pack:default:terrain/icelandic_jagged_slate/material"
const OUTPUT="D:/code/rmmo_runtime/review_artifacts/river_materials"

func run() -> void:
	create_timer(480).timeout.connect(func():quit(2)); Engine.max_fps=60
	root.size=Vector2i(1600,1100); root.content_scale_size=root.size
	directory=Paths.cache_directory("river_materials_%d"%Time.get_ticks_usec()); map_path=directory.path_join("map.gltf")
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var doc:=Doc.new(); var terrains: Array=[]; var waters: Array=[]
	for z in [-8,8]:
		var id: String=doc.add_box("grass",Vector3(0,0,z),Vector3(32,1,16)); terrains.append(id)
		var r: Dictionary=doc._find(id); var heights: Array=[]; var holes: Array=[]; holes.resize(64*32); holes.fill(false)
		for zi in 33:
			for xi in 65:
				var x: float=absf(float(xi)/2-16)
				heights.append(-3.0+4.5*smoothstep(3.0,14.0,x))
		r.terrain_mesh={"version":1,"columns":64,"rows":32,"floor":-12,"heights":heights,"holes":holes}
		var water: String=doc.add_box("water",Vector3(0,-.05,z),Vector3(27,.1,16)); waters.append(water)
		var w: Dictionary=doc._find(water); w.collision="none"
		w.channel_mesh={"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]],"uv_origin":[0,0,z]}
		var m:=preload("res://scripts/world_editor/surface_material_library.gd").new().find("pack:default:water/river_ripples/material")
		var node:=doc._mesh(w,false); var geo:=Paint.geometry(node); node.free()
		var entries: Array=[]
		for face in geo.surfaces[0].faces: entries.append({"mesh":".","surface":0,"face":face,"geometry":geo.surfaces[0].signature,"material":m,"mapping":"uv","scale":[.25,.25],"offset":[0,0],"rotation":0})
		w.surface_paint=entries
	check(doc.save(map_path)==OK,"native isolated river fixture")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new(); port=30530
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"real HTTP MCP starts")
	var definitions: Array=(await rpc("tools/list")).result.tools
	check(definitions.filter(func(t):return t.name=="set_river_materials").size()==1 and definitions.all(func(t):return t.name!="paint_tile"),"discover new 3D river material operation; 2D stays disabled")
	var args:={"terrain_ids":terrains,"water_ids":waters,"water_level":0,"sand_material_id":SAND,"rock_material_id":ROCK}
	var before: Array=editor._doc.records.duplicate(true); var history: int=editor._doc._undo.size()
	await call_tool("set_river_materials",args)
	var expected: Array=editor._doc.records.duplicate(true)
	check(history+1==editor._doc._undo.size(),"whole river is one undo transaction")
	await call_tool("undo"); check(equivalent(before,editor._doc.records),"undo restores original materials")
	await call_tool("redo"); check(equivalent(expected,editor._doc.records),"redo restores all material definitions")
	history=editor._doc._undo.size(); await call_tool("set_river_materials",args)
	check(history==editor._doc._undo.size(),"idempotent apply has no history")
	for bad in [{"rock_start":3,"rock_end":2},{"shore_start":2,"shore_end":1},{"terrain_ids":[terrains[0],terrains[0]]},{"sand_material_id":"missing"},{"water_level":1},{"absorption":-1},{"terrain_ids":[waters[0]]},{"water_ids":[terrains[0]]},{"bogus":true}]:
		await atomic_reject("set_river_materials",args.merged(bad,true))
	for property in ["locked","hidden"]:
		await call_tool("set_object_properties",{"ids":[terrains[1]],property:true}); await atomic_reject("set_river_materials",args.merged({"rock_end":3},true)); await call_tool("undo")
	await call_tool("set_floor_view",{"isolation":true,"base_height":30}); await atomic_reject("set_river_materials",args); await call_tool("undo")
	var record: Dictionary=editor._doc._find(terrains[0])
	var broken:=record.duplicate(true); broken.terrain_depth_blend.sand_material.normal_path="C:/outside.png"
	check(not Paint.valid(broken),"nested material path escape rejected")
	broken=record.duplicate(true); broken.terrain_depth_blend.rock_material.normal_path=directory.path_join("absent.png")
	check(not Paint.missing([broken]).is_empty(),"missing nested normals reported")
	var state:=await call_tool("list_terrains")
	check(state.terrains[0].depth_blend.rock_end==2.2,"MCP catalog reports full persisted depth thresholds")
	editor._terrain_panel.refresh(terrains[0]); check(is_equal_approx(editor._terrain_panel.river_fields.fields.rock_end.value,2.2),"UI reads persisted thresholds")
	editor._selection_tools.ids.clear(); editor._terrain_panel.river_fields.fields.rock_end.value=2.6; editor._terrain_panel._apply_river(true)
	check(is_equal_approx(editor._doc._find(terrains[0]).terrain_depth_blend.rock_end,2.6),"UI form uses shared operation: "+str(editor._status.text)); await call_tool("undo")
	await call_tool("set_river_materials",{"terrain_ids":terrains,"water_ids":waters,"enabled":false})
	check(equivalent(before,editor._doc.records),"disable preserves original base PBR and geometry"); await call_tool("undo")
	# Sculpt does not bake a mask: actual world height drives the same saved shader.
	await call_tool("sculpt_terrain",{"id":terrains[0],"mode":"lower","points":[[0,-8]],"radius":2,"strength":.3})
	check(editor._doc._find(terrains[0]).terrain_depth_blend==record.terrain_depth_blend,"sculpt retains live depth rule"); await call_tool("undo")
	await call_tool("set_environment",{"preset":"day","sky_enabled":true,"sun_rotation":[-55,32,0],"sun_energy":1,"ambient_energy":.55})
	await call_tool("save_world"); expected=editor._doc.records.duplicate(true); await call_tool("open_world",{"path":map_path})
	check(equivalent(expected,editor._doc.records),"save and reopen preserve exact definitions")
	var node: MeshInstance3D=editor._view.get_node(NodePath(terrains[0])); var mat: ShaderMaterial=node.get_active_material(0)
	check(mat!=null and mat.get_shader_parameter("sand_normal")!=null and mat.get_shader_parameter("rock_rough")!=null,"terrain shader binds full PBR maps")
	var source_height: Texture2D=mat.get_shader_parameter("rock_height")
	check(source_height!=null and source_height.get_width()==2048 and mat.get_shader_parameter("soil_albedo")!=null,"river renderer binds original 2K height and transition textures")
	editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,-.5,0],"distance":42,"pitch":-48,"yaw":15})
	await shot("with_water")
	for id in waters: editor._view.get_node(NodePath(id)).hide()
	await shot("bed_layers")
	await call_tool("set_editor_camera",{"projection":"top","center":[3,-1,0],"span":13})
	var normals_on:=await shot("normals_on")
	mat.set_shader_parameter("sand_strength",0.); mat.set_shader_parameter("rock_strength",0.)
	var normals_off:=await shot("normals_off")
	var difference:=image_difference(normals_on,normals_off)
	check(difference>.1,"normal maps visibly change actual GPU lighting: "+str(difference))
	River.cache.clear()
	# Captured prefab includes all nested PBR textures and resolves under its pack.
	var pack=preload("res://scripts/world_editor/asset_library.gd").new(directory.path_join("prefab_pack"))
	var captured:=preload("res://scripts/world_editor/prefab_library.gd").capture([editor._doc._find(terrains[0])],pack,"River bed")
	check(captured.ok,"prefab packs river material dependencies")
	if captured.ok:
		var loaded:=preload("res://scripts/world_editor/prefab_library.gd").read(captured.entry)
		check(loaded.ok and loaded.records[0].terrain_depth_blend.sand_material.normal_path.contains("material_textures"),"prefab resolves copied sand normal")
	var scene:=Io.load_scene(map_path)
	check(scene!=null and Paint.meshes(scene).any(func(n):return n.get_active_material(0) is ShaderMaterial),"synchronous native glTF loader restores shaders"); scene.free()
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path)
	var loaded: Array=await loader.finished
	check(loaded[0]!=null,"streaming runtime accepts persisted river materials")
	if loaded[0]!=null:
		var host:=Node3D.new(); root.add_child(host); host.add_child(loaded[0]); Stream.sync(loaded[0],host,Vector3.ZERO); await physics()
		check(Paint.meshes(loaded[0]).filter(func(n):return n.get_active_material(0) is ShaderMaterial).size()==4,"streamed terrain and water retain dynamic shaders")
		var hit:=host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(.123,8,-8),Vector3(.123,-20,-8)))
		check(not hit.is_empty() and absf(hit.position.y+3)<.01,"riverbed collision is unchanged, water remains non-solid")
		host.queue_free(); await settle()
	var f:=FileAccess.open(OUTPUT.path_join("result.json"),FileAccess.WRITE); f.store_string(JSON.stringify({"failures":failed,"fixture":map_path,"normal_difference":difference},"\t")); f.close()
	print("RIVER_MATERIALS_VERIFIED failures=",failed); quit(1 if failed else 0)

func shot(label_: String) -> Image:
	await settle(); await RenderingServer.frame_post_draw
	var image: Image=editor._camera.get_viewport().get_texture().get_image(); image.save_png(OUTPUT.path_join(label_+".png")); return image

func image_difference(a: Image,b: Image) -> float:
	var total:=0.0; var count:=0
	for y in range(0,a.get_height(),4):
		for x in range(0,a.get_width(),4):
			var c:=a.get_pixel(x,y); var d:=b.get_pixel(x,y); total+=absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b); count+=3
	return total/maxi(1,count)*255
