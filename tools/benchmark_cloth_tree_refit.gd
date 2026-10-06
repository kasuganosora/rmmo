extends "res://tools/benchmark_cloth_replay.gd"
func run()->void:
	create_timer(600).timeout.connect(func():push_error("Tree refit comparison timeout");quit(2))
	var results:Array=[]
	for index in 4:
		var flags:=PackedStringArray(["--uncapped","--world-motion","--input-spikes","--stage","refit88_%d"%index])
		flags.append("--serial-candidates")
		if index in [1,2]:flags.append("--refit-tree")
		var result=await run_case(flags)
		if result==null:return
		results.append({"refit":result.substep_tree_refit,"median_ms":result.median_ms,"p95_ms":result.p95_ms,"max_ms":result.frame_times.max(),"functional_pass":result.functional_pass,"stage":result.stage})
	var file:=FileAccess.open(Art.review_path("character_3d/runtime_performance_06/refit88.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  "));file.close();quit()
