extends "res://tools/benchmark_cloth_replay.gd"
func run()->void:
 create_timer(600).timeout.connect(func():push_error("Display comparison timeout");quit(2))
 var results:Array=[]
 for index in 4:
  var flags:=PackedStringArray(["--uncapped","--world-motion","--input-spikes","--stage","display_precise90_%d"%index])
  if index in [0,3]:flags.append("--cpu-display")
  var result=await run_case(flags)
  if result==null:return
  results.append({"gpu_display":result.gpu_display,"median_ms":result.median_ms,"p95_ms":result.p95_ms,"max_ms":result.frame_times.max(),"stage":result.stage})
 var file:=FileAccess.open(Art.review_path("character_3d/runtime_performance_06/display_precise90.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify(results,"  "));file.close();quit()
