extends "res://review_artifacts/town_asset_size_audit_20261011/review_lossless_candidates.gd"
## Read-only, one model per process. Source explicitly imports GLB; native and
## metadata only reopen the actual published SCN, including older generators.
## Required: --mode=source|native|metadata --source=logical.glb --source-sha=...
## --content-root=... --report=external/review_artifacts/fresh/report.json
## Native/metadata also require --product=actual.scn --payload-sha=...
## Source writes camera.json beside its report unless --camera=existing.json.
## Native REQUIRES --camera=source/camera.json; metadata does not render.
## Optional --width=1400 --height=1000 --detail=auto|pennant --id=model-id.
## --features=alpha,emission adds bright/dark alpha and night material captures,
## with a source-authored receiver and shadow camera shared by both arms.
## Run GPU via run_godot_background.py. No library/map/product publication.
const Contract=preload("res://tools/native_migration_review_contract.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Product=preload("res://scripts/world3d/native_model_product.gd")
const Imported=preload("res://scripts/world3d/imported_building.gd")
const WindResponse=preload("res://scripts/world3d/wind_response.gd")
const Schema=preload("res://scripts/world3d/document_schema.gd")
class ReviewErrors extends Logger:
	var errors:Array[String]=[]
	var mutex:=Mutex.new()
	func _log_error(function:String,_file:String,_line:int,code:String,rationale:String,_editor_notify:bool,_type:int,_backtraces:Array)->void:
		mutex.lock();errors.append(function+": "+code+" "+rationale);mutex.unlock()
var mode:=""
var source_sha:=""
var product_path:=""
var payload_sha:=""
var content_root:=""
var report_path:=""
var camera_path:=""
var asset_id:=""
var input_files:Dictionary={}
var raw_textures:Array=[]
var collecting_semantics:=false
var source_owner:Compiled.PreparedSource
var native_packet:Dictionary={}
var reviewed_scene:Node
var review_viewport:SubViewport
var errors:ReviewErrors
var finished:=false
var output_ready:=false
var recipe:Dictionary={}
var captured_code:Dictionary={}
var fixed_native:Dictionary={}
var features:Array[String]=[]
var receiver_recipe:Dictionary={}

func check(ok:bool,label:String)->bool:
	report.checks.append({"label":label,"ok":ok})
	print("PASS " if ok else "FAIL ",label)
	if not ok:report.failures.append(label)
	return ok

func normalized_image(image:Image)->Dictionary:
	if image==null or image.is_empty():check(false,"nonempty actual texture/image readback");return {"invalid":true}
	if collecting_semantics:
		raw_textures.append({"width":image.get_width(),"height":image.get_height(),"format":image.get_format(),"mips":image.has_mipmaps(),"mipmap_count":image.get_mipmap_count(),"bytes":image.get_data().size(),"pixels_sha256":sha(image.get_data())})
	var value:=super.normalized_image(image)
	if value.has("invalid_compression"):check(false,"actual texture decompresses for normalized pixel comparison")
	return value

func value_semantic(value:Variant,depth:int=0)->Variant:
	if depth>24:check(false,"semantic recursion is supported");return {"unsupported_depth":true}
	if value is Shader:return {"shader_code_sha256":str(value.code).sha256_text()}
	return super.value_semantic(value,depth)

func _arguments()->bool:
	var values:Dictionary={}
	for arg:String in OS.get_cmdline_user_args():
		var at:=arg.find("=")
		if at<3 or not arg.begins_with("--"):return check(false,"all arguments use --name=value")
		var name_:String=arg.substr(2,at-2)
		if name_ not in ["mode","source","source-sha","product","payload-sha","content-root","report","camera","width","height","detail","id","features"] or values.has(name_):return check(false,"known unique argument: "+name_)
		values[name_]=arg.substr(at+1)
	mode=values.get("mode","");source=Contract.canonical(values.get("source",""));source_sha=values.get("source-sha","")
	product_path=Contract.canonical(values.get("product",""));payload_sha=values.get("payload-sha","")
	content_root=Contract.canonical(values.get("content-root",""));report_path=Contract.canonical(values.get("report",""))
	camera_path=Contract.canonical(values.get("camera",""));asset_id=values.get("id",source.get_file());detail_mode=values.get("detail","auto")
	var requested_features:String=values.get("features","")
	if not requested_features.is_empty():
		for feature:String in requested_features.split(","):
			if feature not in ["alpha","emission"] or feature in features:return check(false,"known unique capture feature")
			features.append(feature)
	features.sort()
	for key:String in ["width","height"]:
		if values.has(key) and not str(values[key]).is_valid_int():return check(false,"integer output dimension")
	dimensions=Vector2i(int(values.get("width","1400")),int(values.get("height","1000")))
	if not check(mode in ["source","native","metadata"] and Compiled._sha(source_sha),"explicit mode and expected source identity"):return false
	if not check(content_root.is_absolute_path() and Paths.allowed(content_root) and source.is_absolute_path() and Paths.asset_key_allowed(source,content_root),"source logical key stays in allowed content root"):return false
	if not check(dimensions.x>=64 and dimensions.y>=64 and dimensions.x<=8192 and dimensions.y<=8192 and detail_mode in ["auto","pennant"],"valid capture dimensions and detail mode"):return false
	if not check(report_path.get_extension()=="json" and Contract.output_allowed(report_path,Paths.external_root(),ProjectSettings.globalize_path("res://")),"report is outside project in external review_artifacts"):return false
	if not check(not FileAccess.file_exists(report_path),"fresh report path never overwrites previous evidence"):return false
	out=report_path.get_base_dir();case_name=mode
	if mode=="source" and camera_path.is_empty() and not check(report_path!=out.path_join("camera.json"),"report cannot overwrite generated camera evidence"):return false
	var image_directory:=out.path_join(mode)
	if mode!="metadata" and not check(not DirAccess.dir_exists_absolute(image_directory),"fresh image directory preserves previous evidence"):return false
	if DirAccess.make_dir_recursive_absolute(out)!=OK:return check(false,"create external output directory")
	output_ready=true
	if mode!="source" and not check(product_path.is_absolute_path() and Paths.allowed(product_path,Compiled.directory(content_root)) and Compiled._sha(payload_sha),"explicit native product and expected payload identity"):return false
	if mode=="native" and not check(not camera_path.is_empty(),"native capture requires source camera recipe"):return false
	if not camera_path.is_empty() and not check(Contract.output_allowed(camera_path,Paths.external_root(),ProjectSettings.globalize_path("res://")) and FileAccess.file_exists(camera_path),"existing camera is an external review input"):return false
	return true

func _code_identity()->Dictionary:
	var result:Dictionary={}
	for path:String in ["res://tools/review_native_migration.gd","res://tools/native_migration_review_contract.gd","res://review_artifacts/town_asset_size_audit_20261011/review_lossless_candidates.gd","res://scripts/world3d/compiled_asset_cache.gd","res://scripts/world3d/compiled_asset_preparation.gd","res://scripts/world3d/compiled_asset_footprint.gd","res://scripts/world3d/native_model_product.gd","res://scripts/world3d/gltf_map_io.gd","res://scripts/world3d/model_lod_preparation.gd","res://scripts/world3d/model_texture_cache.gd","res://scripts/world3d/grass_texture_cache.gd","res://scripts/world3d/leaf_backlight.gd","res://scripts/world3d/tinted_glass.gd","res://scripts/world3d/asset_visibility_range.gd","res://scripts/world3d/wind_material.gd","res://scripts/world3d/wind_material.gdshader","res://scripts/world3d/wind_response.gd"]:
		result[path]=FileAccess.get_sha256(path)
	return result

func _capture_recipe()->Dictionary:
	return {"version":1,"engine":Engine.get_version_info(),"engine_sha256":FileAccess.get_sha256(OS.get_executable_path()),"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"gpu":RenderingServer.get_video_adapter_name(),"code_sha256":captured_code,"dimensions":[dimensions.x,dimensions.y],"detail":detail_mode,"taa":false,"msaa":0,"background":[.14,.17,.20],"ambient":.65,"sun_rotation":[-38,-28,0],"sun_energy":1.5,"shadow_distance":500,"tonemap":"ACES","exposure":1.0,"camera_near":.03,"camera_far":10000.0,"settle_frames":8,"wind_samples":[[0,0,0,0],[7,0,3,1],[7,0,3,4]],"shadow_receiver":not features.is_empty(),"features":features,"lighting_cases":_lighting_cases(),"receiver_material":{"albedo":[.48,.48,.44],"roughness":.95,"casts_shadow":false},"night_scope":"actual authored material emission; no synthetic light or runtime lamp effects"}

func _lighting_cases()->Array:
	var cases:Array=[{"name":"day","background":[.14,.17,.20],"ambient":.65,"sun":1.5,"views":"all"}]
	if "alpha" in features:
		cases.append_array([{"name":"alpha_bright","background":[.9,.9,.9],"ambient":.65,"sun":1.5,"views":"near_detail"},{"name":"alpha_dark","background":[.01,.01,.01],"ambient":.65,"sun":1.5,"views":"near_detail"}])
	if "emission" in features:cases.append({"name":"night","background":[.005,.008,.015],"ambient":.025,"sun":0.0,"views":"near_detail"})
	return cases

func _source_camera_packet(bounds:AABB)->Dictionary:
	var packet:={"version":1,"source_sha256":source_sha,"recipe":recipe,"views":create_views(reviewed_scene,bounds),"receiver":{}}
	if not recipe.shadow_receiver:return packet
	var ground_y:=bounds.position.y-.025
	var receiver_bounds:=bounds
	var ray_direction:Vector3=-(Basis.from_euler(Vector3(deg_to_rad(-38),deg_to_rad(-28),0))).z
	for endpoint:int in 8:
		var point:=bounds.get_endpoint(endpoint)
		receiver_bounds=receiver_bounds.expand(point+ray_direction*((ground_y-point.y)/ray_direction.y))
	var centre:=receiver_bounds.get_center();var radius:=maxf(1,receiver_bounds.size.length()*.5)
	packet.receiver={"position":[centre.x,ground_y,centre.z],"size":[maxf(8,receiver_bounds.size.x*1.7),maxf(8,receiver_bounds.size.z*1.7)]}
	packet.views.append({"name":"shadow_overview","eye":vec(centre+Vector3(1,1.15,1.5).normalized()*radius/sin(deg_to_rad(19))*1.12),"aim":vec(centre),"fov":38.0,"projection":"perspective"})
	return packet

func _remember(path:String)->bool:
	var digest:=FileAccess.get_sha256(path)
	if not check(Compiled._sha(digest),"input identity: "+path):return false
	input_files[path]=digest;return true

func _load_source()->bool:
	if not check(Paths.allowed(source,content_root) and FileAccess.get_sha256(source)==source_sha,"actual authoring GLB matches expected SHA"):return false
	_remember(source)
	source_owner=Compiled.prepare_source(source)
	if not check(source_owner.error==OK and source_owner.source_digest==source_sha,"explicit production GLB import succeeds"):return false
	reviewed_scene=source_owner.get_scene()
	if not check(reviewed_scene!=null,"production source scene generation succeeds"):return false
	report.source_observation={"sha256":source_sha,"bytes":size_of(source),"parse":source_owner.report(),"scope":"explicit offline authoring import"}
	return true

func _load_native()->bool:
	# All observations below bind the actual publication. They never ask the
	# source GLB for existence, length or a hash, and never publish a replacement.
	var descriptor:Dictionary={}
	var offered:=Footprint.candidate(source,content_root,source_sha,true,"",descriptor)
	if not check(not offered.is_empty(),"published native footprint exists for expected source identity"):return false
	if not check(offered.payload_sha==payload_sha and Contract.canonical(offered.product)==product_path,"specified native file is the actual published payload"):return false
	for path:String in [Compiled.index_path(source,content_root),Footprint.descriptor_path(source,content_root),Footprint.building_descriptor_path(source,content_root),product_path]:
		if not _remember(path):return false
	if not check(input_files[product_path]==payload_sha,"actual native bytes match expected payload SHA"):return false
	var metadata:=Product.read(source,content_root,source_sha)
	if not check(not metadata.is_empty() and metadata.native_payload_sha==payload_sha,"native bounds and budget bind the same published product"):return false
	native_packet=Preparation.read(source,offered,content_root,Callable(),false,false,"",true)
	if not check(native_packet.get("error",FAILED)==OK and not native_packet.get("fallback_required",false) and native_packet.get("packed") is PackedScene,"ordinary published native reader reopens this exact SCN"):return false
	fixed_native=offered.duplicate(true)
	var packed:PackedScene=native_packet.packed
	reviewed_scene=packed.instantiate()
	if not check(reviewed_scene!=null,"actual native scene instantiates"):return false
	var actual_bounds:=scene_bounds(reviewed_scene);var accepted:AABB=metadata.local_bounds
	var tolerance:=maxf(.0001,maxf(accepted.position.length(),accepted.size.length())*.00001)
	check(accepted.grow(tolerance).encloses(actual_bounds),"published bounds conservatively enclose actual native meshes")
	var actual_building:=Imported.describe_packed(packed,source_sha)
	var stored_building:=Footprint._building_metadata(source,content_root,offered)
	check(actual_building.get("ok",false) and not stored_building.is_empty() and stored_building.present==actual_building.get("present") and (not stored_building.present or Contract.same(stored_building.descriptor,actual_building.get("descriptor"))),"building sidecar matches actual published SceneState")
	var absence:Variant=descriptor.get("collision_absence")
	var actual_absence:=Footprint.collision_absence_from_packed(packed)
	if absence!=null:check(Contract.same(absence,actual_absence),"optional absence sidecar matches actual published SceneState")
	report.sidecars={"identity":offered,"model_metadata":descriptor.model_metadata,"building":stored_building,"collision_absence":absence,"absence_status":"verified" if absence!=null else "missing: complete native geometry fallback remains required","actual_bounds":var_to_str(actual_bounds),"bound_tolerance":tolerance}
	report.native={"path":product_path,"source_sha256":source_sha,"payload_sha256":payload_sha,"generator":offered.generator,"bytes":offered.bytes,"uncompressed_bytes":Footprint.native_uncompressed_bytes(product_path),"source_glb_observation":"none: identity read from publication"}
	if mode=="metadata":
		report.cost={"stats":descriptor.get("stats",{}),"admission_bytes":offered.estimated_bytes,"scope":"published offline cost contract, not new readback/RSS/VRAM measurement"}
	else:
		var stats:=Footprint.measure(packed);stats.native_uncompressed_bytes=report.native.uncompressed_bytes
		var estimate:=Footprint.estimate_stats(stats)
		check(not estimate.is_empty() and estimate.estimated_bytes<=offered.estimated_bytes,"actual reopened graph fits the published conservative budget")
		report.cost={"stats":stats,"fresh_conservative_estimate":estimate,"admission_bytes":offered.estimated_bytes,"scope":"actual native graph readback and conservative envelope; not measured RSS/VRAM"}
	return report.failures.is_empty()

func _views()->Array:
	var bounds:=scene_bounds(reviewed_scene)
	report.bounds={"position":vec(bounds.position),"size":vec(bounds.size)}
	if camera_path.is_empty():
		camera_path=out.path_join("camera.json")
		if not check(not FileAccess.file_exists(camera_path),"camera generation never overwrites an earlier recipe"):return []
		var created:=_source_camera_packet(bounds)
		if not check(Contract.camera_valid(created,recipe,source_sha) and put(camera_path,created),"source writes complete fixed camera recipe"):return []
	var file:=FileAccess.open(camera_path,FileAccess.READ)
	if not check(file!=null and file.get_length()<=2*1024*1024,"bounded camera input"):return []
	var bytes:=file.get_buffer(file.get_length());file.close()
	var packet:Variant=JSON.parse_string(bytes.get_string_from_utf8())
	if not check(packet is Dictionary and Contract.camera_valid(packet,recipe,source_sha),"camera exactly matches source, engine, GPU, code, dimensions and environment"):return []
	var digest:=sha(bytes)
	if not check(FileAccess.get_sha256(camera_path)==digest,"parsed camera bytes remain unchanged"):return []
	input_files[camera_path]=digest
	report.camera={"path":camera_path,"sha256":digest}
	receiver_recipe=packet.get("receiver",{}).duplicate(true);report.receiver=receiver_recipe
	return packet.views

func _render(views:Array)->void:
	var image_directory:=out.path_join(mode)
	if not check(DirAccess.make_dir_recursive_absolute(image_directory)==OK,"create fresh image directory"):return
	root.size=dimensions
	review_viewport=SubViewport.new();review_viewport.size=dimensions;review_viewport.own_world_3d=true;review_viewport.use_taa=false;review_viewport.msaa_3d=Viewport.MSAA_DISABLED;review_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(review_viewport);review_viewport.add_child(reviewed_scene)
	var world:=WorldEnvironment.new();world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color(.14,.17,.20)
	world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color.WHITE;world.environment.ambient_light_energy=.65
	world.environment.tonemap_mode=Environment.TONE_MAPPER_ACES;world.environment.tonemap_exposure=1.0;review_viewport.add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-28,0);sun.light_energy=1.5;sun.shadow_enabled=true;sun.directional_shadow_max_distance=500;review_viewport.add_child(sun)
	if not receiver_recipe.is_empty():
		var receiver:=MeshInstance3D.new();receiver.name="Review_only_shadow_receiver"
		var plane:=PlaneMesh.new();plane.size=Vector2(receiver_recipe.size[0],receiver_recipe.size[1]);receiver.mesh=plane
		receiver.position=vector(receiver_recipe.position);receiver.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var receiver_material:=StandardMaterial3D.new();receiver_material.albedo_color=Color(.48,.48,.44);receiver_material.roughness=.95
		receiver.material_override=receiver_material;review_viewport.add_child(receiver)
	var camera:=Camera3D.new();camera.current=true;camera.near=.03;camera.far=10000;review_viewport.add_child(camera)
	var winds:Array[ShaderMaterial]=[];var nodes:Array=[];gather(reviewed_scene,nodes)
	for node:Node in nodes:
		if not node is MeshInstance3D or node.mesh==null:continue
		var config:Variant=node.get_meta("extras",{}).get("rmmo_wind",{})
		if not config is Dictionary or config.is_empty():continue
		if not check(Schema.validate(config,WindResponse.schema()).is_empty(),"authored wind metadata is supported: "+str(reviewed_scene.get_path_to(node))):continue
		config=WindResponse.defaults().merged(config,true)
		if config.profile=="off":continue
		for slot:int in node.mesh.get_surface_count():
			var material:Material=node.get_active_material(slot)
			if not check(material is StandardMaterial3D and WindResponse.material_error(material).is_empty(),"wind material is supported for actual surface"):continue
			var wind:=Wind.make(material,config,node.get_aabb());node.set_surface_override_material(slot,wind);winds.append(wind)
	report.wind_surface_count=winds.size();report.screenshots=[]
	var poses:Array=[{"name":"still","velocity":Vector3.ZERO,"time":0.0}]
	if not winds.is_empty():poses.append_array([{"name":"wind_t1","velocity":Vector3(7,0,3),"time":1.0},{"name":"wind_t4","velocity":Vector3(7,0,3),"time":4.0}])
	var expected_images:=0
	for lighting:Dictionary in recipe.lighting_cases:
		world.environment.background_color=Color(float(lighting.background[0]),float(lighting.background[1]),float(lighting.background[2]))
		world.environment.ambient_light_energy=float(lighting.ambient);sun.light_energy=float(lighting.sun)
		for view_index:int in views.size():
			if lighting.views=="near_detail" and view_index not in [0,3]:continue
			var view:Dictionary=views[view_index]
			camera.position=vector(view.eye);camera.fov=float(view.fov);camera.look_at(vector(view.aim))
			for pose:Dictionary in poses:
				expected_images+=1
				for material:ShaderMaterial in winds:material.set_shader_parameter("wind_velocity",pose.velocity);material.set_shader_parameter("wind_time",pose.time)
				for frame:int in 8:await process_frame;await RenderingServer.frame_post_draw
				if finished:return
				var image_:Image=review_viewport.get_texture().get_image()
				var filename:String=str(lighting.name)+"_"+str(view.name)+"_"+str(pose.name)+".png";var path:=image_directory.path_join(filename)
				if not check(image_!=null and image_.save_png(path)==OK,"capture "+filename):continue
				var rid:=review_viewport.get_viewport_rid()
				report.screenshots.append({"name":filename,"path":path,"file_sha256":FileAccess.get_sha256(path),"pixels":normalized_image(image_),"draw_calls":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),"rendered_primitives":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)})
	check(report.screenshots.size()==expected_images,"every requested view/light/wind sample has image evidence")

func _cleanup()->void:
	if review_viewport!=null:
		if reviewed_scene!=null and reviewed_scene.get_parent()==review_viewport:review_viewport.remove_child(reviewed_scene)
		review_viewport.free();review_viewport=null
	if source_owner!=null:source_owner.dispose();source_owner=null
	elif reviewed_scene!=null:Drainer.dispose_scene(reviewed_scene)
	reviewed_scene=null
	Drainer.synchronize_transfer();Drainer.dispose_result(native_packet)
	textures.clear();materials.clear()

func finish()->void:
	if finished:return
	finished=true
	_cleanup()
	if errors!=null:
		OS.remove_logger(errors)
		report.engine_errors=errors.errors.duplicate()
		check(errors.errors.is_empty(),"zero unexpected engine/script errors")
	for path:String in input_files:check(FileAccess.get_sha256(path)==input_files[path],"input remains unchanged: "+path)
	if not fixed_native.is_empty():check(Contract.same(Footprint.candidate(source,content_root,source_sha,true),fixed_native),"actual publication remains the same frozen native identity")
	if not captured_code.is_empty():check(Contract.same(captured_code,_code_identity()),"review and production code remain unchanged")
	report.input_sha256=input_files;report.passed=report.failures.is_empty()
	report.status={"resource_audit":"passed" if report.passed else "failed","visual":"pending_human_review" if mode!="metadata" else "not_rendered: reuse requires prior evidence with the same payload SHA","runtime_pipeline":"actual native reopen checked" if mode in ["native","metadata"] and report.passed else "not_claimed","editor_integration":"not_run"}
	var saved:bool=output_ready and put(report_path,report)
	print("NATIVE_MIGRATION_REVIEW mode=",mode," checks=",report.checks.size()," failures=",report.failures.size()," report=",report_path," saved=",saved)
	quit(0 if saved and report.passed else 1)

func run()->void:
	report={"version":1,"checks":[],"failures":[],"scope":"One actual model, offline migration evidence only. No product/library/map writes; no automatic visual approval, real-map timing or per-model RSS/VRAM claim.","visual_acceptance":"pending human inspection; use actual lossy WebP quality 90 upload copies; compare local original PNGs"}
	if not _arguments():finish();return
	report.mode=mode;report.asset_id=asset_id;report.logical_source=source;report.expected_source_sha256=source_sha;report.content_root=content_root
	if not check(DisplayServer.get_name()!="headless","private GPU desktop is required even for actual metadata reopen"):finish();return
	errors=ReviewErrors.new();OS.add_logger(errors)
	Engine.max_fps=60
	create_timer(300).timeout.connect(func():check(false,"one-model review timed out");finish())
	captured_code=_code_identity()
	for digest:Variant in captured_code.values():
		if not check(Compiled._sha(digest),"review code identity is present"):finish();return
	recipe=_capture_recipe();report.recipe=recipe
	var loaded:=_load_source() if mode=="source" else _load_native()
	if not loaded:finish();return
	if mode!="metadata":
		collecting_semantics=true;report.semantic=inspect(reviewed_scene);collecting_semantics=false
		if not check(report.semantic.mesh_nodes>0 and report.semantic.instance_triangles>0,"reviewed model has actual triangle geometry"):finish();return
		report.semantic_sha256=sha(stable(report.semantic).to_utf8_buffer());report.texture_readback=raw_textures
		report.resource_counts={"material_objects":materials.size(),"texture_objects":textures.size(),"instance_triangles_lod0":report.semantic.instance_triangles,"mesh_nodes":report.semantic.mesh_nodes}
		if mode=="source":report.cost={"source_bytes":size_of(source),"texture_readbacks":raw_textures,"scope":"actual texture object readback bytes including mip chains; aliases/counts are not RSS or VRAM; no native estimate on source arm"}
		var views:=_views()
		if not views.is_empty():
			report.camera_views=views
			await _render(views)
	finish()
