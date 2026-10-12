extends SceneTree
## CPU-only exact UUID lookup microprobe. No editor scene or content writes.
const Doc = preload("res://scripts/world3d/world_document.gd")
var checks := 0
var failed := false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var selection: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://review_artifacts/house_audit_selection_20261011.json"))
	var before: String = FileAccess.get_sha256(selection.map)
	if before != selection.map_sha: quit(1); return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(selection.map))
	var doc = Doc.new()
	doc.records = data.nodes[0].extras.rmmo_records
	var wanted: Array = []
	for building: Dictionary in data.nodes[0].extras.building_instances.values():
		wanted.append_array(building.parts.values())
	var positions: Dictionary = {}
	for i: int in doc.records.size(): positions[str(doc.records[i].uuid)] = i + 1
	var comparisons := 0
	for id: String in wanted: comparisons += int(positions[id])
	var rounds: Array = []
	for mode: String in ["production_linear_find", "operation_local_index", "operation_local_index", "production_linear_find"]:
		var started := Time.get_ticks_usec()
		var index: Dictionary = {}
		if mode == "operation_local_index":
			for record: Dictionary in doc.records: index[str(record.uuid)] = record
		var misses := 0
		for id: String in wanted:
			var record: Dictionary = doc._find(id) if mode == "production_linear_find" else index.get(id, {})
			checks += 1
			if record.get("uuid", "") != id: misses += 1
		var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0
		if misses != 0: failed = true
		rounds.append({"mode": mode, "elapsed_ms": elapsed_ms, "misses": misses})
		print("HOUSE_INDEX ", mode, " ms=", elapsed_ms)
	checks += 1
	if FileAccess.get_sha256(selection.map) != before: failed = true
	var result: Dictionary = {"scope": "CPU-only UUID lookup component of list_buildings/conflicts. Uses original compact-record UUID order and production WorldDocument._find, versus diagnostic operation-local index including build time. NOT full HTTP/conflict validation or marquee benchmark; production unchanged.", "map_sha": before, "records": doc.records.size(), "owned_parts": wanted.size(), "linear_uuid_comparisons_per_round": comparisons, "rounds": rounds, "checks": checks, "failed": failed}
	var file := FileAccess.open("res://review_artifacts/house_index_work_cpu_20261011.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  ")); file.close()
	print("HOUSE_INDEX checks=", checks, " failed=", failed)
	quit(1 if failed else 0)
