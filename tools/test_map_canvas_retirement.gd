extends SceneTree
## Actual retained radar commands, including live clear/rebind and shutdown.
const Layer=preload("res://scripts/ui/world_map_terrain_layer.gd")
const Data=preload("res://scripts/world3d/world_map_data.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
class Host extends Node2D:
	func _prepare_terrain()->bool:return false
var failures:Array=[]
var timings:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func populate(layer:Node,count:int,color:Color)->RefCounted:
	var data:=Data.new()
	for i in count:
		var offset:=Vector2(i%32*4,i/32%32*4)
		var polygon:=PackedVector2Array([offset,offset+Vector2(4,0),offset+Vector2(4,4),offset+Vector2(0,4),offset])
		data.shapes.append({"polygon":polygon,"bounds":Rect2(offset,Vector2(4,4)),"color":color})
	layer.prepare(data,.25)
	for i in count:layer._record(i,.25)
	layer.show_shapes(data.shapes,.25);layer.set_process(false)
	return data
func pixel()->Color:
	await process_frame;await RenderingServer.frame_post_draw
	return root.get_texture().get_image().get_pixel(2,2)
func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	root.size=Vector2i(128,128);root.content_scale_size=root.size
	RenderingServer.set_default_clear_color(Color.BLACK)
	check(DisplayServer.get_name()!="headless","retirement uses real Vulkan canvas commands")
	var service:Node=Retirement._service()
	var host:=Host.new();root.add_child(host)
	var layer:=Layer.new();host.add_child(layer)
	for count:int in [1563,4096]:
		var source:=populate(layer,count,Color.RED)
		check((await pixel()).r>.5,"old radar is visible before clear")
		var before:int=service.profile.get("canvas_items",0)
		var started:=Time.get_ticks_usec();layer.clear();var elapsed:=Time.get_ticks_usec()-started
		service.set_process(false)
		check(elapsed<8000,"clear detaches commands without a concentrated RID destruction stall")
		check(not service.pending.is_empty(),"old canvas ownership enters the shared retirement queue")
		check((await pixel()).r<.2,"old drawing disappears while disposal remains pending")
		check(source.shapes.size()==count,"clear leaves borrowed map shapes unchanged")
		var replacement:=populate(layer,1,Color.GREEN)
		service.set_process(false)
		check((await pixel()).g>.5,"new radar is visible before old ownership drains")
		service.set_process(true)
		var frames:=0
		while not service.pending.is_empty() and frames<600:await process_frame;frames+=1
		check(service.pending.is_empty() and service.known.is_empty(),"all old RIDs drain with no orphan ticket")
		check(int(service.profile.get("canvas_items",0))-before==count,"every old canvas RID is freed exactly once")
		check((await pixel()).g>.5 and replacement.shapes.size()==1,"old disposal never removes new map commands")
		timings.append({"count":count,"clear_us":elapsed,"drain_frames":frames,"canvas_max_slice_us":service.profile.get("canvas_max_slice_us",0)})
		layer.clear()
		while not service.pending.is_empty():await process_frame
	# Shutdown has no future frame; it must drain the exact same queue.
	populate(layer,128,Color.BLUE);var before:int=service.profile.get("canvas_items",0)
	layer.clear();service._exit_tree()
	check(service.pending.is_empty() and service.known.is_empty() and int(service.profile.get("canvas_items",0))-before==128,"shutdown synchronously drains remaining owned canvas handles")
	# When the service is exiting, live clear must still synchronously release.
	populate(layer,32,Color.RED);layer.clear()
	check(service.pending.is_empty() and (await pixel()).r<.2,"shutdown fallback leaves no visible or queued canvas items")
	host.free()
	var report:={"timings":timings,"profile":service.profile,"failures":failures}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
