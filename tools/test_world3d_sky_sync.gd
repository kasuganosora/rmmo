extends "res://tools/test_world3d_mcp.gd"
const Authority = preload("res://scripts/net/server/sky_module.gd")
const Client = preload("res://scripts/world3d/night_sky.gd")
const Settings = preload("res://scripts/world3d/environment_settings.gd")
const Profile = preload("res://scripts/world3d/weather_profile.gd")
const Net = preload("res://scripts/net/net.gd")
const Review = preload("res://scripts/asset/art_paths.gd")

func run() -> void:
	create_timer(170).timeout.connect(func():push_error("sky sync timeout");quit(2))
	var authority := Authority.new(); authority.rng.seed = 32
	check(authority.configure("test/map",12345678,3),"server assigns map seed and event rate")
	authority.set_environment("test/map",{"preset":"night","weather_transition":2},100)
	var first := authority.snapshot("test/map",100)
	var a := Client.new(); var b := Client.new()
	check(a.receive(first,"test/map",8,8) and b.receive(authority.snapshot("test/map",100),"test/map",500,500),"two independent clients accept one authoritative map")
	check(a.seed == b.seed and a.events == b.events,"seed and future trajectories are shared, not generated per player")
	var event: Dictionary = first.events[0]; var moment: float = event.start_at+event.duration*.5
	a.sample(moment); b.sample(moment)
	check(a.head.is_equal_approx(b.head) and a.tail.is_equal_approx(b.tail) and a.energy==b.energy and a.active_id==b.active_id,"same server time produces same meteor across client clocks")
	var late := Client.new(); late.receive(authority.snapshot("test/map",moment),"test/map",0,0); late.sample(moment)
	check(late.head.is_equal_approx(a.head) and late.active_id==a.active_id,"late join catches current event phase instead of replaying from start")
	check(not a.receive(first,"test/map",9,9) and not a.receive(authority.snapshot("test/map",moment),"other/map",9,9),"duplicate, stale and wrong-map snapshots cannot rewind client")
	var broken := authority.snapshot("test/map",moment); broken.events=[{"id":"bad","start_at":moment,"duration":1,"from":[0,0,0],"to":[0,1,0]}]
	var before := a.snapshot.duplicate(true)
	check(not a.receive(broken,"test/map",9,9) and a.snapshot==before,"malformed server events fail atomically")
	a.sample(event.start_at+event.duration+1); check(a.energy==0,"expired commands do not restart during packet loss")
	var old_map: Dictionary = authority.maps["test/map"].duplicate(true)
	check(not authority.set_environment("test/map",{"wind_speed":100},102).ok and authority.maps["test/map"]==old_map,"server validates environment before mutation")
	authority.set_environment("test/map",{"weather":"rain","wind_speed":12,"weather_transition":4},102)
	var during := authority.snapshot("test/map",103)
	var profile := Profile.at(during,103); var cloud := Profile.drift_at(during,103)
	authority.set_environment("test/map",{"weather":"snow","wind_direction":90},103)
	var interrupted := authority.snapshot("test/map",103)
	check(Profile.decode(interrupted.source_profile)==profile and Profile.drift_at(interrupted,103).is_equal_approx(cloud),"interrupted weather and wind preserve shared transition and cloud position")
	check(Profile.at(interrupted,110).snow==.7,"server-timestamped weather reaches target independent of render frame rate")
	authority.set_environment("test/map",{"weather":"storm","preset":"day"},110)
	check(not authority.snapshot("test/map",110).lightning_events.is_empty(),"lightning timing is issued by the same server timeline")
	check(authority.maps["test/map"].seed==12345678,"weather and day/night changes retain server star seed")
	authority.set_environment("test/map",{"time_hours":16.9,"time_speed":360},200)
	var clock_packet:=authority.snapshot("test/map",202)
	check(is_equal_approx(clock_packet.time_of_day_hours,17.1) and clock_packet.environment.preset=="sunset","server clock drives shared day-to-sunset boundary")
	check(is_equal_approx(clock_packet.transition_at,201),"time phase transition keeps exact server boundary timestamp")
	authority.configure("test/shower",321,0)
	var shower:Dictionary={"id":"shower-1","radiant":[0.0,.8,-.6],"start_at":300.0,"count":8,"interval":.25,"kind":"fireball","brightness":2.5}
	check(authority.meteor_shower("test/shower",shower),"server accepts concentrated fireball shower with explicit brightness")
	var shower_packet:=authority.snapshot("test/shower",300.7)
	a.reset(); b.reset(); a.receive(shower_packet,"test/shower",1,1); b.receive(shower_packet,"test/shower",44,44); a.sample(300.7); b.sample(300.7)
	check(a.meteors.size()>1 and a.meteors==b.meteors and a.meteors[0].kind=="fireball" and a.meteors[0].brightness==2.5,"multiple clients render same simultaneous event types and brightness")
	var saved_events:Array=authority.maps["test/shower"].events.duplicate(true)
	var invalid:Dictionary=shower.merged({"id":"invalid","brightness":6},true)
	check(not authority.meteor_shower("test/shower",invalid) and authority.maps["test/shower"].events==saved_events,"invalid shower is atomic")
	await editor_checks()
	print("test_world3d_sky_sync: "+("PASS" if failed==0 else "FAIL")); quit(0 if failed==0 else 1)

func editor_checks() -> void:
	root.size=Vector2i(1280,800); root.content_scale_size=root.size
	var directory:=Paths.cache_directory("sky_sync_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	var path:=directory.path_join("map.gltf"); var doc:=Doc.new(); doc.add_box("ground",Vector3(0,-.2,0),Vector3(20,.4,20)); doc.save(path)
	Net.session().world3d_editor_doc=doc; Net.session().world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"start real HTTP MCP for night sky settings")
	var discovered:=await rpc("tools/list"); var spec:Dictionary=discovered.result.tools.filter(func(t):return t.name=="set_environment")[0]
	check(spec.inputSchema.properties.has("star_intensity") and spec.inputSchema.properties.meteor_frequency.maximum==12,"3D MCP discovers shared night sky schema")
	var before:=doc.recovery_snapshot(); var history:int=doc._undo.size()
	for changes in [{"star_intensity":-1},{"star_intensity":3},{"meteor_frequency":13},{"meteor_frequency":"fast"},{"meteors_enabled":1},{"time_hours":25},{"time_speed":3601}]: await call_tool("set_environment",changes,false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"invalid sky authoring leaves document and history unchanged")
	await call_tool("set_environment",{"preset":"night","star_intensity":1.4,"meteors_enabled":true,"meteor_frequency":6})
	check(doc._undo.size()==history+1 and editor._environment_panel.form.fields.star_intensity.value==1.4,"one transaction synchronizes night sky inspector")
	await call_tool("undo"); await call_tool("redo"); await call_tool("save_world"); await call_tool("open_world",{"path":path,"discard_changes":true}); await settle()
	check(Settings.resolve(editor._doc.map_meta).meteor_frequency==6,"night sky settings survive save and reopen")
	var server=Net.server(); server.mount_world3d_sky("test/saved",path)
	check(server.snapshot_world3d_sky("test/saved").environment.star_intensity==1.4,"MockServer loads authored settings from its map registry")
	if DisplayServer.get_name()!="headless": await visuals()
	editor.queue_free(); await settle(); Net.session().world3d_editor_doc=null; Net.session().world3d_editor_path=""
	if failed==0:Io._remove_tree(directory)

func capture() -> Image:
	await settle(); await RenderingServer.frame_post_draw
	return editor._canvas.get_child(0).get_texture().get_image()

func visuals() -> void:
	var rig=editor._weather; rig.set_process(false); rig.editor_preview=false
	var authority:=Authority.new(); authority.configure("test/view",12345678,0)
	authority.set_environment("test/view",{"preset":"night","wind_speed":0,"star_intensity":1.7,"weather_transition":0},100)
	var start:=Vector3(-.18,.62,-.76).normalized(); var finish:=Vector3(.15,.45,-.88).normalized()
	check(authority.meteor("test/view",{"id":"review-meteor","start_at":100,"duration":1.2,"from":[start.x,start.y,start.z],"to":[finish.x,finish.y,finish.z]}),"server accepts scripted meteor command")
	var packet:=authority.snapshot("test/view",100.6)
	var envelope:Dictionary={"packet":packet}
	rig.bind_sky("test/view",func():return envelope.packet)
	rig.sky_poll=0; rig._process(0)
	editor._camera.position=Vector3(0,1.5,0); editor._camera.look_at(editor._camera.position+start.slerp(finish,.5)); editor._camera.fov=65
	var energies:PackedFloat32Array=rig.sky_material.get_shader_parameter("meteor_energies")
	var zeros:=PackedFloat32Array(); zeros.resize(8)
	rig.sky_material.set_shader_parameter("meteor_energies",zeros)
	var stars:=await capture(); stars.save_png(Review.review_path("weather3d/night_stars.png"))
	rig.sky_material.set_shader_parameter("meteor_energies",energies)
	var meteor:=await capture(); meteor.save_png(Review.review_path("weather3d/night_meteor.png"))
	var changed:=0; var bright:=0
	for y in meteor.get_height():
		for x in meteor.get_width():
			var s:=stars.get_pixel(x,y); var m:=meteor.get_pixel(x,y)
			if maxf(m.r-s.r,maxf(m.g-s.g,m.b-s.b))>.12:changed+=1
			if maxf(s.r,maxf(s.g,s.b))>.3:bright+=1
	check(changed>15 and changed<meteor.get_width()*meteor.get_height()/30,"GPU draws a narrow meteor trail over world-space sky")
	check(bright>40,"night sky contains visible stars")
	authority.maps["test/view"].events[0].kind="fireball"; authority.maps["test/view"].events[0].brightness=2.5
	envelope.packet=authority.snapshot("test/view",100.6); rig.sky_poll=0; rig._process(0)
	var fireball:=await capture(); fireball.save_png(Review.review_path("weather3d/night_fireball.png"))
	var orange:=0
	for y in fireball.get_height():
		for x in fireball.get_width():
			var color:=fireball.get_pixel(x,y)
			if color.r>color.b*1.5 and color.r>.6:orange+=1
	check(orange>15,"GPU fireball has a brighter warm trail and glowing head")
	envelope.packet=authority.snapshot("test/view",102); rig.sky_poll=0; rig._process(0)
	check(not Array(rig.sky_material.get_shader_parameter("meteor_energies")).any(func(v):return v>0),"expired server meteor disappears")
	authority.set_environment("test/view",{"preset":"day"},102); envelope.packet=authority.snapshot("test/view",102); rig.sky_poll=0; rig._process(0)
	check(rig.sky_material.get_shader_parameter("star_intensity")==0.0 and not Array(rig.sky_material.get_shader_parameter("meteor_energies")).any(func(v):return v>0),"server daytime suppresses celestial night effects")
	authority.configure("test/view",12345678,0)
	authority.set_environment("test/view",{"preset":"night","wind_speed":0,"weather_transition":0},300)
	check(authority.meteor_shower("test/view",{"id":"review-shower","radiant":[0,.8,-.6],"start_at":300,"count":8,"interval":.25,"kind":"meteor","brightness":1.8}),"server generates concentrated shower for GPU review")
	envelope.packet=authority.snapshot("test/view",300.7); rig.sky_poll=0; rig._process(0)
	editor._camera.look_at(editor._camera.position+Vector3(0,.8,-.6))
	var shower_image:=await capture(); shower_image.save_png(Review.review_path("weather3d/night_shower.png"))
	check(Array(rig.sky_material.get_shader_parameter("meteor_energies")).filter(func(v):return v>0).size()>1,"GPU receives simultaneous server-authored shower trails")
