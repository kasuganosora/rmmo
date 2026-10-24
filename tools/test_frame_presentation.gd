extends SceneTree
const Frames=preload("res://scripts/util/frame_presentation.gd")
var checks:=0
var failures:=0
var raw_post_on_main:=0
var raw_post_off_main:=0
var serials:Array=[]
var called:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _raw_post()->void:
	if Thread.is_main_thread():raw_post_on_main+=1
	else:raw_post_off_main+=1
func _presented(serial:int)->void:serials.append([serial,Thread.is_main_thread()])
func _called(tag:String)->void:called.append([tag,Thread.is_main_thread(),Frames.clock().completed])
func run()->void:
	check(not OS.has_feature("rmmo_game_render_thread"),"script runs never opt into the game render thread model")
	if DisplayServer.get_name()=="headless":
		Frames.after_drawn(_called.bind("headless"))
		for i in 4:await process_frame
		check(called.is_empty() and Frames.clock().completed==0,"a server that never draws never reports a presented frame")
		print("FRAME_PRESENTATION checks=",checks," failures=",failures)
		quit(0 if failures==0 else 1);return
	RenderingServer.frame_post_draw.connect(_raw_post)
	var frames:RefCounted=Frames.clock()
	frames.presented.connect(_presented)
	var viewport:=SubViewport.new();viewport.size=Vector2i(8,8);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg=false
	var rect:=ColorRect.new();rect.size=Vector2(8,8);viewport.add_child(rect);root.add_child(viewport)
	await Frames.drawn()
	# Every resume must observe its own change, never the frame still in flight.
	var colors:Array[Color]=[Color(1,0,0),Color(0,1,0),Color(0,0,1),Color(1,1,0),Color(0,1,1),Color(1,0,1)]
	var stale:=0;var off_main:=0
	for round_index in 24:
		var expected:Color=colors[round_index%colors.size()]
		rect.color=expected
		var target:int=Frames.next_serial()
		await Frames.drawn()
		if not Thread.is_main_thread():off_main+=1
		var pixel:Color=viewport.get_texture().get_image().get_pixel(4,4)
		if not pixel.is_equal_approx(expected) or frames.completed<target:stale+=1
	# Control: the raw signal may report an older frame under the separate model.
	var raw_stale:=0
	for round_index in 12:
		var expected:Color=colors[(round_index+3)%colors.size()]
		rect.color=expected
		await RenderingServer.frame_post_draw
		if not viewport.get_texture().get_image().get_pixel(4,4).is_equal_approx(expected):raw_stale+=1
	print("FRAME_PRESENTATION raw_post_draw_stale=",raw_stale,"/12")
	check(off_main==0,"drawn() always resumes on the main thread")
	check(stale==0,"each awaited frame contains the change made before awaiting it (stale=%d)"%stale)
	var monotonic:=true;var on_main:=true
	for i in serials.size():
		on_main=on_main and bool(serials[i][1])
		if i>0 and int(serials[i][0])!=int(serials[i-1][0])+1:monotonic=false
	check(serials.size()>=24 and monotonic,"presented serials are contiguous and increasing (%d frames)"%serials.size())
	if not monotonic:print("FRAME_PRESENTATION serials=",serials.map(func(row:Array)->int:return int(row[0])))
	check(on_main,"presented is emitted on the main thread")
	called.clear()
	var doomed:=Node.new()
	Frames.after_drawn(_called.bind("first"));Frames.after_drawn(doomed.set_name.bind("gone"));Frames.after_drawn(_called.bind("second"))
	var expected_serial:int=Frames.next_serial()
	doomed.free()
	await Frames.drawn();await process_frame
	check(called.size()==2 and called[0][0]=="first" and called[1][0]=="second","after_drawn runs each callback once in order and skips freed receivers")
	check(called.all(func(row:Array)->bool:return bool(row[1]) and int(row[2])>=expected_serial),"after_drawn callbacks run on the main thread after their frame")
	print("FRAME_PRESENTATION model=",("safe" if RenderingServer.is_on_render_thread() else "separate")," raw_post_main=",raw_post_on_main," raw_post_render=",raw_post_off_main)
	viewport.free()
	RenderingServer.frame_post_draw.disconnect(_raw_post)
	print("FRAME_PRESENTATION checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
