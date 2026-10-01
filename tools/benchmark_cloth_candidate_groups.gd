extends "res://tools/benchmark_cloth_replay.gd"
func run()->void:
	create_timer(600).timeout.connect(func():push_error("Candidate group comparison timeout");quit(2))
	var results:Array=[]
	var sizes:=[64,32,16,8,8,16,32,64]
	for index in sizes.size():
		var flags:=PackedStringArray(["--uncapped","--world-motion","--input-spikes","--candidate-group-size",str(sizes[index]),"--stage","groups88_%d"%index])
		flags.append("--serial-candidates")
		var result=await run_case(flags)
		if result==null:return
		results.append({"group_size":result.candidate_group_size,"median_ms":result.median_ms,"p95_ms":result.p95_ms,"max_ms":result.frame_times.max(),"functional_pass":result.functional_pass,"stage":result.stage})
	var file:=FileAccess.open(Art.review_path("character_3d/runtime_performance_06/groups88.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  "));file.close();quit()
