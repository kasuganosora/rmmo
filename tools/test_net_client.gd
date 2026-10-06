extends SceneTree
## Headless: NetClient contract + Net.server() provider indirection.


const Net = preload("res://scripts/net/net.gd")
const NetClient = preload("res://scripts/net/net_client.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0

	# --- Contract base declares the lifecycle signals ---
	var base: Node = NetClient.new()
	for sig in NetClient.REQUIRED_SIGNALS:
		failed += _expect(base.has_signal(sig), "NetClient declares signal %s" % sig)
	base.free()

	# --- required_methods() aggregates the full surface ---
	var req: Array = NetClient.required_methods()
	failed += _expect(req.size() >= 140, "contract lists full method surface (got %d)" % req.size())
	failed += _expect("try_move" in req and "snapshot_party" in req and "enter_world" in req, "contract covers try_/snapshot_/core")

	# --- MockServer (the current scaffold) satisfies the contract ---
	var mock: Node = root.get_node_or_null("MockServer")
	failed += _expect(mock != null, "MockServer autoload present")
	if mock != null:
		var report: Dictionary = NetClient.validate(mock)
		if not bool(report.get("ok", false)):
			print("  missing_methods=", report.get("missing_methods", []))
			print("  missing_signals=", report.get("missing_signals", []))
			print("  missing_properties=", report.get("missing_properties", []))
		failed += _expect(bool(report.get("ok", false)), "MockServer satisfies NetClient contract")

	# --- A bare node fails validation and reports gaps ---
	var bare := Node.new()
	var bad: Dictionary = NetClient.validate(bare)
	failed += _expect(not bool(bad.get("ok", true)), "bare Node fails contract")
	failed += _expect((bad.get("missing_methods", []) as Array).size() > 100, "bare Node missing most methods")
	failed += _expect((bad.get("missing_signals", []) as Array).size() == 4, "bare Node missing all signals")
	bare.free()

	# --- Provider indirection: default is MockServer, injection overrides, clear restores ---
	failed += _expect(not Net.has_server_override(), "no override by default")
	failed += _expect(Net.server() == mock, "server() defaults to MockServer")

	var fake := Node.new()
	fake.name = "FakeTransport"
	root.add_child(fake)
	Net.set_server(fake)
	failed += _expect(Net.has_server_override(), "override active after set_server")
	failed += _expect(Net.server() == fake, "server() returns injected transport")
	Net.clear_server_override()
	failed += _expect(not Net.has_server_override(), "override cleared")
	failed += _expect(Net.server() == mock, "server() restored to MockServer")
	fake.free()

	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("ALL PASS test_net_client")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)
