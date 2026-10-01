extends "res://tools/benchmark_cloth_replay.gd"
## Forward/reverse mode order in one engine; shares the canonical replay inputs.
func run()->void:
	create_timer(600).timeout.connect(func():push_error("Replay matrix timeout");quit(2))
	var results:Array=[]
	for index in 8:
		var mode:String=["reference","combined","substep","both","both","substep","combined","reference"][index]
		var flags:=PackedStringArray(["--uncapped","--world-motion","--input-spikes","--candidate-threshold",".08","--stage","matrix_%d_%s"%[index,mode]])
		if mode in ["reference","combined"]:flags.append("--frame-candidates")
		if mode in ["reference","substep"]:flags.append("--split-contacts")
		var result=await run_case(flags)
		if result==null:return
		results.append(result)
	var file:=FileAccess.open(Art.review_path("character_3d/runtime_performance_06/replay_matrix.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  "));file.close();quit()
