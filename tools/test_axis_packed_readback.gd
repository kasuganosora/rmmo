extends SceneTree
const GPU=preload("res://scripts/char/female_axis_gpu.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(120).timeout.connect(func():push_error("Packed body timeout");quit(2))
	var model=preload("res://scripts/char/character_model_3d.gd").create("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":0}},{})
	root.add_child(model);model.set_process(false)
	var body=model.axis_rig.body
	var original=GPU.new();original.packed_readback=false
	assert(original.initialize(Art.path("characters/base/female_base_v2")))
	var packed=body.gpu;assert(packed!=null and packed.packed_readback)
	var old_ms:Array[float]=[];var new_ms:Array[float]=[]
	for i in 20:
		assert(body.set_shape_values({"height":float(i%3-1)*.3,"bust_size":.2}))
		body.set_angles({"lShldr":Vector3(i*2,0,0),"rThigh":Vector3(i,0,0)},Vector3(.13,-.04,.02))
		assert(original.set_rest_points(body.rest_points))
		var pair:Array=[original,packed] if i%2==0 else [packed,original]
		for gpu in pair:
			var start:=Time.get_ticks_usec()
			gpu.evaluate(body.nodes,body.solved_bones,body.bulge_scale,body.root_offset)
			(old_ms if gpu==original else new_ms).append((Time.get_ticks_usec()-start)/1000.0)
		assert(original.last_positions==packed.last_positions,"Position texture bytes changed")
		assert(original.last_normals==packed.last_normals,"Normal texture bytes changed")
		assert(original.last_points==packed.last_points,"Contact points changed")
		assert(original.last_min_y==packed.last_min_y,"Ground support changed")
	old_ms.sort();new_ms.sort()
	original.close();original.close();model.free()
	for i in 4:await process_frame
	print("PASS 20 packed body outputs byte-identical, shape/pose/root offset and repeated close; original median_ms=",old_ms[10]," packed median_ms=",new_ms[10]);quit()
