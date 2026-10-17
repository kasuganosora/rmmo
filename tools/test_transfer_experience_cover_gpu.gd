extends SceneTree
## Private-desktop GPU presentation checks; no user scene or character involved.
const Cover=preload("res://scripts/world3d/transfer_loading.gd")
var failures:=0
var checks:=0
var directory:="D:/code/rmmo_runtime/review_artifacts/transfer_experience_20261017"
var evidence:Dictionary={"screenshots":[],"checks":[]}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	checks+=1;if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label_);evidence.checks.append({"ok":ok,"label":label_})
func cover_task(cover:CanvasLayer,state:Dictionary)->void:state.ok=await cover.wait_until_drawn();state.done=true
func reveal_task(cover:CanvasLayer,state:Dictionary)->void:state.ok=await cover.reveal();state.done=true
func shot(label_:String)->void:
	await RenderingServer.frame_post_draw
	var img:=root.get_texture().get_image();var path:=directory.path_join(label_+".webp")
	check(img.save_webp(path,true,.9)==OK,"save Q90 WebP "+label_)
	evidence.screenshots.append({"path":path,"sha256":FileAccess.get_sha256(path),"quality":90,"lossy":true,"width":img.get_width(),"height":img.get_height(),"encoder":"Godot Image.save_webp(lossy=true,quality=.9)"})
func run()->void:
	create_timer(60).timeout.connect(func():quit(2))
	root.size=Vector2i(1024,720);root.content_scale_size=root.size;DirAccess.make_dir_recursive_absolute(directory)
	var source:=ColorRect.new();source.color=Color(.5,.7,.9);source.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(source)
	var cover:=Cover.new();root.add_child(cover)
	check(not await cover.reveal() and not await cover.finish(),"unprepared cover cannot grant ready/reveal")
	var state:={"done":false};cover_task(cover,state)
	var partial:=false;var early_budget:=false
	while not state.done:
		partial=partial or (cover.opacity>0 and cover.opacity<1)
		early_budget=early_budget or cover.is_opaque_drawn()
		await process_frame
	check(partial and not early_budget and state.ok and cover.is_opaque_drawn(),"actual fade has intermediate opacity; covered permission waits for opaque rendered frame")
	check(not cover._column.visible,"fast transfer suppresses waiting text")
	var center:=root.get_texture().get_image().get_pixel(512,200)
	check(center.r<.08 and center.g<.08 and center.b<.1,"opaque GPU frame fully conceals source color")
	cover.started_ms-=Cover.SLOW_HINT_MS;cover.update_progress("准备目标附近通行导航",4,9)
	check(cover._column.visible and cover._label.text.contains("4 / 9") and not cover._hint.text.is_empty(),"slow waiting exposes real stage count and elapsed hint")
	await shot("waiting")
	root.disable_3d=true
	check(not await cover.finish() and not await cover.reveal(),"disabled destination rendering cannot open readiness/reveal")
	root.disable_3d=false
	var wrong_camera:=Camera3D.new()
	check(not await cover.finish(wrong_camera),"unmounted target camera cannot authorize first frame")
	wrong_camera.free()
	check(await cover.finish() and cover.opacity==1 and cover.phase=="ready","first destination frame still leaves opaque cover for authority checks")
	check(cover.milestones.ready_frame>cover.drawn_frame,"destination marker follows opaque frame")
	state={"done":false};reveal_task(cover,state);partial=false
	var reveal_budget_safe:=true
	while not state.done:
		partial=partial or (cover.opacity>0 and cover.opacity<1)
		reveal_budget_safe=reveal_budget_safe and not cover.is_opaque_drawn()
		await process_frame
	check(reveal_budget_safe,"revealing frames cannot claim covered work budget")
	check(state.ok and partial and cover.opacity==0,"reveal completes gradual fade after explicit permission")
	evidence.timeline=cover.profile();var old_stage:String=cover.stage;cover.retire()
	cover.update_progress("late worker callback")
	check(cover.stage==old_stage,"retired cover ignores late progress without touching detached viewport")
	await process_frame
	var failure:=Cover.new();root.add_child(failure);await failure.wait_until_drawn()
	var clicked:={"count":0}
	failure.show_failure("目标区域无法安全恢复；请返回角色选择。",func():clicked.count+=1)
	await process_frame;await process_frame
	await shot("failure")
	for pressed:bool in [true,false]:
		var mouse:=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=pressed;mouse.position=failure._back.get_global_rect().get_center();root.push_input(mouse,true);await process_frame
	check(clicked.count==1 and failure.is_opaque_drawn(),"real GUI mouse dispatch activates failure exit once while retaining cover")
	for pressed:bool in [true,false]:
		var key:=InputEventKey.new();key.keycode=KEY_ENTER;key.pressed=pressed;root.push_input(key,true);await process_frame
	check(clicked.count==2,"focused failure action also accepts keyboard confirmation")
	check(not await failure.reveal(),"failure never opens reveal even after a drawn frame")
	failure.retire();await process_frame
	var dying:=Cover.new();root.add_child(dying);state={"done":false};cover_task(dying,state)
	await process_frame;root.remove_child(dying)
	while not state.done:await process_frame
	check(not state.ok and dying.drawn_frame<0,"tree exit cancels in-flight fade without publishing a stale draw marker")
	dying.free()
	var hidden:=SubViewport.new();hidden.size=Vector2i(64,64);hidden.render_target_update_mode=SubViewport.UPDATE_DISABLED;root.add_child(hidden)
	var hidden_cover:=Cover.new();hidden.add_child(hidden_cover)
	check(not await hidden_cover.wait_until_drawn() and hidden_cover.drawn_frame<0,"another viewport global draw cannot authorize a disabled target viewport")
	hidden.free();source.free()
	evidence.passed=checks-failures;evidence.failures=failures
	FileAccess.open(directory.path_join("cover_gpu.json"),FileAccess.WRITE).store_string(JSON.stringify(evidence,"  "))
	print("TRANSFER_EXPERIENCE_COVER_FINISHED passed=",checks-failures," failures=",failures);quit(1 if failures else 0)
