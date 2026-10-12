extends SceneTree
## Explicit offline CPU build; only derived cache files are written.
const Index = preload("res://scripts/world3d/map_dependency_index.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Cursor = preload("res://scripts/world3d/document_open_cursor.gd")
const Snapshot = preload("res://scripts/world3d/document_source_snapshot.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var args := OS.get_cmdline_user_args(); var path := ""; var report_path := ""
	for i in args.size()-1:
		if args[i] == "--map": path = args[i+1]
		if args[i] == "--report": report_path = args[i+1]
	if path.is_empty() or not Paths.allowed(path): print("--map must name an allowed native map"); quit(1); return
	if "--read-only" in args:
		read_only(path, report_path); return
	var started := Time.get_ticks_usec(); var snapshot = Snapshot.read_file(path)
	var native: int = Cursor.native_root(snapshot._data)
	if not snapshot.error.is_empty() or native < 0: print("Invalid map"); quit(1); return
	var restored: Dictionary = Cursor.hydrate_references(snapshot._data.nodes[native].extras,path,Paths.external_root())
	if not restored.ok: print(restored); quit(1); return
	var index := Index.build(path,Paths.external_root(),restored.extras.rmmo_records,snapshot._signature)
	if not index.ok: print(index); quit(1); return
	var reasons := {}; var unique: Dictionary = {}; var classes := {}; var known := 0
	for row: Dictionary in index.rows:
		reasons[row.reason] = int(reasons.get(row.reason,0))+1
		classes[row.classification] = int(classes.get(row.classification,0))+1
		known += int(row.bounds_known)
		if not unique.has(row.reason): unique[row.reason] = {}
		unique[row.reason][row.reference.sha256] = true
	var unique_counts := {}
	for reason in unique: unique_counts[reason] = unique[reason].size()
	var unknown_fields := {}; var unknown_kinds := {}
	for row: Dictionary in index.rows:
		if row.reason != "unknown_geometry": continue
		var record: Dictionary = restored.extras.rmmo_records[row.order]
		var kind: String = str(record.get("kind","")); unknown_kinds[kind] = int(unknown_kinds.get(kind,0))+1
		for field in record:
			if field in Index.COMMON_FIELDS or (kind=="asset" and field in Index.ASSET_FIELDS): continue
			var key := kind+":"+str(field); unknown_fields[key] = int(unknown_fields.get(key,0))+1
	var spawn: Array = index.extras.get("spawn",[0,.9,4]); var origin := Vector3(spawn[0],spawn[1],spawn[2])
	var selected := Index.select(index,[AABB(origin-Vector3(96,100000,96),Vector3(192,200000,192))])
	var report := {"ok":true,"map":path,"source_sha256":snapshot._signature,"source_unchanged":snapshot.matches_disk(),"records":index.rows.size(),"classifications":classes,"reasons":reasons,"unique_definitions_by_reason":unique_counts,"known_bounds":known,"near_selected":selected.selected_count,"near_deferred":selected.deferred_count,"near_unique_definitions":selected.dependencies.size(),"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"index_path":index.index_path,"index_bytes":FileAccess.get_file_as_bytes(index.index_path).size(),"closure_complete":false}
	report.unknown_fields = unknown_fields; report.unknown_kinds = unknown_kinds
	report.building_groups=index.groups.size();report.near_selected_groups=selected.selected_groups.size()
	print(JSON.stringify(report))
	if not report_path.is_empty() and Paths.allowed(report_path): FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit(0 if report.source_unchanged else 1)

func read_only(path: String, report_path: String) -> void:
	var started := Time.get_ticks_usec(); var index := Index.read(path, Paths.external_root())
	if not index.ok: print(index); quit(1); return
	var read_us := Time.get_ticks_usec() - started
	if "--group-probe" in OS.get_cmdline_user_args():
		if index.groups.is_empty(): print("No building groups"); quit(1); return
		var group_id: String = index.groups.keys()[0]; var group: Dictionary = index.groups[group_id]; var requests: Array = []
		for at in group.members:
			var row: Dictionary = index.rows[at]
			requests.append({"record_index":at,"compact_record":index.extras.rmmo_records[at],"bounds":group.bounds,"group_id":group_id,"asset_path":row.asset_path})
		var prepared := preload("res://scripts/world3d/chunk_reference_preparation.gd").prepare(index, requests, path, Paths.external_root())
		var report := {"ok":prepared.error.is_empty(),"error":prepared.error,"group_id":group_id,"source_sha256":index.source_sha256,"index_read_ms":read_us/1000.0,"read_profile":prepared.read_profile,"closure_complete":false,"source_unchanged":FileAccess.get_sha256(path)==index.source_sha256}
		print(JSON.stringify(report))
		if not report_path.is_empty() and Paths.allowed(report_path): FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		quit(0 if report.ok and report.source_unchanged else 1); return
	var spawn: Array = index.extras.get("spawn", [0,.9,4]); var origin := Vector3(spawn[0],spawn[1],spawn[2])
	var selected := Index.select(index, [AABB(origin-Vector3(96,100000,96),Vector3(192,200000,192))])
	var hydration_started := Time.get_ticks_usec()
	var restored: Dictionary = Cursor.hydrate_references(selected.extras,path,Paths.external_root())
	if not restored.ok: print(restored); quit(1); return
	var hydrated_us := Time.get_ticks_usec() - hydration_started
	var validation_started := Time.get_ticks_usec(); var validated := Index.validate_selected(index, restored.extras.rmmo_records)
	var report := {"ok":validated.ok,"source_sha256":index.source_sha256,"source_unchanged":FileAccess.get_sha256(path)==index.source_sha256,"index_read_ms":read_us/1000.0,"selected_records":selected.selected_count,"selected_groups":selected.selected_groups.size(),"deferred_records":selected.deferred_count,"selected_unique_definitions":selected.dependencies.size(),"selected_hydration_ms":hydrated_us/1000.0,"selected_ownership_ms":(Time.get_ticks_usec()-validation_started)/1000.0,"complete_author_groups":index.extras.get("building_instances",{}).size(),"closure_complete":false}
	print(JSON.stringify(report))
	if not report_path.is_empty() and Paths.allowed(report_path): FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit(0 if report.ok and report.source_unchanged else 1)
