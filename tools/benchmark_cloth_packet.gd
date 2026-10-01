extends SceneTree
const Packet=preload("res://addons/godot_gpu_cloth/src/cloth_indexed_packet.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	if preload("res://tools/gpu_shader_review_manifest.gd").collect().is_empty():quit(2);return
	var view=preload("res://scripts/char/character_view_3d.gd").new();root.add_child(view)
	view.configure("female",{"body_model":"female_base_v2"},{"SurfaceEquipment":{"Clothing2":"maid_separate/item_01"},"SurfaceClothSlots":["Clothing2"]})
	while not view.model.axis_rig.cloth.is_ready():await process_frame
	view.model.set_process(false)
	await RenderingServer.frame_post_draw
	var adapter=view.model.axis_rig.cloth.entries.Clothing2.adapter
	var plain=Packet.new();plain.packed_readback=false
	var packed=Packet.new();packed.packed_readback=true
	for builder in [plain,packed]:assert(builder.initialize(adapter.body_triangles,adapter.body.posed_points.size(),0))
	var times:Array=[[],[]]
	for round_index in 105:
		# Reverse order on alternate rounds to limit thermal/scheduler order bias.
		for index in ([0,1] if round_index%2==0 else [1,0]):
			var builder=plain if index==0 else packed
			var start:=Time.get_ticks_usec()
			assert(builder.build(adapter.body.posed_points,adapter.body.root_offset,PackedVector3Array()))
			if round_index>=5:times[index].append((Time.get_ticks_usec()-start)/1000.0)
		assert(plain.output==packed.output)
	for values in times:values.sort()
	var result:Dictionary={"frames_per_mode":100,"triangles":adapter.body_triangles.size()/3,"plain_median_ms":times[0][50],"packed_median_ms":times[1][50],"plain_p95_ms":times[0][94],"packed_p95_ms":times[1][94],"bytes_exact":true}
	var file:=FileAccess.open(Art.review_path("character_3d/runtime_performance_06/packet_paired.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	plain.close();packed.close();view.free()
	for i in 4:await process_frame
	print("PACKET ",result);quit()
