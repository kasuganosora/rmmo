extends "res://tools/test_parallel_draw_recording.gd"
## Same visible binding histories on the main RD's real GPU frame ring.
## Render-thread callbacks signal completion through the main message queue.
signal callback_done
var ring_frames:=0

func complete_callback()->void:
	callback_done.emit()

func setup_main_device()->void:
	rd=RenderingServer.get_rendering_device()
	check(rd!=null,"main rendering device")
	if rd!=null:
		ring_frames=rd.get_frame_delay();check(ring_frames>=2,"main GPU frame ring has multiple slots")
		prepare();prepare_targets()
	complete_callback.call_deferred()

func encode_main_frame(iteration:int)->void:
	for i:int in targets.size():encode_target(i,1024,iteration)
	complete_callback.call_deferred()

func verify_main_frame(iteration:int)->void:
	var pixels:Array[String]=[]
	for i:int in targets.size():pixels.append(verify_target(i,iteration))
	rows.append({"iteration":iteration,"lists":targets.size(),"draws":targets.size()*1028,"pixel_sha256":pixels})
	complete_callback.call_deferred()

func release_main_resources()->void:
	for i:int in range(owned.size()-1,-1,-1):rd.free_rid(owned[i])
	owned.clear();targets.clear();target_textures.clear();shaders.clear();pipelines.clear();sets.clear()
	complete_callback.call_deferred()

func run()->void:
	check(not output.is_empty() and DisplayServer.get_name()!="headless","output and real GPU")
	# Repeat creation, frame-slot reuse and disposal on the same main device.
	for generation:int in 2:
		RenderingServer.call_on_render_thread(setup_main_device)
		await callback_done
		if not failures.is_empty():break
		for step:int in 9:
			var iteration:=generation*9+step
			RenderingServer.call_on_render_thread(encode_main_frame.bind(iteration))
			await callback_done
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			RenderingServer.call_on_render_thread(verify_main_frame.bind(iteration))
			await callback_done
		RenderingServer.call_on_render_thread(release_main_resources)
		await callback_done
		for idle:int in ring_frames+2:await RenderingServer.frame_post_draw
	var result:={"checks":checks,"failures":failures,"rows":rows,"expected_draw_commands":expected_draws,"main_ring_frames":ring_frames,"requested_secondary_lists":OS.get_environment("RMMO_SECONDARY_DRAW_LISTS"),"scope":"Main RD real frame ring, render-thread operations, two generations of eight targets, changing visible binding histories over 18 batches and frame-delayed destruction. Not a map performance sample."}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("PARALLEL_DRAW_MAIN checks=",checks," failures=",failures.size());quit(1 if not failures.is_empty() else 0)
