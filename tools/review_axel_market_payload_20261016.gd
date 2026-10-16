extends "res://review_artifacts/town_asset_size_audit_20261011/review_lossless_candidates.gd"
## Fixed-source market A/B preparation. Explicit isolated native root only.
## Each baseline/candidate runs separately; run through the private desktop wrapper.
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Picking=preload("res://scripts/world_editor/picking_shape_cache.gd")
const Walk=preload("res://scripts/world_editor/walk_mode.gd")
const ROOT="D:/code/rmmo_runtime/review_artifacts/axel_market_optimization_20261016"
const PLAN="D:/code/rmmo_runtime/art_sources/axel_market_optimization_20261016/review_plan.json"
var asset_name:=""
var take_name:=""
var pinned:Dictionary={}

func catalog_roundtrip_same(a:Array,b:Array)->bool:
	if a.size()!=b.size():return false
	for index in a.size():
		if not a[index] is Dictionary or not b[index] is Dictionary:return false
		var left:Dictionary=a[index].duplicate(true);var right:Dictionary=b[index].duplicate(true)
		for key:String in ["bounds_position","bounds_size"]:
			if not left.get(key) is Array or not right.get(key) is Array or left[key].size()!=right[key].size():return false
			for component in left[key].size():
				var x:float=left[key][component];var y:float=right[key][component]
				if absf(x-y)>1e-12*maxf(1.,maxf(absf(x),absf(y))):return false
			left.erase(key);right.erase(key)
		# Only bounds permit JSON decimal rounding; all other fields exact.
		if left!=right:return false
	return true

func value_semantic(value:Variant,depth:int=0)->Variant:
	# Source encoded/pixel identity was proved by the CPU compactor. Do not run
	# another model-image readback/reencode pass; native A/B frames verify binding.
	if value is Texture2D:
		var id:int=value.get_instance_id()
		if not textures.has(id):textures[id]={"__texture":true,"class":value.get_class(),"width":value.get_width(),"height":value.get_height()}
		return textures[id]
	return super.value_semantic(value,depth)

func inspect(scene:Node)->Dictionary:
	var result:Dictionary=super.inspect(scene)
	var cache:=Picking.new();var rows:Array=[];var all:Array=[];gather(scene,all)
	for node:Node in all:
		if not node is MeshInstance3D or node.mesh==null:continue
		# PickingShapeCache attaches a scripted CPU cache to its input Mesh.
		# Audit a local mesh recipe so inspection cannot contaminate the native
		# source graph with runtime-only ground_cpu_cache metadata.
		var collision_mesh:Mesh=node.mesh.duplicate()
		var shape:ConcavePolygonShape3D=cache.shape_for(collision_mesh)
		check(shape!=null,"production picking shape "+str(node.name))
		if shape==null:continue
		var transform:=Transform3D.IDENTITY;var current:Node=node
		while current!=null:
			if current is Node3D:transform=current.transform*transform
			if current==scene:break
			current=current.get_parent()
		rows.append({"path":str(scene.get_path_to(node)),"transform":var_to_str(transform),"face_points":shape.get_faces().size(),"faces_sha256":sha(shape.get_faces().to_byte_array()),"backface_collision":shape.backface_collision,"layer":1|(Walk.WALK_MASK if Walk.physical(node.get_meta("extras",{})) else 0)})
	cache.clear();result.collision=rows
	return result

func create_views(_scene:Node,bounds:AABB)->Array:
	var c:=bounds.get_center();var radius:=maxf(1.,bounds.size.length()*.5)
	var distance:=radius/sin(deg_to_rad(22.))*1.12;var direction:=Vector3(.8,.42,1.6).normalized()
	var views:Array=[]
	for pair in [["near",1.],["medium",1.8],["far",3.]]:views.append({"name":pair[0],"eye":vec(c+direction*distance*pair[1]),"aim":vec(c),"fov":44.})
	views.append({"name":"back","eye":vec(c+Vector3(-.8,.38,-1.6).normalized()*distance),"aim":vec(c),"fov":44.})
	var front:=bounds.end.z;var top:=bounds.end.y;var height:=bounds.size.y
	views.append({"name":"cloth_detail","eye":[c.x+.9,top+.55,front+1.8],"aim":[c.x,top-.35,c.z],"fov":48.})
	views.append({"name":"goods_detail","eye":[c.x+.8,bounds.position.y+height*.57,front+1.4],"aim":[c.x,bounds.position.y+height*.43,c.z],"fov":54.})
	views.append({"name":"structure_detail","eye":[bounds.end.x+1.5,bounds.position.y+height*.42,front+1.3],"aim":[c.x+.45,bounds.position.y+height*.40,c.z],"fov":50.})
	return views

func draw_scene(scene:Node,views:Array)->void:
	root.size=dimensions;var vp:=SubViewport.new();vp.size=dimensions;vp.own_world_3d=true
	vp.use_taa=false;vp.msaa_3d=Viewport.MSAA_DISABLED;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(scene)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(.14,.17,.20);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.65
	env.environment.tonemap_mode=Environment.TONE_MAPPER_ACES;env.environment.tonemap_exposure=1.;vp.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-28,0);sun.light_energy=1.5;sun.shadow_enabled=true;sun.directional_shadow_max_distance=80.;vp.add_child(sun)
	var bounds:=scene_bounds(scene);var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(24,24);ground.mesh=plane
	ground.position=Vector3(bounds.get_center().x,bounds.position.y-.02,bounds.get_center().z)
	var ground_mat:=StandardMaterial3D.new();ground_mat.albedo_color=Color(.29,.31,.30);ground_mat.roughness=.95;ground.material_override=ground_mat;vp.add_child(ground)
	var cam:=Camera3D.new();cam.current=true;cam.near=.03;cam.far=200.;vp.add_child(cam)
	report.render_spec={"dimensions":vec(Vector3(dimensions.x,dimensions.y,0)),"taa":false,"msaa":false,"ambient_energy":.65,"sun_energy":1.5,"sun_rotation":[-38,-28,0],"exposure":1.,"tonemap":"ACES","ground_color":[.29,.31,.30],"characters":"none","wind":"no source wind metadata; one static pose only"}
	report.screenshots=[]
	for view:Dictionary in views:
		cam.position=vector(view.eye);cam.fov=float(view.fov);cam.look_at(vector(view.aim))
		for frame in 10:await process_frame;await RenderingServer.frame_post_draw
		var im:Image=vp.get_texture().get_image();var name_:String=view.name+".png";var path:=out.path_join(case_name).path_join(name_)
		check(im.save_png(path)==OK,"exact local image "+name_)
		report.screenshots.append({"name":name_,"path":path,"file_sha256":FileAccess.get_sha256(path),"pixels":normalized_image(im),"draw_calls":RenderingServer.viewport_get_render_info(vp.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),"renderer_texture_memory_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)})
	vp.queue_free();await process_frame;Drainer.synchronize_transfer()

func compare_reports()->void:
	var a:=read_json(out.path_join("baseline.json"));var b:=read_json(out.path_join("candidate.json"))
	if not check(a.get("passed",false) and b.get("passed",false),"both actual native cases pass"):finish();return
	check(a.original_sha==pinned.source_sha256 and b.original_sha==pinned.candidate_sha256,"A/B reports bind frozen GLB SHA")
	check(a.generator==b.generator and a.generator==Compiled.generator(),"same current native generator")
	check(a.camera_views==b.camera_views and a.render_spec==b.render_spec,"same camera lighting exposure and image dimensions")
	check(stable(a.semantic)==stable(b.semantic),"native geometry material recipe visibility and production collision shape equality")
	report.images=[]
	for shot:Dictionary in a.screenshots:
		var d:=image_difference(out.path_join("baseline").path_join(shot.name),out.path_join("candidate").path_join(shot.name));d.name=shot.name
		report.images.append(d);check(d.get("valid",false) and d.get("exact",false),"lossless actual rendered pixels "+shot.name)
	report.baseline_native=a.native;report.candidate_native=b.native
	report.note="Actual native footprint and fixed-frame A/B only. Footprint estimates and renderer counters are not measured process RSS/dedicated VRAM; GPU images still require visual inspection. Source textures were never recompressed/resized."
	finish()

func run()->void:
	if "--syntax-only" in OS.get_cmdline_user_args():print("MARKET_REVIEW_SYNTAX_OK");quit();return
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--asset="):asset_name=arg.trim_prefix("--asset=")
		elif arg.begins_with("--case="):case_name=arg.trim_prefix("--case=")
		elif arg.begins_with("--take="):take_name=arg.trim_prefix("--take=")
		else:push_error("Unknown argument: "+arg);quit(2);return
	if asset_name not in ["pottery","scroll","potion","ore"] or case_name not in ["baseline","candidate","compare"] or take_name.is_empty() or not take_name.is_valid_identifier():push_error("Invalid fixed review scope");quit(2);return
	var plan:=read_json(PLAN)
	for row:Dictionary in plan.get("rows",[]):
		if row.asset==asset_name:pinned=row
	if pinned.is_empty():push_error("Missing pinned plan");quit(2);return
	source=pinned.source;candidate=pinned.candidate;out=ROOT.path_join(take_name).path_join(asset_name)
	if FileAccess.get_sha256(source)!=pinned.source_sha256 or FileAccess.get_sha256(candidate)!=pinned.candidate_sha256:push_error("Frozen source SHA mismatch");quit(2);return
	if FileAccess.file_exists(out.path_join(case_name+".json")):push_error("Retain prior evidence; choose new take");quit(2);return
	DirAccess.make_dir_recursive_absolute(out);report.asset=asset_name;report.generator=Compiled.generator();report.plan_sha256=FileAccess.get_sha256(PLAN)
	if case_name=="compare":compare_reports();return
	if not check(DisplayServer.get_name()!="headless","private-desktop graphics process required"):finish();return
	Engine.max_fps=60;dimensions=Vector2i(1400,1000)
	var original:String=source if case_name=="baseline" else candidate;var digest:=FileAccess.get_sha256(original)
	report.case_name=case_name;report.original=original;report.original_sha=digest;report.source_bytes=size_of(original);report.dimensions=[dimensions.x,dimensions.y]
	report.raw_admission_estimate=Estimate.estimate(original)
	var case_out:=out.path_join(case_name);var isolated:=case_out.path_join("isolated_content");var local_source:=isolated.path_join("assets").path_join(digest+".glb")
	DirAccess.make_dir_recursive_absolute(local_source.get_base_dir())
	if not check(DirAccess.copy_absolute(original,local_source)==OK and FileAccess.get_sha256(local_source)==digest,"copy exact GLB into owned isolated root"):finish();return
	var document:=GLTFDocument.new();var state:=GLTFState.new();var began:=Time.get_ticks_usec()
	if not check(document.append_from_file(local_source,state,0,local_source.get_base_dir())==OK,"real raw GLTF import"):finish();return
	report.raw_append_us=Time.get_ticks_usec()-began;report.imported_image_entries=state.images.size()
	var scene:Node=Io.generate_scene(document,state)
	if not check(scene!=null,"production scene postprocessing"):finish();return
	scene.name="MarketReview";report.semantic=inspect(scene);report.material_resource_count=materials.size();report.active_texture_bindings=textures.size()
	report.material_pixel_proof="Existing CPU encoded/decoded image SHA proof in optimization audit; no additional model-texture readback/reencoding performed here."
	var bounds:=scene_bounds(scene);report.bounds={"position":vec(bounds.position),"size":vec(bounds.size)}
	var views:Array=[];var view_path:=out.path_join("camera_views.json")
	if case_name=="baseline":views=create_views(scene,bounds);put(view_path,{"source_sha":pinned.source_sha256,"views":views})
	else:
		var saved:=read_json(view_path)
		if not check(saved.get("source_sha")==pinned.source_sha256,"frozen baseline cameras exist"):scene.free();finish();return
		views=saved.views
	report.camera_views=views
	# Private library reader/save verification; never call default-root import_file.
	var library:=Library.new(local_source.get_base_dir())
	library.entries=[{"label":pinned.label,"category":"隔离模型验收","asset_path":local_source,"bounds_position":vec(bounds.position),"bounds_size":vec(bounds.size)}]
	check(library.save()==OK,"private library atomic save")
	check(catalog_roundtrip_same(Library.new(library.directory).entries,library.entries),"private library reopen exact fields and bounds within relative 1e-12")
	own(scene,scene);var packed:=PackedScene.new()
	if not check(packed.pack(scene)==OK and Compiled._valid_packed(packed),"production native schema"):scene.free();finish();return
	var folder:String=Compiled.directory(isolated);DirAccess.make_dir_recursive_absolute(folder);var draft:=folder.path_join("review_build.scn")
	if not check(ResourceSaver.save(packed,draft,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)==OK,"isolated compressed native save"):scene.free();finish();return
	scene.free();scene=null;packed=null;state=null;document=null;Drainer.synchronize_transfer()
	var payload_sha:=FileAccess.get_sha256(draft);var payload:=folder.path_join(payload_sha+".scn")
	check(DirAccess.rename_absolute(draft,payload)==OK,"private content-addressed native publish")
	check(ResourceLoader.get_dependencies(payload).is_empty(),"native has no external dependencies")
	check(put(Compiled.index_path(local_source,isolated),{"version":Compiled.VERSION,"generator":Compiled.generator(),"source_sha":digest,"payload_sha":payload_sha,"bytes":size_of(payload)}),"isolated native index")
	var loaded:Dictionary=Compiled.read(local_source,digest,isolated)
	if not check(loaded.get("hit",false),"production native reader accepts exact private product"):finish();return
	packed=loaded.packed;var stats:Dictionary=Footprint.measure(packed);stats.native_uncompressed_bytes=Footprint.native_uncompressed_bytes(payload)
	var estimated:Dictionary=Footprint.estimate_stats(stats);check(not estimated.is_empty(),"real native footprint measure")
	scene=packed.instantiate();check(stable(inspect(scene))==stable(report.semantic),"native save-reopen preserves materials geometry and collision shape")
	report.native={"content_root":isolated,"source":local_source,"payload":payload,"payload_sha256":payload_sha,"native_bytes":size_of(payload),"stats":stats,"estimate":estimated}
	scene.free();scene=null;loaded.clear();packed=null;Drainer.synchronize_transfer()
	var built:Dictionary=Footprint.build(local_source,isolated);check(built.get("ok",false),"production footprint build in explicit isolated root")
	var fc:Dictionary=Footprint.candidate(local_source,isolated,digest);check(not fc.is_empty(),"actual native footprint verifies");report.native.footprint_candidate=fc
	var prepared:Dictionary=Preparation.read(local_source,fc,isolated)
	if not check(prepared.get("error",FAILED)==OK and prepared.get("packed")!=null and not prepared.get("fallback_required",false),"production native preparation"):finish();return
	packed=prepared.packed;scene=packed.instantiate();check(stable(inspect(scene))==stable(report.semantic),"prepared native semantic identity")
	prepared.clear();packed=null;Drainer.synchronize_transfer();await draw_scene(scene,views)
	check(FileAccess.get_sha256(original)==digest and FileAccess.get_sha256(local_source)==digest,"formal/candidate source bytes untouched")
	report.collision_scope="Production PickingShapeCache shape faces, transforms, WalkMode physical masks before and after native save/reopen. No formal map, UI HTTP or controller traversal claim."
	finish()
