extends "res://tools/test_world3d_mcp.gd"
const Settings = preload("res://scripts/world3d/environment_settings.gd")
const Clouds = preload("res://scripts/world3d/cloud_resources.gd")
const Authority = preload("res://scripts/net/server/sky_module.gd")
const Client = preload("res://scripts/world3d/night_sky.gd")
const Profile = preload("res://scripts/world3d/weather_profile.gd")
const Net = preload("res://scripts/net/net.gd")
const Art = preload("res://scripts/asset/art_paths.gd")
var viewport: SubViewport
var material: ShaderMaterial
var camera: Camera3D

func run() -> void:
	create_timer(220).timeout.connect(func():quit(2))
	logic_checks()
	var directory := Paths.cache_directory("cloud_test_%d"%Time.get_ticks_usec())
	var path := directory.path_join("map.gltf"); var doc := Doc.new()
	doc.add_box("ground",Vector3.ZERO,Vector3(30,.2,30)); doc.save(path)
	Net.session().world3d_editor_doc=doc; Net.session().world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"cloud authoring uses real HTTP MCP")
	var discovery:=await rpc("tools/list")
	var schema:Dictionary=discovery.result.tools.filter(func(t):return t.name=="set_environment")[0].inputSchema.properties
	check(schema.cloud_altitude.minimum==200 and schema.cloud_thickness.maximum==1800 and schema.has("cirrus_amount") and not schema.has("cloud_quality"),"3D discovery exposes shared cloud shape, excludes local quality")
	var previous:=doc.recovery_snapshot(); var history:int=doc._undo.size()
	for bad in [{"cloud_altitude":199},{"cloud_thickness":1801},{"cloud_scale":0},{"cirrus_amount":1.1},{"cloud_quality":"high"}]: await call_tool("set_environment",bad,false)
	check(previous==doc.recovery_snapshot() and history==doc._undo.size(),"invalid cloud calls leave document and undo unchanged")
	await call_tool("set_environment",{"cloud_altitude":850.,"cloud_thickness":700.,"cloud_scale":3200.,"cirrus_amount":.4})
	check(doc._undo.size()==history+1 and editor._environment_panel.form.fields.cloud_altitude.value==850.,"one cloud transaction updates inspector")
	await call_tool("undo"); check(Settings.resolve(doc.map_meta).cloud_altitude==600.,"undo restores cloud shape")
	await call_tool("redo"); await call_tool("save_world"); await call_tool("open_world",{"path":path,"discard_changes":true}); await settle()
	var saved:=Settings.resolve(editor._doc.map_meta)
	check(saved.cloud_altitude==850. and saved.cloud_thickness==700. and saved.cirrus_amount==.4,"cloud settings survive redo and save/reopen")
	check(editor._weather.cloud_resources_ready and editor._weather.sky_material.get_shader_parameter("cloud_altitude")==850.,"shared renderer receives authored clouds and external noise")
	editor.queue_free(); await settle(); Net.session().world3d_editor_doc=null; Net.session().world3d_editor_path=""
	if DisplayServer.get_name()!="headless": await visuals()
	if failed==0: Io._remove_tree(directory)
	print("test_world3d_clouds: "+("PASS" if failed==0 else "FAIL")); quit(0 if failed==0 else 1)

func logic_checks() -> void:
	var authority:=Authority.new(); authority.configure("clouds",2147483646,0.)
	check(authority.set_environment("clouds",{"cloud_altitude":900.,"cloud_thickness":650.,"cloud_scale":3500.,"cirrus_amount":.3,"wind_speed":12.},100.).ok,"mock authority accepts authored cloud volume")
	var packet:=authority.snapshot("clouds",110.); var a:=Client.new(); var b:=Client.new()
	check(a.receive(packet,"clouds",10.,10.) and b.receive(packet,"clouds",30.,30.),"different client clocks accept shared cloud state")
	check(Clouds.seed_offset(a.seed)==Clouds.seed_offset(b.seed) and Profile.drift_at(a.snapshot,10.+a.clock_offset)==Profile.drift_at(b.snapshot,30.+b.clock_offset),"cloud seed and world displacement agree across clients")
	var position:=Profile.drift_at(packet,112.)
	authority.set_environment("clouds",{"wind_direction":-120.,"weather":"storm"},112.)
	check(Profile.drift_at(authority.snapshot("clouds",112.),112.).distance_to(position)<.00001,"weather interruption preserves cloud position")
	var before:=a.snapshot.duplicate(true); packet=authority.snapshot("clouds",113.); packet.environment.cloud_altitude=-1.
	check(not a.receive(packet,"clouds",13.,13.) and a.snapshot==before,"client rejects malformed cloud shape atomically")
	check(Clouds.seed_offset(2147483646)!=Clouds.seed_offset(2147483647),"adjacent large server seeds remain distinct")
	check(Clouds.seed_offset(7321)!=Clouds.seed_offset(7321+65536),"upper server seed bits affect cloud distribution")
	var gs:=preload("res://scripts/game/game_settings.gd").new(); gs.persist_enabled=false
	gs.set_cloud_quality("high"); gs.set_cloud_quality("invalid")
	check(gs.cloud_quality=="high","local quality validates without server mutation"); gs.free()

func capture(label: String="") -> Image:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image()
	if not label.is_empty(): image.save_png(Art.review_path("clouds3d/"+label+".png"))
	return image

func difference(a:Image,b:Image) -> float:
	var total:=0.; var count:=0
	for y in range(0,a.get_height(),8):
		for x in range(0,a.get_width(),8):
			var aa:=a.get_pixel(x,y); var bb:=b.get_pixel(x,y)
			total+=absf(aa.r-bb.r)+absf(aa.g-bb.g)+absf(aa.b-bb.b); count+=3
	return total/count

func visuals() -> void:
	viewport=SubViewport.new(); viewport.size=Vector2i(1920,1080); viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var world:=WorldEnvironment.new(); world.environment=Environment.new(); viewport.add_child(world)
	world.environment.background_mode=Environment.BG_SKY
	world.environment.sky=Sky.new(); world.environment.sky.radiance_size=Sky.RADIANCE_SIZE_64
	world.environment.sky.process_mode=Sky.PROCESS_MODE_INCREMENTAL
	material=ShaderMaterial.new(); material.shader=preload("res://scripts/world3d/weather_sky.gdshader")
	check(Clouds.bind(material),"GPU uses pinned MIT noise volumes")
	world.environment.sky.sky_material=material
	camera=Camera3D.new(); viewport.add_child(camera); camera.current=true; camera.position=Vector3(0,2,0); camera.fov=75
	camera.look_at(camera.position+Vector3(0,.55,-1.))
	material.set_shader_parameter("cloud_cover",.52); material.set_shader_parameter("cloud_seed_offset",Clouds.seed_offset(7321))
	material.set_shader_parameter("sun_direction",Vector3(-.4,.6,-.7).normalized())
	material.set_shader_parameter("cirrus_amount",0.)
	var day:=await capture("day"); var repeat:=await capture()
	check(difference(day,repeat)<.0001,"static cloud field is stable with no frame randomization")
	material.set_shader_parameter("cloud_seed_offset",Clouds.seed_offset(8192)); var changed:=await capture()
	check(difference(day,changed)>.008,"server seed changes rendered cloud distribution")
	material.set_shader_parameter("cloud_seed_offset",Clouds.seed_offset(7321))
	camera.position.x=600.; var moved:=await capture("parallax")
	check(difference(day,moved)>.008,"camera translation produces cloud parallax")
	# Move the field by the same world displacement: density must line up again.
	material.set_shader_parameter("drift",Vector2(.36,0.)); var aligned:=await capture()
	print("cloud translated-field delta=%.6f"%difference(day,aligned))
	check(difference(day,aligned)<.002,"cloud advection has correct scale and world wind direction")
	camera.position.x=0.; material.set_shader_parameter("drift",Vector2.ZERO)
	material.set_shader_parameter("cloud_thickness",100.); var thin:=await capture()
	check(difference(day,thin)>.005,"cloud thickness changes integrated volume")
	material.set_shader_parameter("cloud_thickness",550.); material.set_shader_parameter("cirrus_amount",.9)
	var cirrus:=await capture("cirrus"); check(difference(day,cirrus)>.0003,"independent high thin cloud layer contributes pixels")
	material.set_shader_parameter("cloud_cover",.18); material.set_shader_parameter("cirrus_amount",.22)
	await capture("clear")
	material.set_shader_parameter("cloud_cover",.95); material.set_shader_parameter("cloud_storm",1.)
	material.set_shader_parameter("daylight",.4); var storm:=await capture("storm")
	material.set_shader_parameter("cloud_flash",Vector4(0.,0.,-1000.,1.))
	var flash:=await capture("lightning"); check(difference(storm,flash)>.002,"spatial lightning lights nearby cloud volume")
	material.set_shader_parameter("cloud_flash",Vector4.ZERO)
	material.set_shader_parameter("sun_direction",Vector3(-.3,.12,-.7).normalized())
	material.set_shader_parameter("sun_tint",Color(1.,.45,.2)); material.set_shader_parameter("dusk_amount",1.)
	material.set_shader_parameter("cloud_cover",.5); material.set_shader_parameter("cloud_storm",0.)
	material.set_shader_parameter("zenith",Color(.12,.18,.33)); material.set_shader_parameter("horizon",Color(.65,.30,.17))
	await capture("sunset")
	material.set_shader_parameter("night_amount",1.); material.set_shader_parameter("dusk_amount",0.)
	material.set_shader_parameter("zenith",Color(.004,.009,.023)); material.set_shader_parameter("horizon",Color(.02,.035,.065))
	material.set_shader_parameter("star_intensity",1.7); material.set_shader_parameter("star_seed",7321)
	await capture("night")
	material.set_shader_parameter("moon_direction",-Vector3(-.3,.12,-.7).normalized())
	material.set_shader_parameter("night_amount",.499); var dusk_before:=await capture()
	material.set_shader_parameter("night_amount",.501); var dusk_after:=await capture()
	check(difference(dusk_before,dusk_after)<.005,"opposite sun and moon blend continuously across twilight")
	material.set_shader_parameter("night_amount",0.); material.set_shader_parameter("cloud_cover",.7)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	for quality in [0,1,2]:
		material.set_shader_parameter("cloud_quality",quality)
		for i in 25: await process_frame
		await capture("quality_%d"%quality)
		var times:Array[float]=[]
		for i in 40:
			# Include ongoing sky invalidation, as in the live weather controller.
			material.set_shader_parameter("drift",Vector2(i*.00001,0.))
			await process_frame
			times.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
		times.sort(); print("GPU cloud quality=%d 1080p median_ms=%.4f p95_ms=%.4f"%[quality,times[20],times[38]])
	await scene_review(world.environment)
	viewport.queue_free(); await settle()

func scene_review(environment: Environment) -> void:
	var host:=Node3D.new(); viewport.add_child(host)
	var sun:=DirectionalLight3D.new(); host.add_child(sun)
	for row in [[Vector3(0,-.5,-50),Vector3(220,1,220)], [Vector3(-24,6,-38),Vector3(12,12,15)], [Vector3(30,10,-55),Vector3(16,20,18)], [Vector3(-8,3,-80),Vector3(20,6,15)]]:
		var mesh:=MeshInstance3D.new(); var box:=BoxMesh.new(); box.size=row[1]; mesh.mesh=box; mesh.position=row[0]
		var surface:=StandardMaterial3D.new(); surface.albedo_color=Color(.48,.46,.40); mesh.material_override=surface; host.add_child(mesh)
	camera.position=Vector3(0,8,30); camera.look_at(Vector3(0,15,-30))
	var rig:=preload("res://scripts/world3d/weather_controller.gd").new(); rig.editor_preview=true; host.add_child(rig)
	rig.bind(camera,sun,environment); rig.set_process(false); rig.set_physics_process(false)
	for preset in ["day","sunset","night"]:
		rig.configure(Settings.updated({}, {"preset":preset,"weather_transition":0.,"surface_wetness":false}),true)
		rig._process(0.)
		for i in 30: await process_frame
		await capture("scene_"+preset)
	check(rig.sky_material.get_shader_parameter("cloud_quality")==rig.cloud_quality,"production controller selects local quality")
