extends SceneTree
## Use the actual map-footprint draw command producer on real Vulkan canvas
## items. Compare per-child parent removal with a single owned group detachment.
const Footprint=preload("res://scripts/ui/world_map_footprint.gd")
var failures:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func trial(count:int,grouped:bool)->Dictionary:
	var node:=Node2D.new();root.add_child(node)
	var parent:RID=node.get_canvas_item();var group:=RID()
	if grouped:
		group=RenderingServer.canvas_item_create();RenderingServer.canvas_item_set_parent(group,parent);parent=group
	var items:Array[RID]=[]
	for i in count:
		var item:=RenderingServer.canvas_item_create();items.append(item);RenderingServer.canvas_item_set_parent(item,parent)
		var offset:=Vector2(i%32*4,i/32%32*4)
		var polygon:=PackedVector2Array([offset,offset+Vector2(4,0),offset+Vector2(4,4),offset+Vector2(0,4),offset])
		Footprint.draw(item,polygon,Color.RED,.25)
	await process_frame;await RenderingServer.frame_post_draw
	var before:=root.get_texture().get_image().get_pixel(2,2)
	check(before.r>.5 and before.g<.2,"real canvas footprint is drawn before retirement")
	var started:=Time.get_ticks_usec()
	if group.is_valid():RenderingServer.free_rid(group)
	for item:RID in items:RenderingServer.free_rid(item)
	var elapsed:=Time.get_ticks_usec()-started
	items=[];node.queue_free()
	await process_frame;await RenderingServer.frame_post_draw
	var after:=root.get_texture().get_image().get_pixel(2,2)
	check(after.r<.2,"all retired canvas commands disappear")
	return {"count":count,"grouped":grouped,"release_us":elapsed}
func run()->void:
	root.size=Vector2i(128,128);root.content_scale_size=root.size;root.transparent_bg=false
	RenderingServer.set_default_clear_color(Color.BLACK)
	check(DisplayServer.get_name()!="headless","canvas retirement uses the real renderer")
	var results:Array=[]
	for count in [1563,4096]:
		for grouped in [false,true,true,false]:results.append(await trial(count,grouped))
	var report:={"trials":results,"failures":failures}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
