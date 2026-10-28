extends "res://tools/test_editor_native_only.gd"
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
class Gate extends RefCounted:
	var mutex:=Mutex.new()
	var semaphore:=Semaphore.new()
	var entered:=false
	func active()->bool:
		mutex.lock();var value:=entered;mutex.unlock();return value
	func run(task:Callable)->Dictionary:
		mutex.lock();entered=true;mutex.unlock();semaphore.wait()
		return task.call()
class GatedJob extends "res://scripts/world_editor/load_job.gd":
	var gate:=Gate.new()
	func _enqueue_textures(key:String,requested:Dictionary,root_:String)->void:
		super._enqueue_textures(key,requested,root_)
		_preparation.rows[key].task=gate.run.bind(_preparation.rows[key].task)

func run()->void:
	create_timer(60).timeout.connect(func():quit(2))
	var folder:=Paths.cache_directory("surface_texture_plan_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var manager:=root.get_node("AssetManager");var previous:String=manager.content_root_override;manager.content_root_override=folder
	var source:=folder.path_join("asset/model.glb");var texture_path:=folder.path_join("surface.png")
	var pixels:=Image.create(32,32,false,Image.FORMAT_RGB8);pixels.fill(Color(.3,.5,.8));pixels.save_png(texture_path)
	var definition:={"texture_path":texture_path}
	var first:={"uuid":"first","kind":"asset","asset_path":source,"surface_paint":[{"material":definition}]}
	var second:={"uuid":"second","kind":"box","surface_paint":[{"material":definition}]}
	for scenario:String in ["missing_native","cached_native"]:
		if scenario=="cached_native":
			check(not publish(folder,source,"texture_plan").is_empty(),"publish isolated native fixture without GLB")
			var scene:=Library.instantiate(source);check(scene!=null,"actual native owner enters library cache")
			if scene!=null:scene.free()
		Paint.refresh_sources()
		var job:=LoadJob.new();root.add_child(job);job._timings.build={"units":{}}
		job._begin_asset_lookahead([first,second])
		check(job._texture_tasks.has("first") and not job._texture_tasks.has("second"),scenario+": first consumer owns the sole shared texture plan")
		var asset:Dictionary=await job._prepare_asset(first)
		check(asset.has("scene") and asset.scene==null if scenario=="missing_native" else asset.get("template") is PackedScene,scenario+": missing/native-cached model semantics unchanged")
		var packet:Dictionary=await job._prepare_record_textures(first)
		var previous_images:=LoadJob.TerrainTextures.install(packet)
		var owner:=Paint.texture(definition)
		LoadJob.TerrainTextures.restore(previous_images,packet.failed);job._release_texture_payload(packet)
		var shared:Dictionary=await job._prepare_record_textures(second)
		check(owner!=null and shared.get("owners",{}).get(Paint.texture_key(texture_path))==owner,scenario+": second record borrows the actual published owner")
		job._release_texture_payload(shared)
		var queue:Node=job._preparation;var ledger:RefCounted=queue.ledger
		check(queue.metrics.started==1 and queue.ledger.count()==0,scenario+": exactly one decode and no unused result lease")
		job.free();asset.clear();owner=null
		var deadline:=Time.get_ticks_msec()+10000
		while ledger.count()>0 and Time.get_ticks_msec()<deadline:await process_frame
		check(ledger.count()==0,scenario+": all work drains on close")
		check(not FileAccess.file_exists(source),scenario+": no GLB source is read or created")
	# Stop a real ordinary-paint worker before decoding. Destroying its host must
	# hand ownership to the tree drainer without waiting for this blocked worker.
	Paint.refresh_sources()
	var pending:=GatedJob.new();root.add_child(pending);pending._timings.build={"units":{}};pending._begin_asset_lookahead([second])
	var deadline:=Time.get_ticks_msec()+10000
	while not pending.gate.active() and Time.get_ticks_msec()<deadline:await process_frame
	check(pending.gate.active(),"ordinary surface worker is in flight before cancellation")
	var gate:Gate=pending.gate;var ledger:RefCounted=pending._preparation.ledger
	pending.free();check(ledger.count()>0,"cancel returns while blocked pixels still own their budget")
	gate.semaphore.post();deadline=Time.get_ticks_msec()+10000
	while (ledger.count()>0 or not Drainer.for_tree(self).jobs.is_empty()) and Time.get_ticks_msec()<deadline:await process_frame
	check(ledger.count()==0 and ledger.reserved_bytes==0 and Drainer.for_tree(self).jobs.is_empty(),"cancelled ordinary surface decode joins and returns every budget lease")
	check(Paint.retained_texture(Paint.texture_key(texture_path))==null,"cancelled decode publishes no texture")
	Library.evict_cached_scene(source);manager.content_root_override=previous
	print("EDITOR_SURFACE_TEXTURE_PLAN_FAILED=",failures);quit(1 if failures else 0)
