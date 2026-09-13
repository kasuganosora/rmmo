extends SceneTree
## Headless: character-create compose_preview still produces valid sheets after cache opts.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var MV = load("res://scripts/char/mv_generator.gd")
	failed += _expect(MV != null, "mv_generator loads")
	if MV == null:
		_finish(failed)
		return

	MV.clear_cache()
	MV.warmup("female")
	var slots: Array = MV.slots_for("female")
	failed += _expect(slots.size() >= 8, "slots_for female has appearance rows")
	var parts: Dictionary = MV.default_parts("female")
	failed += _expect(parts.has("Eyes") and parts.has("Body"), "default_parts has Eyes+Body")
	var colors := {"skin": 0, "hair": 10}
	var res: Dictionary = MV.compose_preview("female", parts, colors)
	failed += _expect(res.has("frames") and res.has("portrait") and res.has("sheet"), "compose_preview keys")
	var frames: SpriteFrames = res["frames"]
	failed += _expect(frames != null and frames.has_animation("walk_front"), "walk_front animation")
	if frames != null and frames.has_animation("walk_front"):
		failed += _expect(frames.get_frame_count("walk_front") == 3, "walk_front 3 frames")
	var portrait: Texture2D = res["portrait"]
	failed += _expect(portrait != null and portrait.get_width() == 144, "portrait 144 wide")
	var sheet: Image = res["sheet"]
	failed += _expect(sheet != null and sheet.get_width() == 144 and sheet.get_height() == 192, "TV sheet 144x192")

	var res2: Dictionary = MV.compose_preview("female", parts, colors)
	failed += _expect(res2["frames"] == res["frames"], "same-key preview reuses frames")
	failed += _expect(res2["portrait"] == res["portrait"], "same-key preview reuses portrait")

	var eyes: PackedInt32Array = MV.list_variants("Face", "female", "Eyes")
	failed += _expect(eyes.size() > 1, "Eyes has variants")
	if eyes.size() > 1:
		parts["Eyes"] = eyes[1]
		var res3: Dictionary = MV.compose_preview("female", parts, colors)
		failed += _expect(res3["frames"] == res["frames"], "Face-only change reuses TV frames")
		failed += _expect(res3["portrait"] != res["portrait"], "Face-only change rebuilds portrait")
		var p3: Texture2D = res3["portrait"]
		failed += _expect(p3 != null and p3.get_width() == 144, "rebuilt portrait 144")

	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)
