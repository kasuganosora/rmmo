extends SceneTree
## Headless: AssetManager.load_state() loading-snapshot API for the loading screen.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var am: Node = root.get_node_or_null("AssetManager")
	failed += _expect(am != null, "AssetManager autoload present")
	if am == null:
		_finish(failed)
		return
	failed += _expect(am.has_method("load_state"), "load_state() exists")

	var st: Dictionary = am.load_state()
	failed += _expect(typeof(st) == TYPE_DICTIONARY, "load_state returns Dictionary")
	for key in ["busy", "progress", "pending", "inflight", "active", "ensuring",
			"gate_phase", "gate_fraction", "gate_label",
			"cache_entries", "cache_bytes", "budget_soft_mb", "budget_hard_mb"]:
		failed += _expect(st.has(key), "snapshot has %s" % key)

	# Idle after boot: nothing queued/in-flight, not busy, progress complete.
	failed += _expect(int(st.get("pending", -1)) == 0, "idle pending == 0")
	failed += _expect(int(st.get("inflight", -1)) == 0, "idle inflight == 0")
	failed += _expect(int(st.get("active", -1)) == 0, "idle active == 0")
	failed += _expect(bool(st.get("busy", true)) == false, "idle not busy")
	failed += _expect(float(st.get("progress", -1.0)) >= 0.0 and float(st.get("progress", -1.0)) <= 1.0, "progress in 0..1")

	# gate_progress recording feeds the polled snapshot.
	if am.has_signal("gate_progress"):
		am.emit_signal("gate_progress", "ensure", 0.5, "校验素材 1/2")
		var st2: Dictionary = am.load_state()
		failed += _expect(str(st2.get("gate_phase", "")) == "ensure", "gate_phase recorded")
		failed += _expect(abs(float(st2.get("gate_fraction", 0.0)) - 0.5) < 0.001, "gate_fraction recorded")
		failed += _expect(str(st2.get("gate_label", "")) == "校验素材 1/2", "gate_label recorded")
		failed += _expect(bool(st2.get("busy", false)) == true, "busy during gate")
		failed += _expect(abs(float(st2.get("progress", 0.0)) - 0.5) < 0.001, "progress uses gate fraction")
		# A finished gate clears the busy/gate state.
		am.emit_signal("gate_progress", "done", 1.0, "资源就绪")
		var st3: Dictionary = am.load_state()
		failed += _expect(bool(st3.get("busy", true)) == false, "not busy after gate done")

	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("ALL PASS test_load_state")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)
