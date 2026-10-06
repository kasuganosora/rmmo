extends SceneTree
## Headless: AssetManager manifest-driven whole map-pack remote fetch.
## Driven by tools/run_remote_pack_test.sh (local HTTP server + a multi-file pack).


func _init() -> void:
	call_deferred("_run")


func _rm(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		DirAccess.remove_absolute("%s/%s" % [path, f])
	for sub in d.get_directories():
		_rm("%s/%s" % [path, sub])
	DirAccess.remove_absolute(path)


func _run() -> void:
	var failed := 0
	var am: Node = root.get_node_or_null("AssetManager")
	failed += _expect(am != null, "AssetManager autoload present")
	if am == null:
		_finish(failed)
		return
	var url_base := OS.get_environment("RMMO_TEST_REMOTE_URL").strip_edges()
	var croot := OS.get_environment("RMMO_TEST_CONTENT_ROOT").strip_edges()
	if url_base == "" or croot == "":
		print("SKIP no RMMO_TEST_REMOTE_URL/CONTENT_ROOT env")
		_finish(failed)
		return
	am.content_root_override = croot
	am.set_remote(url_base)

	var pdir := "%s/packs/map_pack/testpack" % croot

	# --- manifest URL mapping ---
	var mu: String = am.remote_pack_manifest_url_for("testpack")
	failed += _expect(mu == url_base + "/packs/map_pack/testpack/pack.manifest.json",
		"manifest url maps (got %s)" % mu)

	# --- whole-pack fetch: 3 files ---
	var r: Dictionary = am.ensure_remote_pack("testpack")
	failed += _expect(bool(r.get("ok", false)), "pack fetch ok (err=%s)" % str(r.get("error", "")))
	failed += _expect(int(r.get("downloaded", -1)) == 3, "downloaded 3 files (got %s)" % str(r.get("downloaded", -1)))
	failed += _expect(int(r.get("skipped", -1)) == 0, "skipped 0 on first fetch")
	failed += _expect(FileAccess.file_exists("%s/pack.json" % pdir), "pack.json downloaded")
	failed += _expect(FileAccess.file_exists("%s/Map001.json" % pdir), "Map001.json downloaded")
	failed += _expect(FileAccess.file_exists("%s/sub/extra.json" % pdir), "nested sub/extra.json downloaded")
	failed += _expect(am.has("content://map_pack/testpack"), "has(map_pack) true after fetch")

	# --- resume: everything already present + matching sha -> skipped ---
	var r2: Dictionary = am.ensure_remote_pack("testpack")
	failed += _expect(bool(r2.get("ok", false)) and int(r2.get("skipped", 0)) == 3 and int(r2.get("downloaded", 0)) == 0,
		"resume skips all (dl=%s skip=%s)" % [str(r2.get("downloaded", 0)), str(r2.get("skipped", 0))])

	# --- corrupt one file -> only that file re-downloaded ---
	var cf := FileAccess.open("%s/Map001.json" % pdir, FileAccess.WRITE)
	cf.store_string("CORRUPTED")
	cf.close()
	var r3: Dictionary = am.ensure_remote_pack("testpack")
	failed += _expect(bool(r3.get("ok", false)) and int(r3.get("downloaded", 0)) == 1 and int(r3.get("skipped", 0)) == 2,
		"corrupt file re-fetched (dl=%s skip=%s)" % [str(r3.get("downloaded", 0)), str(r3.get("skipped", 0))])

	# --- ensure() end-to-end: remove local, pull via content ref ---
	_rm(pdir)
	failed += _expect(not am.has("content://map_pack/testpack"), "not present after local wipe")
	var e: int = am.ensure("content://map_pack/testpack")
	failed += _expect(e == OK, "ensure() pulled whole pack (err=%d)" % e)
	failed += _expect(am.has("content://map_pack/testpack"), "has(map_pack) true after ensure()")

	# --- missing pack -> failure ---
	var rn: Dictionary = am.ensure_remote_pack("nope_missing_pack")
	failed += _expect(not bool(rn.get("ok", false)), "missing pack manifest -> fail")

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
		print("ALL PASS test_remote_pack")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)
