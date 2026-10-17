extends "res://tools/review_axel_guild_finish.gd"
const DEST="D:/code/rmmo_runtime/review_artifacts/axel_guild_finish_20261012/repair_review"
func run()->void:
	out=DEST;case_name="filter_motion"
	var evidence:=read_json(DEST+"/final_building/candidate.json")
	var packed:PackedScene=load(evidence.native.payload)
	var scene:Node3D=packed.instantiate();root.add_child(scene)
	root.size=Vector2i(960,720);root.msaa_3d=Viewport.MSAA_4X;root.use_taa=false
	var world:=WorldEnvironment.new();world.environment=Environment.new();var env:=world.environment
	env.background_mode=Environment.BG_COLOR;env.background_color=Color(.14,.17,.20)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.65
	env.tonemap_mode=Environment.TONE_MAPPER_ACES;env.tonemap_exposure=1.0;root.add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-28,0);sun.light_energy=1.5;sun.shadow_enabled=true;root.add_child(sun)
	var cam:=Camera3D.new();root.add_child(cam);cam.current=true;cam.fov=60;cam.far=300
	report.source_sha=evidence.original_sha;report.frames=[]
	for sequence in ["roof_banner","guest_floor"]:
		DirAccess.make_dir_recursive_absolute(DEST+"/motion/"+sequence)
		for i in 32:
			var t:=float(i)/31.0
			if sequence=="roof_banner":
				cam.position=Vector3(27+2*t,12.5,13+2*t);cam.look_at(Vector3(16,8,0))
			else:
				cam.position=Vector3(28+.3*t,6.15,-1.0-.2*t);cam.look_at(Vector3(30.1,5.2,-3.5))
			for frame in 2:await process_frame
			await RenderingServer.frame_post_draw
			var path:String=DEST+"/motion/"+sequence+"/%03d.png"%i
			check(root.get_texture().get_image().save_png(path)==OK,"motion frame "+sequence+str(i))
			report.frames.append({"sequence":sequence,"frame":i,"eye":vec(cam.position),"path":path})
	report.scope="32 consecutive camera poses per sequence; current generated mips. Inspect original PNG frames; no claim of all-camera temporal stability."
	finish()
