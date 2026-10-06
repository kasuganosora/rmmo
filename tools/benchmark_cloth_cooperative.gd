extends "res://tools/benchmark_cloth_replay.gd"
func run()->void:
	create_timer(600).timeout.connect(func():push_error("Cooperative candidate timeout");quit(2))
	var results:Array=[]
	for index in 4:
		var flags:=PackedStringArray(["--uncapped","--world-motion","--input-spikes","--stage","cooperative88_%d"%index])
		if index in [1,2]:flags.append("--cooperative-candidates")
		else:flags.append("--serial-candidates")
		var result=await run_case(flags)
		if result==null:return
		results.append({"cooperative":result.cooperative_candidates,"median_ms":result.median_ms,"p95_ms":result.p95_ms,"max_ms":result.frame_times.max(),"functional_pass":result.functional_pass,"stage":result.stage})
	var file:=FileAccess.open(Art.review_path("character_3d/runtime_performance_06/cooperative88.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  "));file.close();quit()
