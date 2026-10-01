extends "res://tools/benchmark_cloth_replay.gd"
func run()->void:
	create_timer(600).timeout.connect(func():push_error("Cache comparison timeout");quit(2))
	var results:Array=[]
	var margins:=[.012,.04,.08,.12,.12,.08,.04,.012]
	for index in margins.size():
		var flags:=PackedStringArray(["--uncapped","--world-motion","--input-spikes","--candidate-padding",str(margins[index]),"--stage","cache87_%d"%index])
		var result=await run_case(flags)
		if result==null:return
		results.append({"padding":margins[index],"median_ms":result.median_ms,"p95_ms":result.p95_ms,"functional_pass":result.functional_pass,"stage":result.stage})
	var file:=FileAccess.open(Art.review_path("character_3d/runtime_performance_06/cache87.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  "));file.close();quit()
