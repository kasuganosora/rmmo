extends SceneTree
## Probe whether the real loading cover (2D frames, disabled 3D) continues the
## engine budget scheduler. No explicit streaming flush or hidden 3D scene.
const Product=preload("res://scripts/world3d/streamed_texture_product.gd")
var failures:Array[String]=[]
var report:Dictionary={}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func bytes_used()->int:return int(Engine.get_singleton("TextureStreaming").call("get_memory_budget_bytes_used"))
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	var folder:String=ProjectSettings.get_setting("rmmo/content_root");DirAccess.make_dir_recursive_absolute(folder)
	create_timer(15).timeout.connect(func():quit(2))
	root.disable_3d=true
	var cover:=ColorRect.new();cover.color=Color.BLACK;cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(cover)
	var image:=Image.create(256,256,false,Image.FORMAT_RGBA8);image.fill(Color(.2,.4,.6));image.generate_mipmaps()
	var path:=folder.path_join("cover.stex");var file:=FileAccess.open(path,FileAccess.WRITE)
	check(Product.write(file,image)==OK,"write isolated native mip chain");file.close();image=null
	var texture:Texture2D=ClassDB.instantiate("StreamedTexture2D");check(texture.call("load",path)==OK,"load native output under opaque 2D cover")
	report.counter_immediately_after_load=bytes_used()
	var start:=Time.get_ticks_msec();var frames:=0
	while bytes_used()==0 and Time.get_ticks_msec()-start<3000:await process_frame;frames+=1
	report.first_counter_bytes=bytes_used();report.first_counter_msec=Time.get_ticks_msec()-start;report.process_frames=frames
	check(root.disable_3d and root.get_camera_3d()==null,"probe has no 3D view or camera")
	check(bytes_used()>0,"2D covered frames advance engine residency without explicit flush")
	var weak:WeakRef=weakref(texture);texture=null
	for frame:int in 4:await process_frame;await RenderingServer.frame_post_draw
	start=Time.get_ticks_msec()
	while bytes_used()!=0 and Time.get_ticks_msec()-start<3000:await process_frame
	report.final_counter_bytes=bytes_used();report.owner_alive=weak.get_ref()!=null
	check(bytes_used()==0 and weak.get_ref()==null,"2D covered frames also retire engine residency without explicit flush")
	report.failures=failures
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STREAMED_COVER_BUDGET ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
