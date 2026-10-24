extends SceneTree
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Template=preload("res://scripts/world3d/asset_spec_template.gd")
const Compare=preload("res://tools/test_asset_spec_template_gpu.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run_case(mode:String,packed:PackedScene,record:Dictionary,expected:Array)->void:
	var loader:=Loader.new();loader.background_preload=true;loader._mesh_cache_allowed=false
	loader._path=record.asset_path
	loader._source_snapshot=preload("res://scripts/world3d/document_source_snapshot.gd").read_file(loader._path)
	loader._record_meta={"rmmo_records":[record]};loader._record_order={record.uuid:0}
	loader._asset_states={record.asset_path:{"packed":packed}}
	var observed:Dictionary={"worker":false,"completed":false,"scene":null,"error":"","profile":{}}
	loader.progress.connect(func(stage:String,_done:int,_total:int):
		if stage!="准备模型实例数据（后台）":return
		observed.worker=loader._asset_spec_worker!=null and loader._asset_spec_worker.is_started()
		if mode=="cancel":loader.cancel()
		elif mode=="free":loader.queue_free()
	)
	loader.finished.connect(func(scene:Node,_path:String,error:String):
		observed.completed=true;observed.scene=scene;observed.error=error;observed.profile=loader._profile.duplicate(true)
	)
	loader.tree_exiting.connect(func():observed.profile=loader._profile.duplicate(true))
	root.add_child(loader);loader.set_process(false);loader._build_records()
	var deadline:=Time.get_ticks_msec()+20000
	while is_instance_valid(loader) and Time.get_ticks_msec()<deadline:await process_frame
	check(not is_instance_valid(loader) and observed.worker,mode+": loader uses the private worker and exits")
	if mode=="complete":
		check(observed.completed and observed.error.is_empty() and is_instance_valid(observed.scene),"complete: finished scene transfers once")
		if is_instance_valid(observed.scene):
			var library:Array=observed.scene.get_meta("stream_library",[])
			# Index construction adds residency metadata to the same spec owners.
			var projection:Array=[]
			for spec:Dictionary in library:
				var clean:Dictionary={}
				for key in expected[projection.size()]:clean[key]=spec.get(key)
				projection.append(clean)
			check(Compare.same(projection,expected),"complete: exact source owners, fixture state and bounds match graph projection")
			var handle:Node3D=observed.scene.get_child(0)
			check(handle.get_meta("asset_uuid")==record.uuid and handle.get_child_count()==0,"complete: whole-asset handle remains without disposable descendants")
			check(observed.profile.asset_instance_nodes_avoided>2000 and observed.profile.asset_instance_worker_us>0,"complete: node reduction and worker CPU time are measured")
			var description:Dictionary=packed.get_meta(Template.META)
			check(observed.profile.accepted_initial_template_rows_adapted==description.rows.size() and observed.profile.accepted_initial_template_rows_projected==description.rows.size() and observed.profile.accepted_initial_template_sockets_applied==(description.sockets.size() if description.components else 0) and observed.profile.accepted_initial_template_meshes_projected==expected.size(),"complete: accepted initial-template row/socket/mesh work matches the immutable description")
			observed.scene.free()
	else:
		check(not observed.completed,mode+": no partial scene is published")
		check(observed.profile.get("accepted_initial_template_rows_adapted",0)==0 and observed.profile.get("accepted_initial_template_rows_projected",0)==0 and observed.profile.get("accepted_initial_template_sockets_applied",0)==0 and observed.profile.get("accepted_initial_template_meshes_projected",0)==0,mode+": unaccepted worker packet is not counted as completed initial-template work")
	var drainer:Node=root.get_node_or_null("AssetWorkerDrainer")
	deadline=Time.get_ticks_msec()+10000
	while drainer!=null and not drainer.jobs.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(drainer==null or drainer.jobs.is_empty(),mode+": cancelled or completed worker releases its template lease")
func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd");controls.enable_white_materials();controls.discard_map_textures=true
	var base:="D:/code/rmmo_runtime/cache/world3d/white_native_assets_v1"
	var info:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base.path_join("3ecafd6e86b1daa421b6bd21a20cb102deed3e7ced4c14c47f44b680c9c32576.json")))
	var packed:=ResourceLoader.load(base.path_join(info.payload_sha+".scn"),"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	Compare.prepared(packed)
	var folder:="D:/code/rmmo_runtime/cache/initial_asset_specs_%d"%Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("source.gltf");FileAccess.open(path,FileAccess.WRITE).store_string("{}")
	var record:Dictionary={"uuid":"instance","kind":"asset","asset_path":path,"position":[14,2,-5],"rotation":[0,42,0],"size":[1.1,.9,1.2],"collision":"walk"}
	var doc:=preload("res://scripts/world3d/world_document.gd").new()
	var old:=preload("res://scripts/world3d/instance_spec_preparation.gd").new()
	old.begin(doc._asset(record,{"template":packed}),false,0);old.advance(0)
	for mode:String in ["complete","cancel","free"]:await run_case(mode,packed,record,old.specs)
	print("INITIAL_ASSET_SPECS checks=",checks," failures=",failures);quit(1 if failures else 0)
