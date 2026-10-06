extends "res://tools/test_world3d_mcp.gd"
const Settings=preload("res://scripts/world3d/environment_settings.gd")
const Cycle=preload("res://scripts/world3d/celestial_cycle.gd")
const Authority=preload("res://scripts/net/server/sky_module.gd")
const Client=preload("res://scripts/world3d/night_sky.gd")
const Lightning=preload("res://scripts/world3d/lightning_runtime.gd")
const Net=preload("res://scripts/net/net.gd")
const Review=preload("res://scripts/asset/art_paths.gd")

func run() -> void:
	create_timer(170).timeout.connect(func():quit(2))
	logic_checks()
	root.size=Vector2i(1280,800); root.content_scale_size=root.size
	var directory:=Paths.cache_directory("environment_upgrade_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	var path:=directory.path_join("map.gltf"); var doc:=Doc.new()
	doc.add_box("ground",Vector3(0,-.2,0),Vector3(40,.4,40))
	doc.add_box("roof",Vector3(0,3.2,0),Vector3(6,.25,6))
	for x in [-3.,3.]:doc.add_box("wall",Vector3(x,1.5,0),Vector3(.2,3.,6.))
	doc.add_box("wall",Vector3(0,1.5,-3),Vector3(6.,3.,.2))
	doc.save(path); Net.session().world3d_editor_doc=doc; Net.session().world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"upgrade starts real HTTP MCP")
	var discovered:=await rpc("tools/list"); var schema:Dictionary=discovered.result.tools.filter(func(t):return t.name=="set_environment")[0].inputSchema.properties
	check(schema.has("celestial_cycle") and schema.has("surface_wetness") and schema.has("thunder_enabled") and schema.lightning_radius.maximum==2000,"HTTP discovers all new environment controls")
	var previous:=doc.recovery_snapshot(); var history:int=doc._undo.size()
	for invalid in [{"celestial_cycle":1},{"initial_wetness":1.1},{"wetting_seconds":0},{"drying_seconds":29},{"puddle_strength":-1},{"thunder_enabled":"yes"},{"lightning_center":[0,0]},{"lightning_radius":2001}]: await call_tool("set_environment",invalid,false)
	check(doc.recovery_snapshot()==previous and doc._undo.size()==history,"invalid upgrade calls have no document or undo side effects")
	var changes:Dictionary={"celestial_cycle":true,"time_hours":18.,"surface_wetness":true,"initial_wetness":.9,"wetting_seconds":15.,"drying_seconds":45.,"puddle_strength":.8,"thunder_enabled":true,"lightning_center":[10.,0.,20.],"lightning_radius":250.,"environment_audio":true}
	await call_tool("set_environment",changes)
	check(doc._undo.size()==history+1 and editor._environment_panel.form.fields.initial_wetness.value==.9,"one transaction updates environment UI")
	await call_tool("undo"); await call_tool("redo"); await call_tool("save_world"); await call_tool("open_world",{"path":path,"discard_changes":true}); await settle()
	check(Settings.resolve(editor._doc.map_meta).initial_wetness==.9 and Settings.resolve(editor._doc.map_meta).lightning_radius==250.,"upgrade settings survive undo/redo and save/reopen")
	var rig=editor._weather; rig.set_process(false); rig.precipitation.set_physics_process(false)
	rig.configure(Settings.updated({}, {"weather":"rain","weather_intensity":1.,"weather_transition":0.,"wetting_seconds":10.}),true)
	rig._process(10.); check(absf(rig.wetness-(1.-exp(-1.)))<.001,"local rain gradually wets surface")
	rig.configure(Settings.updated({}, {"weather":"clear","weather_transition":0.,"drying_seconds":30.}))
	var wet:float=rig.wetness; rig._process(30.)
	check(absf(rig.wetness-wet*exp(-1.))<.001,"clear weather locally dries previously wet ground")
	editor._camera.position=Vector3(0,1.5,0); await physics_frame; await physics_frame
	rig.shelter_tick=0.; rig._physics_process(.2); rig._process(.1)
	check(rig.roof_cover==1. and rig.enclosure>0. and rig.enclosure<rig.enclosure_target,"indoor mix approaches enclosure gradually")
	var indoors:float=rig.enclosure
	editor._camera.position=Vector3(10,1.5,0); rig.shelter_tick=0.; rig._physics_process(.2); rig._process(.1)
	check(rig.roof_cover==0. and rig.enclosure>0. and rig.enclosure<indoors,"leaving doorway fades rather than snaps ambience")
	await lightning_checks(rig)
	if DisplayServer.get_name()!="headless": await visuals(rig)
	editor.queue_free(); await settle(); Net.session().world3d_editor_doc=null; Net.session().world3d_editor_path=""
	if failed==0: Io._remove_tree(directory)
	print("test_world3d_environment_upgrade: "+("PASS" if failed==0 else "FAIL")); quit(0 if failed==0 else 1)

func logic_checks() -> void:
	for hour in [0.,5.,6.,8.,12.,16.,17.,18.,20.,24.]:
		var a:=Cycle.sample(hour-.001); var b:=Cycle.sample(hour+.001)
		check(a.sun_direction.distance_to(b.sun_direction)<.001 and absf(a.sun_energy-b.sun_energy)<.006,"continuous lighting around hour %.1f"%hour)
	check(Cycle.sample(12.).sun_direction.y>.9 and Cycle.sample(0.).moon_direction.y>.9,"sun and moon traverse opposite sky hemispheres")
	var authority:=Authority.new(); authority.configure("test",1,0.)
	var event:Dictionary={"id":"strike","start_at":100.,"position":[0.,0.,0.],"seed":9876,"energy":1.,"height":90.}
	check(authority.lightning("test",event),"server issues positioned seeded lightning")
	var prior:Array=authority.maps.test.lightning_events.duplicate(true)
	check(not authority.lightning("test",event.merged({"id":"bad","height":1000.},true)) and authority.maps.test.lightning_events==prior,"invalid strike cannot mutate authority")
	var snapshot:=authority.snapshot("test",102.)
	check(snapshot.lightning_events.size()==1 and not snapshot.has("surface_water") and not snapshot.has("wetness"),"snapshot retains travelling thunder and contains no runtime wetness")
	var client:=Client.new(); check(client.receive(snapshot,"test",1.,1.),"client validates full spatial strike")
	var bad:=authority.snapshot("test",103.); bad.lightning_events[0].position=[NAN,0.,0.]
	check(not client.receive(bad,"test",2.,2.) and client.snapshot==snapshot,"invalid strike rejects snapshot atomically")
	check(is_equal_approx(Lightning.arrival(event,Vector3(343,0,0)),101.) and is_equal_approx(Lightning.arrival(event,Vector3(1029,0,0)),103.),"thunder arrival depends on listener distance")
	check(Lightning.geometry(9876,90.).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==Lightning.geometry(9876,90.).surface_get_arrays(0)[Mesh.ARRAY_VERTEX],"server seed reproduces exact bolt geometry")

func lightning_checks(rig:Node) -> void:
	var authority:=Authority.new(); authority.configure("review",1,0.)
	var event:Dictionary={"id":"sound-test","start_at":100.,"position":[0.,0.,0.],"seed":13,"energy":1.,"height":90.}
	authority.lightning("review",event); var packet:=authority.snapshot("review",100.)
	var effect:Node=rig.lightning
	var ambient:=AudioServer.get_bus_index("Ambient"); var muted:=AudioServer.is_bus_mute(ambient); AudioServer.set_bus_mute(ambient,true)
	effect.advance(packet,100.02,Vector3(343,0,0),0.,true,true)
	check(effect.bolt.visible and effect.light.light_energy>0. and effect.sound_count==0,"visible world-space flash precedes sound")
	effect.advance(packet,101.,Vector3(343,0,0),.8,true,true)
	check(not effect.bolt.visible and effect.sound_count==1,"distance-delayed thunder starts after flash with indoor attenuation")
	effect.advance(packet,101.05,Vector3(343,0,0),.8,true,true)
	check(effect.sound_count==1,"repeated snapshot does not replay thunder")
	effect.reset(); effect.advance(packet,105.,Vector3(343,0,0),0.,true,true)
	check(effect.sound_count==1,"late join skips thunder which already passed")
	effect.reset(); AudioServer.set_bus_mute(ambient,muted)

func capture() -> Image:
	await settle(); await RenderingServer.frame_post_draw
	return editor._canvas.get_child(0).get_texture().get_image()

func region(image:Image,point:Vector2) -> Color:
	var result:=Color(0,0,0,0)
	for y in range(-6,7):
		for x in range(-6,7): result+=image.get_pixel(clampi(int(point.x)+x,0,image.get_width()-1),clampi(int(point.y)+y,0,image.get_height()-1))
	return result/169.

func visuals(rig:Node) -> void:
	var roof:Node3D=editor._view.get_node(NodePath(editor._doc.records[1].uuid)); roof.hide()
	editor._camera.position=Vector3(0,24,12); editor._camera.look_at(Vector3.ZERO)
	var config:=Settings.updated({}, {"time_hours":15.,"weather_transition":0.,"initial_wetness":0.,"surface_wetness":true})
	rig.configure(config,true); rig._process(0.)
	# Incremental sky reflections need to converge before image comparisons.
	for i in 80: await process_frame
	var dry:=await capture()
	rig.configure(config.merged({"initial_wetness":1.},true),true); rig._process(0.)
	for i in 80: await physics_frame
	var wet:=await capture()
	var outside:Vector2=editor._camera.unproject_position(Vector3(8,0,0)); var inside:Vector2=editor._camera.unproject_position(Vector3.ZERO)
	var outside_change:float=absf(region(dry,outside).get_luminance()-region(wet,outside).get_luminance())
	var inside_change:float=absf(region(dry,inside).get_luminance()-region(wet,inside).get_luminance())
	print("wet GPU delta exposed=%.5f covered=%.5f receivers=%d"%[outside_change,inside_change,rig.wet_surfaces.receivers.size()])
	check(outside_change>.005 and inside_change<.003,"GPU wets exposed ground while hidden roof collision keeps inside dry")
	dry.save_png(Review.review_path("weather3d/surface_dry.png")); wet.save_png(Review.review_path("weather3d/surface_wet.png"))
	rig.wet_surfaces.enabled=false; rig.wet_surfaces.clear()
	check(rig.wet_surfaces.receivers.is_empty(),"disabling wetness removes instance overlays")
	for i in 20: await process_frame
	var restored:=await capture()
	check(absf(region(dry,outside).get_luminance()-region(restored,outside).get_luminance())<.005,"original PBR material restores exactly after wet overlay removal")
	roof.show(); editor._camera.position=Vector3(13,7,15); editor._camera.look_at(Vector3(0,1,0))
	for hour in [5.5,8.,18.,22.]:
		rig.configure(Settings.updated({}, {"celestial_cycle":true,"time_hours":hour,"weather_transition":0.}),true); rig._process(0.)
		var image:=await capture(); image.save_png(Review.review_path("weather3d/cycle_%s.png"%str(hour)))
	var authority:=Authority.new(); authority.configure("bolt",1,0.)
	check(authority.lightning("bolt",{"id":"review-bolt","start_at":100.,"position":[0.,0.,-30.],"seed":918,"energy":1.,"height":70.}),"GPU review accepts spatial bolt")
	editor._camera.position=Vector3(20,8,30); editor._camera.look_at(Vector3(0,20,-30))
	rig.lightning.advance(authority.snapshot("bolt",100.),100.02,editor._camera.global_position,0.,true,false)
	for i in 25: await process_frame
	check(rig.lightning.bolt.visible and rig.lightning.light.light_energy>0.,"world bolt persists at fixed review timestamp")
	var bolt_image:=await capture(); bolt_image.save_png(Review.review_path("weather3d/lightning_spatial.png"))
	rig.lightning.bolt.hide(); var no_bolt:=await capture()
	var bright:=0
	for y in bolt_image.get_height()/2:
		for x in bolt_image.get_width():
			if bolt_image.get_pixel(x,y).get_luminance()-no_bolt.get_pixel(x,y).get_luminance()>.1: bright+=1
	check(bright>30,"GPU renders glowing lightning core and branches")
