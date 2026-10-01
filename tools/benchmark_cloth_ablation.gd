extends "res://tools/benchmark_cloth_replay.gd"
## Diagnostic subtraction, never runtime quality defaults. Keep clock identical.
func run()->void:
	create_timer(600).timeout.connect(func():push_error("Ablation timeout");quit(2))
	var results:Array=[]
	var modes:=["full","no_cloth","iter12","iter8","steps2","steps2","iter8","iter12","no_cloth","full"]
	for index in modes.size():
		var mode:String=modes[index]
		var flags:=PackedStringArray(["--uncapped","--world-motion","--input-spikes","--stage","ablation_%d_%s"%[index,mode]])
		if mode=="no_cloth":flags.append("--without-cloth")
		if mode.begins_with("iter"):flags.append_array(["--iterations",mode.trim_prefix("iter")])
		if mode=="steps2":flags.append_array(["--substeps","2"])
		var result=await run_case(flags)
		if result==null:return
		results.append({"mode":mode,"median_ms":result.median_ms,"p95_ms":result.p95_ms,"functional_pass":result.functional_pass,"stage":result.stage})
	var file:=FileAccess.open(Art.review_path("character_3d/runtime_performance_06/ablation.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  "));file.close();quit()
