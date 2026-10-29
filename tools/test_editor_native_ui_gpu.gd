extends "res://tools/test_editor_native_texture_join_gpu.gd"
## Real controls/service/tracker. Observer subclasses call every production
## method unchanged and record only mip levels and viewport readback evidence.
const Service=preload("res://scripts/world_editor/editor_asset_preparation.gd")
const Preview=preload("res://scripts/world_editor/asset_preview.gd")
const Thumbnails=preload("res://scripts/world_editor/asset_thumbnails.gd")
const Ownership=preload("res://scripts/world_editor/prepared_model_ownership.gd")
const Presentation=preload("res://scripts/util/frame_presentation.gd")
const Prefabs=preload("res://scripts/world_editor/prefab_library.gd")
var original:Node3D
var observations:Dictionary={}
var captures:Dictionary={}
var baselines:Dictionary={}
var native_refs:Array[WeakRef]=[]
var ui_host:Node
var service:Node
var tracker:Node

class ReadinessObserver extends "res://scripts/world_editor/streamed_preview_readiness.gd":
	var trace:Array=[]
	func _draw(phase:String)->void:
		trace.append({"event":"draw","phase":phase,"frame":Engine.get_process_frames()})
		super._draw(phase)
	func _queried(result:Dictionary,serial:int,query_serial:int,verifying:bool)->void:
		trace.append({"event":"query","verifying":verifying,"frame":Engine.get_process_frames(),"result":result.duplicate(true)})
		super._queried(result,serial,query_serial,verifying)
	func _finish(ok:bool,error:String="",error_code:int=OK)->void:
		trace.append({"event":"finish","ok":ok,"error":error,"frame":Engine.get_process_frames()})
		super._finish(ok,error,error_code)

class PreviewObserver extends "res://scripts/world_editor/asset_preview.gd":
	var observe:Callable
	var observe_draw:Callable
	var first_scheduled:=false
	func _init()->void:_readiness=ReadinessObserver.new()
	func _show_scene()->void:
		super._show_scene()
		if scene!=null and observe.is_valid():observe.call(self)
	func _process(delta:float)->void:
		super._process(delta)
		if not first_scheduled and _readiness.profile.draws>0:
			first_scheduled=true
			Presentation.after_drawn(observe_draw.bind(self))

class ThumbnailObserver extends "res://scripts/world_editor/asset_thumbnails.gd":
	var observe:Callable
	func _init()->void:_readiness=ReadinessObserver.new()
	func _present_model(model:Node3D,key:String,importing:bool)->void:
		super._present_model(model,key,importing)
		if model!=null and observe.is_valid():observe.call("bound",self)
	func _finish(serial:int)->void:
		if serial==_render_serial and is_inside_tree() and is_instance_valid(_model) and observe.is_valid():observe.call("capture",self)
		super._finish(serial)

func fixture()->Node3D:
	var scene:=Node3D.new();scene.name="FineMipCube"
	var pixels:=Image.create(256,256,false,Image.FORMAT_RGBA8)
	for y:int in 256:
		for x:int in 256:
			var checker:bool=((x/4+y/4)%2)==0
			var color:=Color(.95,.12,.06) if checker else Color(.04,.65,.95)
			if x%32<2 or y%32<2:color=Color.WHITE
			if x%32>=16 and y%32>=16:color=Color(.95,.85,.05) if (x+y)%4<2 else Color(.03,.08,.15)
			pixels.set_pixel(x,y,color)
	pixels.generate_mipmaps()
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.albedo_texture=ImageTexture.create_from_image(pixels)
	var box:=BoxMesh.new();box.size=Vector3(2,2,2)
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,box.get_mesh_arrays());mesh.surface_set_material(0,material)
	var node:=MeshInstance3D.new();node.name="TexturedCube";node.mesh=mesh;scene.add_child(node);node.owner=scene
	return scene

func texture_of(scene:Node)->Texture2D:
	for child:Node in scene.find_children("*","MeshInstance3D",true,false):
		var material:Material=child.material_override
		if material==null:material=child.mesh.surface_get_material(0)
		if material is StandardMaterial3D and material.albedo_texture!=null:return material.albedo_texture
	return null

func native_state(scene:Node)->Dictionary:
	var texture:=texture_of(scene)
	if texture==null:return {"missing":true}
	native_refs.append(weakref(texture))
	return {"class":texture.get_class(),"id":texture.get_instance_id(),"rid":texture.get_rid().get_id(),
		"mip":texture.call("get_streaming_mip_level"),"active":texture.call("is_streaming_active"),
		"min_override":texture.call("get_min_lod_override"),"max_override":texture.call("get_max_lod_override"),"frame":Engine.get_process_frames()}

func baseline_for(view:SubViewport,camera:Camera3D)->SubViewport:
	var baseline:=SubViewport.new();baseline.size=view.size;baseline.own_world_3d=true
	baseline.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(baseline)
	baseline.add_child(original.duplicate())
	var fixed:=camera.duplicate() as Camera3D;baseline.add_child(fixed);fixed.current=true
	return baseline

func preview_bound(preview:PreviewObserver)->void:
	if observations.has("preview_bound"):return
	observations.preview_bound=native_state(preview.scene)
	observations.preview_size=[preview.viewport_.size.x,preview.viewport_.size.y]
	baselines.preview=baseline_for(preview.viewport_,preview.camera)

func preview_first(preview:PreviewObserver)->void:
	if not is_instance_valid(preview) or preview.scene==null:return
	observations.preview_first=native_state(preview.scene)
	captures.preview_first=preview.viewport_.get_texture().get_image()

func thumbnail_observed(stage:String,thumbnail:ThumbnailObserver)->void:
	observations["thumbnail_"+stage]=native_state(thumbnail._model)
	if stage=="bound":baselines.thumbnail=baseline_for(thumbnail._viewport,thumbnail._camera)
	else:
		captures.thumbnail_first=thumbnail._viewport.get_texture().get_image()
		observations.thumbnail_ready=thumbnail._readiness.snapshot()
		observations.thumbnail_trace=thumbnail._readiness.trace.duplicate(true)

func mismatch(a:Image,b:Image)->int:
	if a.get_size()!=b.get_size():return -1
	var left:=a.get_data();var right:=b.get_data();var different:=0
	for at:int in left.size():different+=int(left[at]!=right[at])
	return different

func capture_file(label:String,pixels:Image)->void:
	check(pixels.save_png(folder.path_join(label+".png"))==OK,"keep local RGBA "+label)
	check(pixels.save_webp(folder.path_join(label+".webp"),true,.9)==OK,"encode original-size lossy q90 "+label)

func wait_clean(label:String)->void:
	var streaming:=Engine.get_singleton("TextureStreaming");var deadline:=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		tracker.collect_retired(100)
		if ui_host._shared_preparation_ledger.count()==0 and tracker.report().entries==0 and int(streaming.call("get_memory_budget_bytes_used"))==0 and service.snapshot().batches==0:break
		await process_frame
	report[label]={"service":service.snapshot(),"published":tracker.report(),"engine_bytes":streaming.call("get_memory_budget_bytes_used"),"cache_entries":Assets._scenes.size()}
	check(ui_host._shared_preparation_ledger.count()==0 and ui_host._shared_preparation_ledger.reserved_bytes==0,label+": transient ledger zero")
	check(tracker.report().entries==0 and tracker.report().published_envelope_bytes==0,label+": published private geometry zero")
	check(int(streaming.call("get_memory_budget_bytes_used"))==0,label+": final native engine residency zero")
	check(service.snapshot().batches==0 and service.snapshot().groups==0 and service.snapshot().requests==0 and service.snapshot().bundles==0,label+": service requests and finite batches zero")

func run()->void:
	if DisplayServer.get_name()=="headless" or not Prep.Streamed.enabled():quit(2);return
	folder=Prep.Paths.external_root()
	if not folder.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(150).timeout.connect(func():printerr("EDITOR_NATIVE_UI_GPU watchdog");quit(2))
	Paint.refresh_sources();Prep.Pixels.Policy.verify_packages=false
	original=fixture();var prepared:=Products.prepare(original,folder)
	check(prepared.ok and prepared.stats.textures==1,"fine pattern publishes one actual multi-mip STEX")
	var paths:Array=[]
	for label:String in ["ui_first","ui_second","ui_cancel"]:paths.append(publish_fixture(original,prepared,label))
	Products.restore(prepared);prepared.clear()
	ui_host=Host.new();root.add_child(ui_host)
	var preview:=PreviewObserver.new();preview.size=Vector2(384,288);preview.observe=preview_bound;preview.observe_draw=preview_first;ui_host.add_child(preview)
	var sibling:=Preview.new();sibling.size=Vector2(384,288);sibling.position=Vector2(400,0);ui_host.add_child(sibling)
	var thumbnails:=ThumbnailObserver.new();thumbnails.observe=thumbnail_observed;ui_host.add_child(thumbnails)
	service=Service.for_consumer(preview);tracker=Ownership.for_tree(self)
	check(service.native_texture_pool==null and not service.native_texture_preparer.is_valid() and service.ownership_tracker==null,"production service has no preparation or tracker injections")
	var cache_before:=Assets._scenes.size();var png:=folder.path_join("ui_thumbnail.png")
	thumbnails.queue_import({"asset_path":paths[0],"thumbnail_path":png})
	preview.show_asset(paths[0]);sibling.show_asset(paths[0])
	var batch:Dictionary=service._batches.values()[0];var helper:RefCounted=batch.native;batch={}
	var deadline:=Time.get_ticks_msec()+20000
	while (not captures.has("preview_first") or not FileAccess.file_exists(png)) and Time.get_ticks_msec()<deadline:await process_frame
	check(preview.scene!=null and sibling.scene!=null and FileAccess.file_exists(png),"real preview siblings and actual thumbnail queue finish cold preparation")
	if preview.scene==null or not FileAccess.file_exists(png):report.observations=observations;finish();return
	check(service.profile.producers==1 and service.profile.joined==2,"three UI requests share one actual geometry producer")
	report.shared_native=helper.snapshot()
	check(report.shared_native.pool.produced==1 and report.shared_native.pool.streamed_loads==1 and report.shared_native.tables.native_async_reads==1,"UI requests share one real STEX and one table read")
	check(texture_of(preview.scene)==texture_of(sibling.scene),"real preview instances share exact native owner and RID")
	check(Assets._scenes.size()==cache_before,"private UI preparation does not grow the global template cache")
	while preview._readiness.active() and Time.get_ticks_msec()<deadline:await process_frame
	var profiles_before:={"preview":preview._readiness.snapshot(),"thumbnail":thumbnails._readiness.snapshot()}
	for frame:int in 90:
		await process_frame;await RenderingServer.frame_post_draw
		if frame in [0,5,20,60,89]:
			observations["preview_wait_%d"%frame]=native_state(preview.scene)
			observations["preview_wait_%d"%frame].update_mode=preview.viewport_.render_target_update_mode
	captures.preview_frozen=preview.viewport_.get_texture().get_image()
	captures.preview_source=baselines.preview.get_texture().get_image()
	captures.thumbnail_source=baselines.thumbnail.get_texture().get_image()
	captures.thumbnail_png=Image.load_from_file(png)
	report.first_preview_mismatch=mismatch(captures.preview_first,captures.preview_source)
	report.frozen_preview_mismatch=mismatch(captures.preview_frozen,captures.preview_source)
	report.thumbnail_png_mismatch=mismatch(captures.thumbnail_png,captures.thumbnail_source)
	report.first_vs_frozen_mismatch=mismatch(captures.preview_first,captures.preview_frozen)
	# The documented contract permits progressive first presentation. Keep its
	# raw mismatch as evidence; settled UI and persisted PNG remain exact checks.
	check(report.frozen_preview_mismatch==0,"UPDATE_ONCE preview does not retain a lower-mip frame")
	check(report.thumbnail_png_mismatch==0,"persisted thumbnail PNG preserves the settled source detail")
	observations.preview_ready=preview._readiness.snapshot()
	observations.preview_trace=preview._readiness.trace.duplicate(true)
	check(not preview.is_processing() and not preview._readiness.active() and preview._readiness.snapshot().state=="complete","completed preview stops processing after finite native observation")
	check(observations.preview_ready.observation_id==0 and observations.thumbnail_ready.observation_id==0,"both completed controls cancel their non-owning engine tickets")
	check(observations.thumbnail_ready.state=="complete" and not thumbnails._readiness.active(),"thumbnail captures only after finite controller completion")
	check(preview._readiness.profile.draws==profiles_before.preview.profile.draws and thumbnails._readiness.profile.draws==profiles_before.thumbnail.profile.draws,"90 settled frames do not schedule repeated viewport draws")
	check(preview._readiness.profile.queries==profiles_before.preview.profile.queries and thumbnails._readiness.profile.queries==profiles_before.thumbnail.profile.queries,"completed controllers stop repeated observation queries")
	for trace:Array in [observations.preview_trace,observations.thumbnail_trace]:
		check(trace.any(func(row):return row.event=="query" and not row.verifying and row.result.covered and row.result.ready),"actual API reports covered ready before final redraw")
		check(trace.any(func(row):return row.event=="draw" and row.phase=="drawing_verified"),"actual controller requests a fresh verified draw")
		check(trace.any(func(row):return row.event=="query" and row.verifying and row.result.covered and row.result.ready),"same real observation ticket is queried after completed redraw")
	# Diagnostic continuation only after observing untouched production behavior.
	# This requests ordinary rendering feedback, never flushes streaming or pins LOD.
	if report.frozen_preview_mismatch!=0:preview.viewport_.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	report.diagnostic_continuous_enabled=report.frozen_preview_mismatch!=0
	var same:=-1
	for frame:int in 120:
		await process_frame;await RenderingServer.frame_post_draw
		if frame%6!=0:continue
		same=mismatch(preview.viewport_.get_texture().get_image(),captures.preview_source)
		if same==0:break
	observations.preview_continuous=native_state(preview.scene)
	captures.preview_continuous=preview.viewport_.get_texture().get_image()
	report.continuous_preview_mismatch=same
	check(same==0,"ordinary continuous redraw naturally reaches source detail without flush or LOD override")
	for label:String in captures:capture_file(label,captures[label])
	report.observations=observations
	preview.free();sibling.free();thumbnails.free()
	for view:SubViewport in baselines.values():view.free()
	baselines.clear();await wait_clean("after_ui_close")
	await cancellation_cases(paths)
	await prefab_case(paths)
	check(Assets._scenes.size()==cache_before,"all UI operations leave global scene cache unchanged")
	check(native_refs.all(func(ref_):return ref_.get_ref()==null),"observer weak references do not retain native textures")
	report.service_final=service.snapshot();ui_host.free();original.free();original=null
	finish()

func cancellation_cases(paths:Array)->void:
	var preview:=Preview.new();preview.size=Vector2(240,180);ui_host.add_child(preview)
	var before:int=service.profile.cancelled
	preview.show_asset(paths[0]);preview.show_asset(paths[1])
	var deadline:=Time.get_ticks_msec()+15000
	while preview.scene==null and Time.get_ticks_msec()<deadline:await process_frame
	check(preview.scene!=null and preview.current_path==paths[1] and service.profile.cancelled>before,"real rapid selection cancels obsolete request and shows replacement only")
	while preview._readiness.snapshot().observation_id==0 and Time.get_ticks_msec()<deadline:await process_frame
	check(preview._readiness.snapshot().observation_id>0,"replacement preview begins an actual engine observation before owner exit")
	observations.cancel_preview=preview._readiness.snapshot()
	preview.show_asset(paths[2]);preview.free()
	await wait_clean("after_selection_and_owner_exit")
	var thumbnail:=Thumbnails.new();ui_host.add_child(thumbnail)
	var entry:={"asset_path":paths[2],"thumbnail_path":folder.path_join("cancelled_thumbnail.png")}
	thumbnail.set_visible_entries([entry]);thumbnail.queue_import(entry,true)
	deadline=Time.get_ticks_msec()+5000
	while thumbnail._readiness.snapshot().observation_id==0 and Time.get_ticks_msec()<deadline:await process_frame
	check(thumbnail._readiness.snapshot().observation_id>0,"idle thumbnail starts a real engine observation before scrolling away")
	observations.cancel_thumbnail=thumbnail._readiness.snapshot()
	thumbnail.set_visible_entries([]);thumbnail.free()
	await wait_clean("after_thumbnail_scroll_close")
	check(not FileAccess.file_exists(entry.thumbnail_path),"obsolete idle thumbnail does not publish its PNG")

func prefab_case(paths:Array)->void:
	var records:Array=[]
	for index:int in 2:records.append({"kind":"asset","uuid":"prefab_%d"%index,"asset_path":paths[index],"position":[float(index)*3,0,0],"rotation":[0,0,0],"size":[1,1,1],"collision":"none"})
	var path:=folder.path_join("assets/prefabs/ui_pair.json")
	write_json(path,{"format":"rmmo_prefab","version":1,"records":records,"building_instances":{}})
	var entry:={"prefab_path":path};var loaded:=Prefabs.read(entry)
	check(loaded.get("ok",false),"actual prefab reader accepts two native dependencies")
	if not loaded.get("ok",false):report.prefab_error=loaded;return
	var preview:=Preview.new();preview.size=Vector2(320,240);ui_host.add_child(preview)
	var thumb:=Thumbnails.new();ui_host.add_child(thumb)
	var before:int=service.profile.producers;var png:=folder.path_join("prefab_thumbnail.png")
	thumb.queue_import({"prefab_path":path,"thumbnail_path":png});preview.show_prefab(entry)
	var deadline:=Time.get_ticks_msec()+20000
	while (preview.scene==null or not FileAccess.file_exists(png)) and Time.get_ticks_msec()<deadline:await process_frame
	check(preview.scene!=null and preview.scene.get_child_count()==2 and FileAccess.file_exists(png),"real prefab preview and thumbnail complete through the native service")
	check(service.profile.producers-before==2,"prefab UI subscribers produce each native model once")
	preview.free();thumb.free();await wait_clean("after_prefab_ui_close")
