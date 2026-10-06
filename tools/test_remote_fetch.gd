extends SceneTree
## Headless: AssetManager remote content fetch (download + sha256 verify + ensure()).
## Driven by tools/run_remote_fetch_test.sh which stands up a local HTTP server and
## passes RMMO_TEST_REMOTE_URL / RMMO_TEST_CONTENT_ROOT / RMMO_TEST_SHA.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var am: Node = root.get_node_or_null("AssetManager")
	failed += _expect(am != null, "AssetManager autoload present")
	if am == null:
		_finish(failed)
		return

	var url_base := OS.get_environment("RMMO_TEST_REMOTE_URL").strip_edges()
	var croot := OS.get_environment("RMMO_TEST_CONTENT_ROOT").strip_edges()
	var sha := OS.get_environment("RMMO_TEST_SHA").strip_edges()
	if url_base == "" or croot == "":
		print("SKIP no RMMO_TEST_REMOTE_URL/CONTENT_ROOT env")
		_finish(failed)
		return

	am.content_root_override = croot
	am.set_remote(url_base)
	failed += _expect(am.remote_configured(), "remote_configured() true")

	# --- URL mapping ---
	var u: String = am.remote_url_for("content://charset/testremote")
	failed += _expect(u == url_base + "/assets/charset/testremote.png",
		"remote_url_for maps content tree (got %s)" % u)
	failed += _expect(am.remote_url_for("content://map_pack/foo") == "",
		"map_pack not single-file fetchable")

	# --- fetch_remote_file happy path + integrity ---
	var dest: String = croot + "/dl/testremote.png"
	var r: Dictionary = am.fetch_remote_file(u, dest)
	failed += _expect(bool(r.get("ok", false)), "fetch ok (err=%s code=%s)" % [str(r.get("error", "")), str(r.get("code", 0))])
	failed += _expect(FileAccess.file_exists(dest), "downloaded file exists")
	failed += _expect(int(r.get("bytes", 0)) > 0, "bytes > 0")
	failed += _expect(str(r.get("sha256", "")).to_lower() == sha.to_lower(), "reported sha256 matches server file")
	failed += _expect(not FileAccess.file_exists(dest + ".part"), ".part cleaned up")

	# --- explicit sha256 verify: correct hash accepted, wrong rejected ---
	var ok_dest: String = croot + "/dl/ok.png"
	var r_ok: Dictionary = am.fetch_remote_file(u, ok_dest, sha)
	failed += _expect(bool(r_ok.get("ok", false)), "correct expected-sha accepted")
	var bad_dest: String = croot + "/dl/bad.png"
	var r_bad: Dictionary = am.fetch_remote_file(u, bad_dest, "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
	failed += _expect(not bool(r_bad.get("ok", false)), "sha256 mismatch rejected")
	failed += _expect(not FileAccess.file_exists(bad_dest), "rejected download not kept")

	# --- 404 handling ---
	var r404: Dictionary = am.fetch_remote_file(url_base + "/assets/charset/does_not_exist.png", croot + "/dl/none.png")
	failed += _expect(not bool(r404.get("ok", false)), "404 rejected")
	failed += _expect(int(r404.get("code", 0)) == 404, "404 code surfaced (got %s)" % str(r404.get("code", 0)))

	# --- ensure() end-to-end: missing -> remote fetch -> has() ---
	failed += _expect(not am.has("content://charset/testremote"), "not present before ensure")
	var e: int = am.ensure("content://charset/testremote")
	failed += _expect(e == OK, "ensure() pulled from remote (err=%d)" % e)
	failed += _expect(am.has("content://charset/testremote"), "has() true after ensure()")

	# Clean up override so nothing leaks.
	am.set_remote("")
	am.content_root_override = ""
	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("ALL PASS test_remote_fetch")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)
