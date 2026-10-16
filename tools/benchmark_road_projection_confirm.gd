extends "res://tools/benchmark_road_projection.gd"
## Larger follow-up because the first OFF run also moved unaffected controls.
## Keep every original fixture and all raw samples, including prior runs.
func initialize()->bool:
	var ok:=super.initialize()
	report.script_sha256["res://tools/benchmark_road_projection_confirm.gd"]=FileAccess.get_sha256("res://tools/benchmark_road_projection_confirm.gd")
	return ok

func run()->void:
	sample_pairs=40;calibration_pairs=12
	super.run()
