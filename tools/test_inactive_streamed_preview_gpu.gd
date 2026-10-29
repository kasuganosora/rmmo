extends "res://tools/test_editor_native_ui_gpu.gd"
## Real loaded STEX with startup streaming disabled. Exercise presentation of
## already prepared materials; this does not claim split-preparer Compatibility.
const NativeProduct=preload("res://scripts/world3d/streamed_texture_product.gd")
const Collector=preload("res://scripts/world_editor/streamed_preview_observer.gd")

func bound_scene(texture:Texture2D)->Node3D:
	var scene:=fixture()
	var material:StandardMaterial3D=scene.get_node("TexturedCube").mesh.surface_get_material(0)
	material.albedo_texture=texture
	return scene

func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	folder=Prep.Paths.external_root()
	if not folder.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(45).timeout.connect(func():printerr("INACTIVE_STEX_UI watchdog");quit(2))
	check(not ProjectSettings.get_setting("rendering/textures/streaming/enabled",true),"startup streaming is disabled for the real resident-STEX case")
	original=fixture()
	var pixels:=texture_of(original).get_image()
	check(pixels.has_mipmaps() and pixels.get_mipmap_count()==8,"independent source contains a real nine-level fine-pattern chain")
	var path:=folder.path_join("inactive_multi_mip.stex")
	var file:=FileAccess.open(path,FileAccess.WRITE)
	check(NativeProduct.write(file,pixels)==OK,"write real multi-mip native product outside the project")
	file.close();file=null;pixels=null
	var native:Texture2D=ClassDB.instantiate("StreamedTexture2D")
	check(native.call("load",path)==OK,"load actual STEX bytes through the native engine reader")
	report.native={"class":native.get_class(),"width":native.get_width(),"height":native.get_height(),"mip":native.call("get_streaming_mip_level"),"active":native.call("is_streaming_active"),"rid":native.get_rid().get_id(),"stex_sha256":FileAccess.get_sha256(path)}
	check(native.get_width()==256 and native.get_height()==256 and native.get_rid().is_valid() and not report.native.active and report.native.mip==0,"loaded native texture is real full-resolution residency with no streaming state")
	var reference:WeakRef=weakref(native)
	var cache_before:=Assets._scenes.size()
	var host:=Node.new();root.add_child(host)
	var preview:=Preview.new();preview.size=Vector2(384,288);host.add_child(preview)
	preview.scene=bound_scene(native);preview.current_path=path;preview.visible=true;preview._show_scene()
	var thumbnail:=Thumbnails.new();host.add_child(thumbnail)
	var png:=folder.path_join("inactive_thumbnail.png")
	thumbnail._output=png;thumbnail._busy=true
	thumbnail._present_model(bound_scene(native),path,true)
	var source_preview:=baseline_for(preview.viewport_,preview.camera)
	var source_thumbnail:=baseline_for(thumbnail._viewport,thumbnail._camera)
	var collector:=Collector.new();collector.capture(preview.scene)
	check(collector.snapshot().textures==0 and collector.live_textures().is_empty(),"collector excludes actual loaded inactive StreamedTexture2D from observation")
	var deadline:=Time.get_ticks_msec()+15000
	while (preview._readiness.active() or thumbnail._busy) and Time.get_ticks_msec()<deadline:
		await process_frame
	await Presentation.drawn()
	report.preview=preview._readiness.snapshot();report.thumbnail=thumbnail._readiness.snapshot()
	report.preview_error=preview.streaming_error
	check(preview.visible and preview.streaming_error.is_empty() and report.preview.state=="complete" and not preview.is_processing(),"fully resident STEX preview completes and stops processing")
	check(FileAccess.file_exists(png),"fully resident STEX reaches the real thumbnail PNG publication")
	check(report.preview.profile.begins==0 and report.thumbnail.profile.begins==0 and report.preview.profile.queries==0 and report.thumbnail.profile.queries==0,"resident-only controls never enter the native observation API")
	check(report.preview.profile.draws==1 and report.thumbnail.profile.draws==1,"resident-only controls each finish one real plain draw")
	var displayed:=preview.viewport_.get_texture().get_image()
	var expected:=source_preview.get_texture().get_image()
	report.preview_mismatch=mismatch(displayed,expected)
	check(report.preview_mismatch==0,"fully resident native preview exactly matches independent source RGBA")
	capture_file("inactive_preview",displayed);capture_file("inactive_source",expected)
	if FileAccess.file_exists(png):
		var actual:=Image.load_from_file(png);var source:=source_thumbnail.get_texture().get_image()
		report.png_mismatch=mismatch(actual,source)
		check(report.png_mismatch==0,"persisted resident-native thumbnail matches independent source RGBA")
		capture_file("inactive_thumbnail",actual);capture_file("inactive_thumbnail_source",source)
	else:check(false,"persisted resident-native thumbnail matches independent source RGBA")
	var before_preview:Dictionary=preview._readiness.profile.duplicate();var before_thumbnail:Dictionary=thumbnail._readiness.profile.duplicate()
	for frame:int in 12:await process_frame
	check(preview._readiness.profile==before_preview and thumbnail._readiness.profile==before_thumbnail,"completed resident controls do not restart queries or redraws")
	check(int(Engine.get_singleton("TextureStreaming").call("get_memory_budget_bytes_used"))==0,"non-streaming resident textures never enter engine streaming accounting")
	preview.free();thumbnail.free();host.free();source_preview.free();source_thumbnail.free();original.free();original=null;native=null;collector.clear()
	for frame:int in 8:await process_frame
	check(reference.get_ref()==null,"plain presentation releases its real native texture owner")
	check(Assets._scenes.size()==cache_before,"direct presentation does not populate global asset cache")
	finish()
