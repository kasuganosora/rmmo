extends SceneTree
## Fixed authored pixels, fixed upload count, bounded ready/in-flight textures.
## Compare main vs background creation INCLUDING real draw and retirement frames.
## This is an independent GPU stress fixture, not a map-loading benchmark.
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
class UploadQueue extends RefCounted:
	var mutex:=Mutex.new()
	var credit:=Semaphore.new()
	var rows:Array=[]
	var claimed:=0
	var produced:=0
	var live:=0
	var peak_live:=0
	var limit:=64
	var stopped:=false
	func _init(count:int)->void:
		limit=count;credit.post();credit.post()
	func produce(image:Image)->void:
		while true:
			credit.wait();mutex.lock()
			if stopped or claimed>=limit:mutex.unlock();credit.post();return
			var id:=claimed;claimed+=1;live+=1;peak_live=maxi(peak_live,live);mutex.unlock()
			var began:=Time.get_ticks_usec();var texture:=ImageTexture.create_from_image(image)
			var ended:=Time.get_ticks_usec()
			mutex.lock();rows.append({"id":id,"texture":texture,"start_us":began,"end_us":ended,"thread":OS.get_thread_caller_id()});produced+=1;mutex.unlock()
	func take()->Dictionary:
		mutex.lock();var row:Dictionary={} if rows.is_empty() else rows.pop_front();mutex.unlock();return row
	func consumed()->void:
		mutex.lock();live-=1;mutex.unlock();credit.post()
	func cancel()->void:
		mutex.lock();stopped=true;mutex.unlock();credit.post();credit.post()
var failures:=0
var checks:=0
var frames:Array=[]
var phase:=""
var previous:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func observe()->void:
	var now:=Time.get_ticks_usec()
	if previous>0:frames.append({"at_us":now,"us":now-previous,"phase":phase})
	previous=now
func upload_row(image:Image,id:int)->Dictionary:
	var began:=Time.get_ticks_usec()
	var texture:=ImageTexture.create_from_image(image)
	return {"id":id,"texture":texture,"start_us":began,"end_us":Time.get_ticks_usec(),"thread":OS.get_thread_caller_id()}
func verify_pixels(texture:ImageTexture,image:Image,expected:PackedByteArray)->void:
	var actual:=texture.get_image()
	check(actual!=null and actual.get_format()==image.get_format() and actual.get_data()==expected,"GPU readback retains exact authored pixels and every mip")
func run()->void:
	var output:="";var manifest:="";var workers:=0;var count:=64
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--image-manifest="):manifest=arg.trim_prefix("--image-manifest=")
		elif arg.begins_with("--workers="):workers=arg.trim_prefix("--workers=").to_int()
		elif arg.begins_with("--count="):count=arg.trim_prefix("--count=").to_int()
	if output.is_empty() or FileAccess.file_exists(output) or manifest.is_empty() or workers<0 or workers>2 or count<4 or count>256 or DisplayServer.get_name()=="headless":
		push_error("Require private GPU desktop, new output, image manifest, 0..2 workers and 4..256 uploads");quit(2);return
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(manifest))
	var source_sha:=FileAccess.get_sha256(source.path)
	var image:Image=Pixels.image(source.path,bool(source.flip))
	check(image!=null,"authored upload pixels prepared by production decoder")
	if image==null:quit(1);return
	check(image.get_format()==int(source.format) and image.get_width()==int(source.width) and image.get_height()==int(source.height) and image.get_data_size()==int(source.bytes),"pixel format, dimensions and full mip bytes match actual map trace")
	var expected:=image.get_data()
	if failures:quit(1);return
	root.size=Vector2i(640,480);Engine.max_fps=0
	preload("res://scripts/util/display_state.gd").set_vsync_mode(DisplayServer.VSYNC_DISABLED,root.get_window_id())
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,0,3);camera.current=true
	var visual:=MeshInstance3D.new();visual.mesh=QuadMesh.new();root.add_child(visual)
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;visual.material_override=material
	var tiny:=Image.create(2,2,false,Image.FORMAT_RGBA8);tiny.fill(Color.WHITE)
	material.albedo_texture=ImageTexture.create_from_image(tiny)
	# Warm only the same tiny rendered material/geometry on both controls.
	# The first real-size upload and staging-buffer growth remain in measurement.
	for i:int in 24:await process_frame
	var queue:=UploadQueue.new(count);var threads:Array=[]
	var first:ImageTexture;var last:ImageTexture;var ids:Dictionary={};var uploads:Array=[]
	var started:=Time.get_ticks_usec();phase="upload";previous=started;process_frame.connect(observe)
	for i:int in workers:
		var worker:=Thread.new();check(worker.start(queue.produce.bind(image))==OK,"background upload worker starts");threads.append(worker)
	var main_max:=0;var main_total:=0;var submitted:=0;var deadline:=started+120000000;var unique:=true
	while submitted<count and Time.get_ticks_usec()<deadline:
		var row:Dictionary={};var began:=Time.get_ticks_usec()
		if workers==0:
			row=upload_row(image,submitted)
		else:row=queue.take()
		if not row.is_empty():
			unique=unique and not ids.has(row.id) and row.texture!=null
			ids[row.id]=true;last=row.texture
			if first==null:first=last
			material.albedo_texture=last
			uploads.append({"id":row.id,"start_us":row.start_us,"end_us":row.end_us,"thread":row.thread,"bound_frame":Engine.get_frames_drawn()})
			submitted+=1
			if workers>0:queue.consumed()
		row={}
		var cost:=Time.get_ticks_usec()-began;main_max=maxi(main_max,cost);main_total+=cost
		await process_frame
	# The final texture is actually drawn before the measured upload phase ends.
	await RenderingServer.frame_post_draw
	var elapsed:=Time.get_ticks_usec()-started
	check(unique and submitted==count and ids.size()==count,"all fixed work rendered without duplicate IDs")
	if workers>0:check(queue.produced==count and queue.peak_live<=2,"producer keeps the two-texture admission bound")
	phase="drain"
	queue.cancel()
	while threads.any(func(thread:Thread)->bool:return thread.is_alive()):await process_frame
	for worker:Thread in threads:worker.wait_to_finish()
	phase="oracle";RenderingServer.force_sync()
	verify_pixels(first,image,expected);verify_pixels(last,image,expected)
	check(image.get_data()==expected and FileAccess.get_sha256(source.path)==source_sha,"immutable CPU pixels and authored source preserved")
	var first_ref:WeakRef=weakref(first);var last_ref:WeakRef=weakref(last)
	phase="retirement";var retire_started:=Time.get_ticks_usec();previous=retire_started
	material.albedo_texture=null;first=null;last=null;queue.rows.clear();queue=null
	for i:int in 24:await process_frame
	var retire_us:=Time.get_ticks_usec()-retire_started
	process_frame.disconnect(observe)
	check(first_ref.get_ref()==null and last_ref.get_ref()==null,"final ImageTexture owners released after worker drain and material detach")
	var report:={"checks":checks,"failures":failures,"workers":workers,"count":count,"source":source,"source_sha":source_sha,"upload_bytes":image.get_data_size()*submitted,"main_total_us":main_total,"main_max_us":main_max,"elapsed_us":elapsed,"retire_us":retire_us,"uploads":uploads,"frames":frames,"contract":"Fixed upload work; two pending/in-flight textures plus displayed/first-oracle owners. First full-size transfer included; GPU readback outside upload timing. Uncapped real draw; no GDB. Not map timing or actual VRAM measurement."}
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
	visual.free();camera.free();print("TEXTURE_TRANSFER ",JSON.stringify({"checks":checks,"failures":failures,"workers":workers,"elapsed_us":elapsed,"main_max_us":main_max}));quit(1 if failures else 0)
