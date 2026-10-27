extends SceneTree

func _initialize() -> void:
	var method := &"rmmo_test_shader_decode_contract"
	if not ClassDB.class_has_method(&"RenderingDevice", method):
		printerr("SHADER_DECODE_CONTRACT_MISSING_API")
		quit(2)
		return
	var result: Dictionary = ClassDB.class_call_static(&"RenderingDevice", method)
	print("SHADER_DECODE_CONTRACT_JSON ", JSON.stringify(result))
	var expected_red := OS.get_environment("RMMO_EXPECT_DECODE_RED") == "1"
	var failures := int(result.get("failed", -1))
	var expected_failures := 8 if expected_red else 0
	var success := failures == expected_failures and int(result.get("seed_decode_calls", 0)) == 14 and int(result.get("probe_decode_calls", 0)) == 14 and int(result.get("gpu_calls", -1)) == 0
	for row: Dictionary in result.get("cases", []):
		success = success and bool(row.get("seed_ok", false)) and bool(row.get("seed_bytes_match", false)) and bool(row.get("same_scratch_allocation", false))
		var expected_actual := true if expected_red else bool(row.get("expected_ok", false))
		success = success and bool(row.get("actual_ok", false)) == expected_actual
		if bool(row.get("expected_ok", false)):
			success = success and bool(row.get("valid_output_bytes_match", false))
		if expected_red and str(row.get("case", "")).begins_with("short_raw_"):
			success = success and bool(row.get("prior_stage_tail_visible", false))
	print("SHADER_DECODE_CONTRACT_EXPECTED_", "RED" if expected_red else "GREEN", " ", "PASS" if success else "FAIL")
	quit(0 if success else 1)
