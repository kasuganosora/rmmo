extends "res://tools/review_axel_guild_finish.gd"
## Read-only source review; every native write is restricted to this isolated root.
const REVIEW_ROOT="D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review"
var mode:="library"
var only_id:=""

func animation_equal(a:Array,b:Array)->bool:
	# Native animation key times are float32, GLTF's resampled times are doubles.
	# Measured maximum conversion delta: 1.1127e-7 s; values and paths stay exact.
	if a.size()!=b.size():return false
	var max_delta:=0.0
	for i in a.size():
		if a[i].name!=b[i].name or a[i].length!=b[i].length or a[i].tracks.size()!=b[i].tracks.size():return false
		for t in a[i].tracks.size():
			var x:Array=a[i].tracks[t];var y:Array=b[i].tracks[t]
			if x[0]!=y[0] or x[1]!=y[1] or x[2].size()!=y[2].size():return false
			for k in x[2].size():
				if x[2][k][1]!=y[2][k][1]:return false
				max_delta=maxf(max_delta,absf(x[2][k][0]-y[2][k][0]))
	report.animation_max_key_time_delta_seconds=max_delta
	return max_delta<.000001

func animation_signature(scene:Node)->Array:
	var result:Array=[]
	for player:AnimationPlayer in scene.find_children("*","AnimationPlayer",true,false):
		for key in player.get_animation_list():
			var a:Animation=player.get_animation(key);var tracks:Array=[]
			for t in a.get_track_count():
				var keys:Array=[]
				for k in a.track_get_key_count(t):keys.append([a.track_get_key_time(t,k),var_to_str(a.track_get_key_value(t,k))])
				tracks.append([str(a.track_get_path(t)),a.track_get_type(t),keys])
			result.append({"name":str(key),"length":a.length,"tracks":tracks})
	return result

func gallery(scene:Node,folder:String)->void:
	var bounds:=scene_bounds(scene);var center:=bounds.get_center();var radius:=maxf(.08,bounds.size.length()*.5)
	var distance:=radius/sin(deg_to_rad(20))*1.12
	var viewport:=SubViewport.new();viewport.size=Vector2i(800,800);viewport.own_world_3d=true;viewport.msaa_3d=Viewport.MSAA_4X;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport);viewport.add_child(scene)
	var world:=WorldEnvironment.new();world.environment=Environment.new();var env:=world.environment
	env.background_mode=Environment.BG_COLOR;env.background_color=Color(.14,.17,.20);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_energy=.65;env.tonemap_mode=Environment.TONE_MAPPER_ACES;env.tonemap_exposure=1
	viewport.add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-28,0);sun.light_energy=1.5;sun.shadow_enabled=true;viewport.add_child(sun)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(radius*10,radius*10);ground.mesh=plane;ground.position=Vector3(center.x,bounds.position.y-.015,center.z)
	var gm:=StandardMaterial3D.new();gm.albedo_color=Color(.23,.25,.27);gm.roughness=1;ground.material_override=gm;viewport.add_child(ground)
	var cam:=Camera3D.new();cam.current=true;cam.fov=40;cam.near=.005;cam.far=1500;viewport.add_child(cam)
	var views:Array=[['near',Vector3(.8,.45,1.5).normalized(),1.0],['medium',Vector3(.8,.45,1.5).normalized(),1.8],['far',Vector3(.8,.45,1.5).normalized(),3.0],['back',Vector3(-.8,.45,-1.5).normalized(),1.0],['dark',Vector3(.8,.45,1.5).normalized(),1.0],['highlight',Vector3(-.3,.25,1.5).normalized(),1.0]]
	var players:=scene.find_children('*','AnimationPlayer',true,false)
	if not players.is_empty():views.append(['open',Vector3(.8,.45,1.5).normalized(),1.0])
	report.screenshots=[];report.animation_samples=[]
	for v in views:
		env.ambient_light_energy=.025 if v[0]=='dark' else .65;env.background_color=Color(.006,.008,.012) if v[0]=='dark' else Color(.14,.17,.20)
		sun.light_energy=.025 if v[0]=='dark' else 1.5;sun.rotation_degrees=Vector3(-20,140,0) if v[0]=='highlight' else Vector3(-38,-28,0)
		if v[0]=='open':
			for player:AnimationPlayer in players:
				for clip in player.get_animation_list():
					if 'Open' in str(clip):
						player.play(clip);player.seek(player.get_animation(clip).length,true);player.advance(0);player.pause()
						report.animation_samples.append({"clip":str(clip),"pose_sha":sha(stable(inspect(scene)).to_utf8_buffer())})
		cam.position=center+v[1]*distance*v[2];cam.look_at(center)
		for frame in 5:await process_frame;await RenderingServer.frame_post_draw
		var pic:=viewport.get_texture().get_image();check(pic.save_png(folder.path_join(str(v[0])+'.png'))==OK,'screenshot '+str(v[0]))
		report.screenshots.append({"name":v[0],"eye":vec(cam.position),"aim":vec(center),"fov":40,"draw_calls":RenderingServer.viewport_get_render_info(viewport.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),"primitives_including_review_ground":RenderingServer.viewport_get_render_info(viewport.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)})
	viewport.remove_child(scene);viewport.queue_free();await process_frame

func review_one(scene:Node,row:Dictionary,folder:String)->void:
	DirAccess.make_dir_recursive_absolute(folder)
	report={"checks":[],"failures":[],"identity":row,"generator":Compiled.generator(),"engine":Engine.get_version_info(),"scope":"Isolated native save/reopen and GPU gallery. No map integration, no measured per-model VRAM/RSS."}
	var semantic:=inspect(scene);var signature:=animation_signature(scene)
	report.semantic_sha=sha(stable(semantic).to_utf8_buffer());report.animation_signature=signature
	report.instance_triangles=semantic.instance_triangles;report.mesh_nodes=semantic.mesh_nodes;report.material_count=materials.size();report.texture_count=textures.size()
	report.texture_diagnostics=[]
	for value in textures.values():report.texture_diagnostics.append(value)
	var bounds:=scene_bounds(scene);report.bounds={"position":vec(bounds.position),"size":vec(bounds.size)}
	own(scene,scene);var packed:=PackedScene.new();check(packed.pack(scene)==OK,'PackedScene pack')
	var valid_static:bool=Compiled._valid_packed(packed);report.static_compiled_supported=valid_static
	if signature.is_empty():check(valid_static,'production static schema')
	else:report.animated_pipeline_note='Animation preserved by GLTF and native PackedScene; static cache support is reported separately, not a reason to delete animation.'
	var native_path:=folder.path_join('asset.scn');check(ResourceSaver.save(packed,native_path,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)==OK,'native save')
	scene.free();scene=null;packed=null;Drainer.synchronize_transfer()
	var reopened:PackedScene=ResourceLoader.load(native_path,'PackedScene',ResourceLoader.CACHE_MODE_IGNORE)
	if not check(reopened!=null,'native reopen'):put(folder.path_join('report.json'),report);return
	scene=reopened.instantiate();check(stable(inspect(scene))==stable(semantic),'native geometry/material/extras semantic equality');check(animation_equal(signature,animation_signature(scene)),'native animation values exact; key times within 1 microsecond')
	report.native_bytes=size_of(native_path);report.native_sha=FileAccess.get_sha256(native_path);report.native_dependencies=ResourceLoader.get_dependencies(native_path)
	check(report.native_dependencies.is_empty(),'native has no external dependencies')
	if valid_static:
		var stats:Dictionary=Footprint.measure(reopened);stats.native_uncompressed_bytes=Footprint.native_uncompressed_bytes(native_path);report.footprint_stats=stats;report.conservative_estimate=Footprint.estimate_stats(stats)
		report.pipeline_scope='Production Io.generate_scene, static validator and Footprint.measure; normal native ResourceLoader roundtrip. Compiled.read/Preparation use whole-model shared contract evidence.'
	await gallery(scene,folder)
	scene.free();reopened=null;report.passed=report.failures.is_empty();put(folder.path_join('report.json'),report)
	print('GUILD_ITEM ',mode,' ',row.id,' passed=',report.passed)
	Drainer.synchronize_transfer();await process_frame

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with('--mode='):mode=arg.trim_prefix('--mode=')
		if arg.begins_with('--only='):only_id=arg.trim_prefix('--only=')
	if DisplayServer.get_name()=='headless':print('Syntax check only');quit();return
	if mode not in ['library','assembly']:quit(2);return
	var inventory:=read_json(REVIEW_ROOT+'/inventory.json')
	if mode=='library':
		for row:Dictionary in inventory.assets:
			if not only_id.is_empty() and only_id not in row.id:continue
			# Tower has its own fixed-camera multi-LOD suite, not furniture-framed views.
			if row.id=='guild_alarm_tower_game':continue
			var folder:=REVIEW_ROOT.path_join(mode).path_join(row.id)
			var doc:=GLTFDocument.new();var state:=GLTFState.new()
			if doc.append_from_file(row.path,state)!=OK:push_error('Import failed '+row.path);continue
			var scene:Node=Io.generate_scene(doc,state);doc=null;state=null
			await review_one(scene,row,folder)
			if FileAccess.get_sha256(row.path)!=row.sha256:push_error('SOURCE MUTATED');quit(3);return
	else:
		var doc:=GLTFDocument.new();var state:=GLTFState.new();var main:Dictionary=inventory.main
		if doc.append_from_file(main.path,state)!=OK:quit(1);return
		var assembly:Node=Io.generate_scene(doc,state);doc=null;state=null
		var found:Dictionary={}
		for n in assembly.find_children('*','Node3D',true,false):
			var e:Dictionary=n.get_meta('extras',{});var id:String=e.get('asset_id','')
			if id.is_empty() or found.has(id):continue
			found[id]=true
			var clone:Node3D=n.duplicate();clone.transform=Transform3D.IDENTITY
			var row:Dictionary={"id":id,"path":main.path,"sha256":main.sha256,"assembly_node":str(assembly.get_path_to(n)),"instance_count":main.asset_groups[id].size(),"author_extras":e}
			await review_one(clone,row,REVIEW_ROOT.path_join(mode).path_join(id))
		assembly.free();check(FileAccess.get_sha256(main.path)==main.sha256,'assembly source unchanged')
	print('GUILD_BATCH_COMPLETE ',mode);quit()
