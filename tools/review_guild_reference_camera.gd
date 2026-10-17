extends "res://tools/review_guild_full_batch.gd"
## Reference-focused cameras with a recorded reflection environment. No maps/library writes.
const Components = preload("res://scripts/world3d/model_components.gd")
const Fixtures = preload("res://scripts/world3d/building_fixtures.gd")
var review_kind := "building"
var requested_views:PackedStringArray=[]
class ReviewWeather extends Node:
	var values:Dictionary={"time_hours":12.0}
	var night_sky:Dictionary={"ready":false}

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with('--source='):source=arg.trim_prefix('--source=')
		if arg.begins_with('--out='):out=arg.trim_prefix('--out=')
		if arg.begins_with('--kind='):review_kind=arg.trim_prefix('--kind=')
		if arg.begins_with('--views='):requested_views=arg.trim_prefix('--views=').split(',')
	if DisplayServer.get_name()=='headless':print('REFERENCE_REVIEW_SYNTAX_OK');quit();return
	if not out.replace('\\','/').begins_with('D:/code/rmmo_runtime/review_artifacts/guild_reference_recheck_20261013/') or not FileAccess.file_exists(source):quit(2);return
	create_timer(600).timeout.connect(func():push_error('REFERENCE_REVIEW_TIMEOUT');quit(124))
	var digest:=FileAccess.get_sha256(source)
	var doc:=GLTFDocument.new();var state:=GLTFState.new()
	if doc.append_from_file(source,state)!=OK:quit(1);return
	var lod:=preload("res://scripts/world3d/model_lod_preparation.gd").prepare(state)
	var scene:Node=Io.generate_scene(doc,state);doc=null;state=null
	await review_one(scene,{"id":source.get_file().get_basename(),"path":source,"sha256":digest},out)
	report.lod_derivation=lod
	report.runtime_implementation={}
	for path in ['model_components.gd','runtime_mesh_cache.gd','streetlamp_lights.gd','tinted_glass.gd']:
		report.runtime_implementation[path]=FileAccess.get_sha256('res://scripts/world3d/'+path)
	check(report.get('gallery_completed',false),'all requested reference cameras completed')
	check(FileAccess.get_sha256(source)==digest,'source immutable')
	report.passed=report.failures.is_empty();put(out.path_join('report.json'),report)
	print('REFERENCE_REVIEW_COMPLETE ',review_kind,' passed=',report.passed);quit(0 if report.passed else 1)

func gallery(scene:Node,folder:String)->void:
	var vp:=SubViewport.new();vp.size=Vector2i(1400,1000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=false;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(scene)
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.12,.15,.18)
	var sky:=Sky.new();var sm:=ProceduralSkyMaterial.new();sm.sky_top_color=Color(.25,.38,.57);sm.sky_horizon_color=Color(.72,.76,.80);sm.ground_bottom_color=Color(.18,.16,.13);sm.ground_horizon_color=Color(.65,.65,.64);sky.sky_material=sm;env.sky=sky
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY;env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.22
	env.tonemap_mode=Environment.TONE_MAPPER_ACES;env.tonemap_exposure=1;env.ssao_enabled=true;env.ssao_radius=.7;env.ssao_intensity=1.2
	var world:=WorldEnvironment.new();world.environment=env;vp.add_child(world)
	# Local room reflections distinguish metal from a uniform sky reflection.
	# This is a recorded material review environment, not baked asset lighting.
	if review_kind=='building':
		var probe:=ReflectionProbe.new();probe.position=Vector3(16,4,-7);probe.size=Vector3(33,9,15)
		probe.interior=true;probe.box_projection=true;probe.max_distance=40
		probe.ambient_mode=ReflectionProbe.AMBIENT_COLOR;probe.ambient_color=Color.WHITE;probe.ambient_color_energy=.22
		probe.name='ReviewRoomReflection';vp.add_child(probe)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-28,0);sun.light_energy=1.5;sun.shadow_enabled=true;sun.directional_shadow_max_distance=500;vp.add_child(sun)
	var cam:=Camera3D.new();cam.current=true;cam.near=.02;cam.far=1000;vp.add_child(cam)
	var wd:=preload("res://scripts/world3d/world_document.gd").new();wd._namespace_asset(scene,'reference_review',scene);Components.apply(scene,{"kind":"asset","uuid":"reference_review"})
	var winds:Array=[];var all:Array=[];gather(scene,all)
	var original_pose:Dictionary={}
	for node in all:
		if not node is MeshInstance3D or node.mesh==null:continue
		preload("res://scripts/world3d/streetlamp_lights.gd").register(node)
		original_pose[node]=node.transform
		var cfg:Dictionary=node.get_meta('extras',{}).get('rmmo_wind',{})
		if cfg.is_empty():continue
		for slot in node.mesh.get_surface_count():
			var mat:=node.get_active_material(slot) as StandardMaterial3D
			if mat==null:continue
			var wind:=Wind.make(mat,cfg,node.get_aabb());node.set_surface_override_material(slot,wind);winds.append(wind)
	var weather:=ReviewWeather.new();vp.add_child(weather)
	var lights:=preload("res://scripts/world3d/streetlamp_lights.gd").new();vp.add_child(lights);lights.weather=weather;lights.camera=cam
	var views:Array=[]
	if review_kind=='building':
		views=[
			['near',[43,23,31],[16,5,-6],45],['medium',[54,31,47],[16,5,-6],45],['far',[82,43,80],[16,5,-6],45],
			['facade_front',[16,6.5,32],[16,5.5,0],50],['entry_closed',[16,2.4,8],[16,1.7,0],46],['entry_open',[20,3.7,9],[16,1.6,0],51],
			['banner',[19.8,7.7,8.6],[16,6.5,1.5],43],['roof_join',[21,15,11],[16,9,-.6],45],['rear',[-14,22,-38],[16,5,-6],45],
			['lantern_detail',[13.15,2.15,2.0],[13.68,2.06,.68],40],['lantern_detail_night',[13.15,2.15,2.0],[13.68,2.06,.68],40],
			['rose_front',[16.6,9.6,4.0],[16,9.4,.475],44],['rose_backlight',[16,9.4,-2.0],[16,9.4,.475],52],
			['stone_close',[19.4,2.0,2.0],[18.6,2.0,-.01],42],['stone_raking',[20.8,2.0,.9],[18.6,2.0,-.01],42],
			['roof_material',[21,12.3,6.1],[23,9.8,-1.2],34],
			['roof_detail',[22.3,11.8,3.1],[23,9.8,-1.2],34],['roof_side',[26,11.4,.9],[23,9.8,-1.2],34],
			['bone_detail',[17.9,10.9,-3.8],[16,10.8,-5.8],50],['pedestal_detail',[18.5,1.4,-4.9],[16,.75,-7.3],50],
			['linen_detail',[22.9,6.25,-1.9],[24.15,5.0,-3.25],50],['dining_wood',[8.8,1.45,-2.6],[7,.79,-4.2],50],
			['crystal_front',[24.7,1.88,-8.95],[24.65,1.75,-10.4],35],['crystal_side',[26,1.92,-9.7],[24.65,1.75,-10.4],35],
			['hall_reference',[18,1.7,-2.2],[12.3,3.2,-8.8],72],['hall_roof',[18,2.4,-4.0],[14,7.5,-8],75],
			['reception',[27.5,2.1,-4.5],[23.8,2,-9.3],76],['reception_oblique',[29,1.8,-7.5],[23.8,2.2,-11],68],
			['quest_mount',[25,2.6,-5.2],[21.8,2,-8],55],['fanlight',[24.5,2.5,-7.3],[24.65,2.9,-10.9],38],
			['crystal',[25.6,2.25,-8.6],[24.65,1.67,-10.4],42],['stair',[12.5,1.7,-9.9],[3,5,-9.9],66],
			['guest',[24.7,6.15,-1.0],[22.8,5.5,-3.4],76],['guest_night',[24.7,6.15,-1.0],[22.8,5.5,-3.4],76],
			['hall_night',[18,1.7,-2.2],[12.3,3.2,-8.8],72]
		]
		if 'entry_closed_no_ssao' in requested_views:views.append(['entry_closed_no_ssao',[16,2.4,8],[16,1.7,0],46])
		if 'entry_closed_no_sun_shadow' in requested_views:views.append(['entry_closed_no_sun_shadow',[16,2.4,8],[16,1.7,0],46])
	elif review_kind=='tower':
		views=[['near',[14,32,18],[0,27.3,0],50],['medium',[45,35,60],[0,16.685,0],50],['far',[90,65,135],[0,16.685,0],50],['horn',[10,28,6],[4.8,25.9,0],50],['dormer',[7.2,29.4,0],[2.8,29.1,0],34],['back',[-14,32,-18],[0,27.3,0],50]]
	else:
		var bounds:=scene_bounds(scene);var center:=bounds.get_center();var radius:=maxf(.1,bounds.size.length()*.5);var distance:=radius/sin(deg_to_rad(20))*1.12
		for spec in [['near',Vector3(.8,.45,1.5),1.],['medium',Vector3(.8,.45,1.5),1.8],['far',Vector3(.8,.45,1.5),3.],['back',Vector3(-.8,.45,-1.5),1.],['highlight',Vector3(-.8,.25,1.5),1.]]:
			views.append([spec[0],vec(center+spec[1].normalized()*distance*spec[2]),vec(center),40])
		if 'crystal' in source:views.append(['detail',vec(center+Vector3(.30,.22,.55)),vec(center+Vector3(0,.10,0)),55])
		if 'lamp' in source or 'lantern' in source or 'candle' in source or 'crystal' in source:
			views.append(['near_night',vec(center+Vector3(.8,.45,1.5).normalized()*distance),vec(center),40])
		var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(radius*8,radius*8);ground.mesh=plane;ground.position=Vector3(center.x,bounds.position.y-.02,center.z);var gm:=StandardMaterial3D.new();gm.albedo_color=Color(.23,.25,.27);gm.roughness=1;ground.material_override=gm;vp.add_child(ground)
	report.review_environment={"size":[1400,1000],"msaa":4,"taa":false,"tone":"ACES","exposure":1,"ambient_day":.22,"ambient_night":.045,"sun_day":1.5,"sun_rotation":[-38,-28,0],"reflection":"procedural sky + one interior room probe at 16,4,-7 size 33,9,15 for building","ssao_radius":.7,"ssao_intensity":1.2,"lighting_scope":"bounded review rig and production nearby light controller; final map GI/exposure is separate"}
	report.screenshots=[]
	for view in views:
		if not requested_views.is_empty() and not view[0] in requested_views:continue
		env.ssao_enabled=view[0]!='entry_closed_no_ssao'
		sun.shadow_enabled=view[0]!='entry_closed_no_sun_shadow'
		# A backlit window must see the daylight sky, not the neutral studio
		# clear colour used for exterior silhouette comparisons.
		env.background_mode=Environment.BG_SKY if view[0]=='rose_backlight' else Environment.BG_COLOR
		var night:bool='night' in view[0];weather.values.time_hours=22.0 if night else 12.0;env.ambient_light_energy=.045 if night else .22;sun.light_energy=.015 if night else 1.5
		var room_probe:=vp.get_node_or_null('ReviewRoomReflection') as ReflectionProbe
		if room_probe!=null:room_probe.ambient_color_energy=.045 if night else .22
		for mesh in original_pose:
			mesh.transform=original_pose[mesh]
			if str(view[0]).begins_with('entry_closed'):
				var f:Dictionary=mesh.get_meta('extras',{}).get('fixture',{})
				if not f.is_empty():mesh.transform=Fixtures.pose(mesh.transform,f,-float(f.open))
		cam.position=vector(view[1]);cam.fov=view[3];cam.look_at(vector(view[2]));lights.refresh()
		var poses:Array=[['still',0.0,Vector3.ZERO]]
		if view[0]=='banner' or (review_kind=='prop' and view[0]=='near' and not winds.is_empty()):poses.append_array([['wind1',1.,Vector3(3,0,1)],['wind4',4.,Vector3(3,0,1)]])
		for pose in poses:
			for mat in winds:mat.set_shader_parameter('wind_time',pose[1]);mat.set_shader_parameter('wind_velocity',pose[2])
			for frame in 24:await process_frame;await RenderingServer.frame_post_draw
			var filename:String=view[0]+'_'+pose[0]+'.png';check(vp.get_texture().get_image().save_png(folder.path_join(filename))==OK,'capture '+filename)
			report.screenshots.append({"name":filename,"eye":view[1],"aim":view[2],"fov":view[3],"wind_time":pose[1],"draw_calls":RenderingServer.viewport_get_render_info(vp.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),"triangles":RenderingServer.viewport_get_render_info(vp.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),"nearby_lights":lights.lights.filter(func(l):return l.visible).size()})
	report.gallery_completed=true
	vp.remove_child(scene);vp.queue_free()
	for frame in 8:await process_frame;await RenderingServer.frame_post_draw
