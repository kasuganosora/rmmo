extends "res://tools/test_world3d_roads.gd"
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Library=preload("res://scripts/world_editor/surface_material_library.gd")
const OUTPUT="D:/code/rmmo_runtime/review_artifacts/river_bank_lab"
const MAP="D:/code/rmmo_runtime/maps/river_bank_lab/map.gltf"
const TOWN="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const SAND="pack:default:terrain/bright_desert_sand/material"
const ROCK="pack:default:terrain/icelandic_jagged_slate/material"
var water_ids: Array=[]
var bank_ids: Array=[]
var hill_ids: Array=[]

func ground(doc, name_: String, x_center: float, steep: bool) -> String:
	var id: String=doc.add_box("grass",Vector3(x_center,0,0),Vector3(24,1,32)); var r: Dictionary=doc._find(id)
	r.editor_name=name_; r.color=[.34,.4,.23]
	r.terrain_material=Library.new().find("pack:default:terrain/mossy_grass/material")
	var heights: Array=[]; var holes: Array=[]; holes.resize(64*32); holes.fill(false)
	for z in 33:
		for x in 65:
			var distance:=absf(float(x)/64.*24.-12.)
			var t:=clampf((distance-4.5)/.75,0.,1.) if steep else smoothstep(2.,11.,distance)
			heights.append(lerpf(-4.,1.5,t))
	r.terrain_mesh={"version":1,"columns":64,"rows":32,"floor":-8,"heights":heights,"holes":holes}
	return id
func paint_record(doc, record: Dictionary, material: Dictionary) -> void:
	var n: MeshInstance3D=doc._mesh(record,false); var geometry:=Paint.geometry(n); n.free(); var entries: Array=[]
	for slot in geometry.surfaces.size():
		var surface: Dictionary=geometry.surfaces[slot]
		for face in surface.faces:
			entries.append({"mesh":".","surface":slot,"face":face,"geometry":surface.signature,"material":material.duplicate(true),"mapping":"meters","scale":[1,1],"offset":[0,0],"rotation":0})
	record.surface_paint=entries
func water(doc,x: float,width: float,name_: String) -> void:
	var id: String=doc.add_box("water",Vector3(x,-1.55,0),Vector3(width,.1,32)); var r: Dictionary=doc._find(id); r.editor_name=name_; r.collision="none"
	r.channel_mesh={"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]],"uv_origin":[x,0,0]}
	paint_record(doc,r,Library.new().find("pack:default:water/river_ripples/material")); water_ids.append(id)

func run() -> void:
	create_timer(600).timeout.connect(func():quit(2)); Engine.max_fps=60; root.size=Vector2i(1800,1200); root.content_scale_size=root.size
	DirAccess.make_dir_recursive_absolute(OUTPUT); directory=Paths.cache_directory("river_bank_lab_%d"%Time.get_ticks_usec()); map_path=directory.path_join("map.gltf")
	var town_hash:=FileAccess.get_sha256(TOWN)
	var doc:=Doc.new()
	var gentle:=ground(doc,"A 缓坡 · 水深与坡度",-48,false); var legacy:=ground(doc,"B 陡岸 · 旧算法对照",-16,true); var steep:=ground(doc,"C 陡岸 · 坡度与三向投影",16,true)
	for x in [-48,-16,16]: water(doc,x,20 if x==-48 else 10,"河流水面")
	var stone:=Library.new().find("pack:default:walls/castle_rubble/material"); check(not stone.is_empty(),"lining masonry PBR resolves")
	for side in [-1,1]:
		var id: String=doc.add_box("stone",Vector3(48+side*6.4,-1.25,0),Vector3(.8,5.5,32)); var r: Dictionary=doc._find(id); r.editor_name="D 水渠 · 垂直砌石护岸"; paint_record(doc,r,stone); bank_ids.append(id)
	var bed: String=doc.add_box("stone",Vector3(48,-4.25,0),Vector3(12,.5,32)); doc._find(bed).editor_name="D 水渠 · 砌石渠底"; paint_record(doc,doc._find(bed),stone); bank_ids.append(bed)
	water(doc,48,12,"D 水渠水面")
	var layout:=City.defaults()
	for spec in [["overview","河岸与隆起地形对照",[0,0,20],160],["gentle","A 缓坡河岸",[-48,0,0],32],["legacy","B 陡岸旧算法",[-16,0,0],32],["steep","C 陡岸修正",[16,0,0],32],["canal","D 垂直砌石水渠",[48,0,0],24],["hills","E–G 隆起缓坡 / 陡坎 / 悬崖",[0,4,48],100]]:
		layout.bookmarks.append({"id":spec[0],"name":spec[1],"camera":{"projection":"top","center":spec[2],"span":spec[3],"distance":50,"yaw":0,"pitch":-60}})
	doc.map_meta={"name":"地形材质独立验证 · 河岸 / 水渠 / 隆起悬崖","map_ref":"tests/river_bank_lab","river_bank_lab":true,"editor_layout":layout,"environment":{"preset":"day","sky_enabled":true,"sun_shadows":false,"sun_rotation":[-55,32,0],"sun_energy":1,"ambient_energy":.55,"surface_wetness":false},"editor_view":{"spawn":[0,2,59]},"spawn":[0,2,59]}
	check(doc.save(map_path)==OK,"isolated native test fixture")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new(); port=30610
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"real loopback MCP")
	var definitions: Array=(await rpc("tools/list")).result.tools
	var schema: Dictionary=definitions.filter(func(t):return t.name=="set_river_materials")[0].inputSchema
	check(schema.properties.has("bank_ids") and schema.properties.has("steep_start") and schema.properties.has("transition_width") and schema.properties.has("height_blend_strength"),"HTTP discovers slope, canal and natural transition schemas")
	check(definitions.size()==111 and definitions.any(func(t):return t.name=="set_terrain_slope_materials"),"HTTP discovers independent dry terrain slope tool")
	var args:={"terrain_ids":[gentle,steep],"sand_material_id":SAND,"rock_material_id":ROCK,"bank_profile":"natural"}
	var before: Array=editor._doc.records.duplicate(true)
	await call_tool("set_river_materials",args); var applied: Array=editor._doc.records.duplicate(true)
	await call_tool("undo"); check(equivalent(before,editor._doc.records),"natural profile atomic undo"); await call_tool("redo"); check(equivalent(applied,editor._doc.records),"natural profile redo")
	await call_tool("set_river_materials",args.merged({"terrain_ids":[legacy],"bank_profile":"depth"},true))
	before=editor._doc.records.duplicate(true)
	await call_tool("set_river_materials",{"water_ids":water_ids,"bank_ids":bank_ids,"wet_height":.3})
	applied=editor._doc.records.duplicate(true); await call_tool("undo"); check(equivalent(before,editor._doc.records),"canal/water batch undo"); await call_tool("redo"); check(equivalent(applied,editor._doc.records),"canal/water batch redo")
	await atomic_reject("set_river_materials",args.merged({"steep_start":70,"steep_end":40},true))
	await atomic_reject("set_river_materials",args.merged({"transition_width":-1},true))
	await atomic_reject("set_river_materials",args.merged({"transition_material_id":"missing"},true))
	await atomic_reject("set_river_materials",{"bank_ids":[steep]})
	await atomic_reject("set_river_materials",{"bank_ids":[bank_ids[0]],"water_ids":[water_ids[3]],"water_level":0})
	await call_tool("set_object_properties",{"ids":[bank_ids[1]],"locked":true}); await atomic_reject("set_river_materials",{"bank_ids":bank_ids,"wet_height":.8}); await call_tool("undo")
	editor._terrain_panel.refresh(steep)
	check(editor._terrain_panel.river_fields.values().bank_profile=="natural","UI shows natural slope profile")
	var r: Dictionary=editor._doc._find(steep); var n:=Terrain.normal(r,45,16)
	check(rad_to_deg(acos(absf(n.y)))>75,"actual test bank is steeper than 75 degrees")
	var wall: Dictionary=editor._doc._find(bank_ids[1]); var wall_mesh: MeshInstance3D=editor._doc._mesh(wall,false); var faces:=Paint.geometry(wall_mesh); wall_mesh.free()
	check(faces.surfaces.any(func(s):return s.faces.values().any(func(f):return absf(f.normal.y)<.001)),"canal uses real 90-degree walls")
	await build_hills()
	await call_tool("save_world"); var expected: Array=editor._doc.records.duplicate(true); await call_tool("open_world",{"path":map_path})
	check(equivalent(expected,editor._doc.records),"all profiles and lining UV survive native save/reopen")
	editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()
	await shot("overview",{"projection":"perspective","center":[0,0,20],"distance":155,"pitch":-52,"yaw":8})
	for pair in [["gentle",-48],["steep_old",-16],["steep_new",16],["canal",48]]:
		await shot(pair[0],{"projection":"perspective","center":[pair[1],-1,0],"distance":28,"pitch":-32,"yaw":24})
	var cliff_camera:={"projection":"perspective","center":[20.8,1.,0],"distance":7.5,"pitch":-23,"yaw":-70}
	await shot("edge_after",cliff_camera)
	var cliff_node: MeshInstance3D=editor._view.get_node(NodePath(steep)); var new_material: ShaderMaterial=cliff_node.get_active_material(0); var old_material: ShaderMaterial=new_material.duplicate()
	old_material.set_shader_parameter("transition_width",0.)
	cliff_node.set_surface_override_material(0,old_material); await shot("edge_before",cliff_camera); cliff_node.set_surface_override_material(0,new_material)
	await shot("hills",{"projection":"perspective","center":[0,3,48],"distance":90,"pitch":-38,"yaw":5})
	for pair in [["raised_gentle",-32],["raised_bank",0],["raised_cliff",32]]:
		await shot(pair[0],{"projection":"perspective","center":[pair[1],3,48],"distance":34,"pitch":-28,"yaw":25})
	for id in water_ids: editor._view.get_node(NodePath(id)).hide()
	await shot("canal_dry_inspection",{"projection":"perspective","center":[48,-1.5,0],"distance":22,"pitch":-35,"yaw":30})
	# Actual GPU probes: same steep geometry and height, different material rule.
	var old_color:=await probe_bank(legacy,-16,false); var new_color:=await probe_bank(steep,16,true)
	check(old_color.r>old_color.b*2 and new_color.b>new_color.r*2,"GPU legacy sand vs slope-aware rock at identical shallow depth: "+str([old_color,new_color]))
	await probe_cliff()
	var shader: ShaderMaterial=editor._view.get_node(NodePath(bank_ids[1])).get_active_material(0)
	var original_albedo: Variant=shader.get_shader_parameter("albedo_tex"); var original_tint: Variant=shader.get_shader_parameter("tint")
	shader.set_shader_parameter("albedo_tex",null); shader.set_shader_parameter("normal_strength",0.); shader.set_shader_parameter("tint",Color.WHITE)
	editor._camera.projection=Camera3D.PROJECTION_ORTHOGONAL; editor._camera.size=7; editor._camera.position=Vector3(48,-1,0); editor._camera.look_at(Vector3(54,-1,0))
	await settle(); await RenderingServer.frame_post_draw; var image: Image=editor._camera.get_viewport().get_texture().get_image()
	var dry:=pixel(image,Vector3(54,.7,0)); var wet:=pixel(image,Vector3(54,-2.5,0)); check(wet.get_luminance()<dry.get_luminance()*.9,"GPU lining darkens below waterline without a sand layer")
	shader.set_shader_parameter("albedo_tex",original_albedo); shader.set_shader_parameter("tint",original_tint)
	# Publish only the saved authored data, not temporary diagnostic material overrides.
	var saved=Doc.open_file(map_path); var destination=Doc.open_file(MAP) if FileAccess.file_exists(MAP) else Doc.new()
	check(destination!=null and (destination.records.is_empty() or destination.map_meta.get("river_bank_lab",false)),"independent lab destination")
	if destination!=null and failed==0:
		destination.records=saved.records.duplicate(true); destination.map_meta=saved.map_meta.duplicate(true); check(destination.save(MAP)==OK,"save independent user-inspectable test map")
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"runtime loads all river bank profiles")
	if loaded[0]!=null:
		var host:=Node3D.new(); root.add_child(host); host.add_child(loaded[0]); Stream.sync(loaded[0],host,Vector3(48,0,0)); await physics()
		var meshes:=Paint.meshes(loaded[0]); check(meshes.any(func(m):return m.get_active_material(0) is ShaderMaterial and m.get_active_material(0).resource_name=="Canal lining wetness"),"streamed walls retain wetness and PBR")
		check(meshes.any(func(m):return m.get_active_material(0) is ShaderMaterial and m.get_active_material(0).resource_name=="Terrain slope blend"),"streamed raised terrain retains independent slope shader")
		var space:=host.get_world_3d().direct_space_state
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(48,-1,0),Vector3(56,-1,0)))
		check(not hit.is_empty() and absf(hit.position.x-54)<.01,"vertical canal wall remains solid at correct position")
		hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(48,2,.2),Vector3(48,-8,.2)))
		check(not hit.is_empty() and absf(hit.position.y+4)<.01,"water stays non-solid and canal bed stays at -4m")
		host.queue_free(); await settle()
	check(FileAccess.get_sha256(TOWN)==town_hash,"existing town remains byte-for-byte unchanged")
	var f:=FileAccess.open(OUTPUT.path_join("result.json"),FileAccess.WRITE); f.store_string(JSON.stringify({"failures":failed,"map":MAP,"fixture":map_path,"town_sha256":town_hash,"old_sand_pixel":[old_color.r,old_color.g,old_color.b],"new_rock_pixel":[new_color.r,new_color.g,new_color.b]},"\t")); f.close()
	print("RIVER_BANK_LAB_FINISHED failures=",failed); quit(1 if failed else 0)

func build_hills() -> void:
	for spec in [["E 隆起缓坡",-32,3,10,0],["F 隆起陡坎",0,6,8,.7],["G 隆起悬崖",32,10,8,.95]]:
		var created:=await call_tool("create_terrain",{"name":spec[0],"center":[spec[1],0,48],"width":24,"depth":24,"cell_size":.375,"material_id":"pack:default:terrain/mossy_grass/material"})
		if not created.ok: return
		var id: String=created.id; hill_ids.append(id)
		await call_tool("set_terrain_slope_materials",{"terrain_ids":[id],"rock_material_id":ROCK})
		var flat: Array=editor._doc.records.duplicate(true)
		await call_tool("sculpt_terrain",{"id":id,"mode":"raise","points":[[spec[1],48]],"radius":spec[3],"strength":spec[2],"hardness":spec[4]})
		var raised: Array=editor._doc.records.duplicate(true)
		await call_tool("undo"); check(equivalent(flat,editor._doc.records),"raised terrain undo includes original flat mesh"); await call_tool("redo"); check(equivalent(raised,editor._doc.records),"raised terrain redo preserves live slope rule")
		var record: Dictionary=editor._doc._find(id); var angle:=0.
		for z in 65:
			for x in 65: angle=maxf(angle,rad_to_deg(acos(clampf(Terrain.normal(record,x,z).y,-1,1))))
		check(angle<40 if hill_ids.size()==1 else angle>65,"actual sculpted slope angle "+str(angle))
		var material: ShaderMaterial=editor._view.get_node(NodePath(id)).get_active_material(0)
		check(material.get_shader_parameter("depth_enabled")==false and material.get_shader_parameter("slope_aware")==true and material.get_shader_parameter("rock_normal")!=null,"dry terrain slope binds PBR without water-level blending")
		var height_texture: Texture2D=material.get_shader_parameter("rock_height")
		check(height_texture!=null and height_texture.get_width()==2048 and material.get_shader_parameter("soil_albedo")!=null,"GPU material binds original 2K height and transition PBR")
	var args:={"terrain_ids":hill_ids,"rock_material_id":ROCK}
	var before: Array=editor._doc.records.duplicate(true)
	await call_tool("set_terrain_slope_materials",args.merged({"steep_start":35},true)); var changed: Array=editor._doc.records.duplicate(true)
	await call_tool("undo"); check(equivalent(before,editor._doc.records),"slope batch undo"); await call_tool("redo"); check(equivalent(changed,editor._doc.records),"slope batch redo"); await call_tool("undo")
	var history: int=editor._doc._undo.size(); await call_tool("set_terrain_slope_materials",args); check(editor._doc._undo.size()==history,"same slope settings are idempotent")
	await atomic_reject("set_terrain_slope_materials",args.merged({"steep_start":70,"steep_end":60},true))
	await atomic_reject("set_terrain_slope_materials",args.merged({"edge_noise":2},true))
	await atomic_reject("set_terrain_slope_materials",args.merged({"transition_material_id":"missing"},true))
	await atomic_reject("set_terrain_slope_materials",args.merged({"rock_material_id":"absent"},true))
	await atomic_reject("set_terrain_slope_materials",args.merged({"terrain_ids":[hill_ids[0],hill_ids[0]]},true))
	await atomic_reject("set_terrain_slope_materials",{"terrain_ids":[bank_ids[0]],"rock_material_id":ROCK})
	for property in ["locked","hidden"]:
		await call_tool("set_object_properties",{"ids":[hill_ids[1]],property:true}); await atomic_reject("set_terrain_slope_materials",args.merged({"steep_start":35},true)); await call_tool("undo")
	await call_tool("set_floor_view",{"isolation":true,"base_height":30}); await atomic_reject("set_terrain_slope_materials",args); await call_tool("undo")
	editor._selection_tools.ids.clear(); editor._terrain_panel.refresh(hill_ids[2]); editor._terrain_panel.slope_fields.fields.steep_start.value=38; editor._terrain_panel._apply_slope(true)
	check(is_equal_approx(editor._doc._find(hill_ids[2]).terrain_slope_blend.steep_start,38),"UI slope form shares operation"); await call_tool("undo")
	await call_tool("set_terrain_slope_materials",{"terrain_ids":hill_ids,"enabled":false}); check(hill_ids.all(func(id):return not editor._doc._find(id).has("terrain_slope_blend")),"disable dry slope preserves sculpt geometry"); await call_tool("undo")
	var record: Dictionary=editor._doc._find(hill_ids[2]); var invalid:=record.duplicate(true); invalid.terrain_slope_blend.rock_material.normal_path="C:/outside.png"; check(not Paint.valid(invalid),"dry slope dependency cannot escape resource root")
	invalid=record.duplicate(true); invalid.terrain_slope_blend.rock_material.height_path="C:/outside.png"; check(not Paint.valid(invalid),"height map cannot escape resource root")
	var pack=preload("res://scripts/world_editor/asset_library.gd").new(directory.path_join("prefab_pack"))
	var captured:=preload("res://scripts/world_editor/prefab_library.gd").capture([record],pack,"Raised cliff")
	check(captured.ok,"prefab captures dry slope PBR dependencies")
	if captured.ok:
		var loaded:=preload("res://scripts/world_editor/prefab_library.gd").read(captured.entry)
		check(loaded.ok and loaded.records[0].terrain_slope_blend.rock_material.normal_path.contains("material_textures") and loaded.records[0].terrain_slope_blend.rock_material.height_path.contains("material_textures"),"prefab resolves dry cliff normal and height maps")

func probe_cliff() -> void:
	var node: MeshInstance3D=editor._view.get_node(NodePath(hill_ids[2])); var original: ShaderMaterial=node.get_active_material(0); var material: ShaderMaterial=original.duplicate()
	node.set_surface_override_material(0,material)
	for layer in ["base","sand","rock"]:
		material.set_shader_parameter(layer+"_albedo",null); material.set_shader_parameter(layer+"_strength",0.)
	material.set_shader_parameter("base_color",Color.GREEN); material.set_shader_parameter("rock_color",Color.BLUE)
	editor._camera.projection=Camera3D.PROJECTION_ORTHOGONAL; editor._camera.size=12; editor._camera.position=Vector3(50,5,48); editor._camera.look_at(Vector3(32,5,48))
	await settle(); await RenderingServer.frame_post_draw; var image: Image=editor._camera.get_viewport().get_texture().get_image(); image.save_png(OUTPUT.path_join("probe_dry_cliff.png"))
	# Near the rim as well as mid-wall: no flat summit grass streaks down tall faces.
	for height in [2.,5.,8.]:
		var c:=pixel(image,Vector3(39.7,height,48))
		check(c.b>c.g*2,"GPU dry near-vertical face remains rock at height "+str(height))
	editor._camera.position=Vector3(32,25,48.01); editor._camera.look_at(Vector3(32,0,48))
	await settle(); await RenderingServer.frame_post_draw; image=editor._camera.get_viewport().get_texture().get_image()
	var top_color:=pixel(image,Vector3(32,10,48)); check(top_color.g>top_color.b*2,"GPU flat raised summit preserves original grass")
	node.set_surface_override_material(0,original)

func pixel(image: Image,point: Vector3) -> Color:
	var p: Vector2=editor._camera.unproject_position(point); return image.get_pixel(clampi(roundi(p.x),0,image.get_width()-1),clampi(roundi(p.y),0,image.get_height()-1))
func probe_bank(id: String,x: float,natural: bool) -> Color:
	var node: MeshInstance3D=editor._view.get_node(NodePath(id)); var original: ShaderMaterial=node.get_active_material(0); var material: ShaderMaterial=original.duplicate()
	node.set_surface_override_material(0,material)
	for layer in ["base","sand","rock"]:
		material.set_shader_parameter(layer+"_albedo",null); material.set_shader_parameter(layer+"_strength",0.)
	material.set_shader_parameter("base_color",Color.GREEN); material.set_shader_parameter("sand_color",Color.RED); material.set_shader_parameter("rock_color",Color.BLUE)
	editor._camera.projection=Camera3D.PROJECTION_ORTHOGONAL; editor._camera.size=7; editor._camera.position=Vector3(x,-1.25,0); editor._camera.look_at(Vector3(x+4.875,-1.25,0))
	await settle(); await RenderingServer.frame_post_draw; var image: Image=editor._camera.get_viewport().get_texture().get_image(); image.save_png(OUTPUT.path_join("probe_natural.png" if natural else "probe_legacy.png"))
	var color:=pixel(image,Vector3(x+4.875,-1.25,0)); node.set_surface_override_material(0,original); return color
func shot(label_: String,camera: Dictionary) -> void:
	await call_tool("set_editor_camera",camera); await settle(); await RenderingServer.frame_post_draw
	var image: Image=editor._camera.get_viewport().get_texture().get_image(); image.save_png(OUTPUT.path_join(label_+".png"))
