extends SceneTree
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Surface=preload("res://scripts/world3d/surface_materials.gd")
const Response=preload("res://scripts/world3d/wind_response.gd")
const Runtime=preload("res://scripts/world3d/wind_runtime.gd")
const Vegetation=preload("res://scripts/world3d/vegetation_render.gd")
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const G=preload("res://scripts/world3d/ground_batch_geometry.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/wind_cutout_20261018/"
var failures:=0
var evidence:Dictionary={"checks":[],"models":[]}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_);evidence.checks.append({"ok":ok,"label":label_})
	if not ok:failures+=1
func shot(view:SubViewport,path:String)->Image:
	for i in 5:await process_frame;await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image();image.save_png(path);return image
func make_native(source:String,folder:String)->Dictionary:
	# Same explicit isolated native contract as the existing model review helper.
	var isolated:=folder.path_join("isolated_content");var path:=isolated.path_join("assets/model.glb")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir());DirAccess.copy_absolute(source,path)
	check(FileAccess.get_sha256(source)==FileAccess.get_sha256(path),"isolated source copy preserves final bytes")
	var prepared:=Compiled.prepare_source(path);var scene:Node=prepared.get_scene()
	if scene==null:prepared.dispose();return {}
	Compiled._own(scene,scene);var packed:=PackedScene.new()
	check(packed.pack(scene)==OK and Compiled._valid_packed(packed),"fresh production scene satisfies native graph validator")
	var cache:=Compiled.directory(isolated);DirAccess.make_dir_recursive_absolute(cache)
	var temporary:=cache.path_join("review.scn")
	check(ResourceSaver.save(packed,temporary,ResourceSaver.FLAG_COMPRESS|ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"save compressed closed native product outside shared caches")
	packed=null;prepared.dispose()
	var digest:=FileAccess.get_sha256(temporary);var saved:=cache.path_join(digest+".scn");DirAccess.rename_absolute(temporary,saved)
	var manifest:={"version":Compiled.VERSION,"generator":Compiled.generator(),"source_sha":FileAccess.get_sha256(path),"payload_sha":digest,"bytes":FileAccess.get_file_as_bytes(saved).size()}
	FileAccess.open(Compiled.index_path(path,isolated),FileAccess.WRITE).store_string(JSON.stringify(manifest))
	var result:=Compiled.read(path,manifest.source_sha,isolated);result.saved=saved
	return result
func run()->void:
	create_timer(220).timeout.connect(func():quit(2))
	var handoff:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/review_artifacts/axel_vegetation_resource_audit_20261017/candidate_handoff01.json"))
	var media:String=OUT+"production_%d"%Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(media)
	for item:Dictionary in handoff.models:
		if item.label not in ["short_grass_a","boxwood"]:continue
		var path:String=item.candidate.path
		var native:Dictionary=make_native(path,media.path_join(item.label))
		check(native.get("hit",false),"current production Compiled.read accepts freshly built isolated product: "+item.label)
		if not native.get("hit",false):continue
		var packed:PackedScene=native.packed;var saved:String=native.saved
		var holder:Node3D=packed.instantiate()
		check(holder!=null and FileAccess.get_sha256(path)==item.candidate.sha256,"production asset final bytes and native reopening preserve retained identity: "+item.label)
		var record:={"uuid":"retained_"+item.label,"kind":"asset","asset_path":path,"vegetation_batch":true}
		var unchanged:bool=Vegetation.flatten(holder,record)==holder
		check(unchanged,"existing wind/LOD hierarchy remains intact: "+item.label)
		var view:=SubViewport.new();view.size=Vector2i(1280,800);view.own_world_3d=true;view.use_taa=false;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
		var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.08,.1,.16);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.5;view.add_child(env)
		var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-35,0);sun.shadow_enabled=true;sun.directional_shadow_max_distance=500;view.add_child(sun)
		var camera:=Camera3D.new();camera.current=true;camera.fov=50;camera.far=500;view.add_child(camera);view.add_child(holder)
		var bounds:AABB=Assets.bounds_of(holder);var center:=bounds.get_center()
		var floor_node:=MeshInstance3D.new();var floor_mesh:=BoxMesh.new();floor_mesh.size=Vector3(25,.05,25);floor_node.mesh=floor_mesh;floor_node.position.y=bounds.position.y-.025;view.add_child(floor_node)
		var runtime:=Runtime.new();view.add_child(runtime);runtime.camera=camera;runtime.set_physics_process(false)
		var source_identity:Array=[];var wind_nodes:=0
		for visual:MeshInstance3D in Surface.meshes(holder):
			source_identity.append([visual.get_instance_id(),visual.mesh,visual.transform]);Response.register(visual)
			if visual.is_in_group(Response.GROUP):wind_nodes+=1
		var batch:=Batch.new();view.add_child(batch);batch.set_process(false)
		var rows:Array=[]
		for v:Dictionary in [{"name":"detail","distance":2.5},{"name":"near","distance":6.},{"name":"mid","distance":18.},{"name":"far","distance":45.}]:
			camera.position=center+Vector3(v.distance*.25,v.distance*.18,v.distance);camera.look_at(center)
			for t:float in [1.,1.75]:
				G.static_scatter_instances_enabled=false;batch.clear();runtime.set_enabled(false);runtime.set_enabled(true);runtime.set_physics_process(false);runtime.cached_variants_only=false;runtime.refresh();runtime.advance(Vector3(8,0,2),t)
				var prefix:String=item.label+"_"+v.name+"_"+str(t)
				var a:Image=await shot(view,media.path_join(prefix+"_source.png"))
				var before_triangles:int=view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
				G.static_scatter_instances_enabled=true;runtime.set_enabled(false);runtime.set_enabled(true);runtime.set_physics_process(false);runtime.cached_variants_only=true;runtime.refresh();runtime.advance(Vector3(8,0,2),t);batch.sync([holder]);batch.flush()
				var b:Image=await shot(view,media.path_join(prefix+"_guarded.png"))
				var after_triangles:int=view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
				var exact:bool=a.get_data()==b.get_data()
				check(exact and before_triangles==after_triangles,"production alpha/shadows/wind and original LOD match: "+prefix)
				rows.append({"view":v.name,"time":t,"exact_pixels":exact,"source_triangles":before_triangles,"guarded_triangles":after_triangles,"wind":runtime.capability_status()})
		var preserved:=true
		for row:Array in source_identity:
			var visual:MeshInstance3D=instance_from_id(row[0]);preserved=preserved and visual.mesh==row[1] and visual.transform==row[2]
		check(preserved,"original mesh and local transforms remain identical across render policies")
		var costs:Dictionary=Footprint.measure(packed)
		costs.native_uncompressed_bytes=Footprint.native_uncompressed_bytes(saved)
		evidence.models.append({"label":item.label,"source_path":path,"source_sha256":FileAccess.get_sha256(path),"source_bytes":FileAccess.get_file_as_bytes(path).size(),"wind_nodes":wind_nodes,"native_reopened":true,"native_path":saved,"native_sha256":FileAccess.get_sha256(saved),"native_bytes":FileAccess.get_file_as_bytes(saved).size(),"compiled_generator":Compiled.generator(),"costs":costs,"views":rows})
		view.free();await process_frame
	evidence.failures=failures;evidence.media=media
	FileAccess.open(OUT+"production_retention.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"  "))
	print("PRODUCTION_VEGETATION_RETENTION failures=",failures);quit(1 if failures else 0)
