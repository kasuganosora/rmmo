extends "res://tools/test_world3d_ground_batching.gd"
const TOWN="D:/code/rmmo_runtime/cache/world3d/medieval_town_walls/map.gltf"
func run() -> void:
	create_timer(900).timeout.connect(func():quit(2)); Engine.max_fps=60
	directory=Paths.cache_directory("transform_hotspot_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory)
	var hash_before:=FileAccess.get_sha256(TOWN)
	var doc=Doc.open_file(TOWN); check(doc!=null,"town document opens for temporary in-memory benchmark")
	if doc==null: quit(1); return
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=TOWN; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); editor._safety.enabled=false; await flush()
	var record: Dictionary=doc.records.filter(func(r):return r.has("fortification") and r.has("surface_paint") and not r.has("fixture"))[0]
	editor._selection_tools.component_edit=true
	editor._selection_tools.set_ids([str(record.uuid)])
	await flush()
	var original: Array=record.position.duplicate(); var samples: Array=[]; var inspector_samples: Array=[]; var total_samples: Array=[]
	var mesh_id: int=editor._view.get_node(str(record.uuid)).mesh.get_instance_id()
	var start_rebuilds: int=editor._ground_batches.rebuild_count
	var start_syncs: int=editor._ground_batches.sync_count
	editor._transform_drag.active=true
	for i in 12:
		record.position=[float(original[0])+.1*(i+1),original[1],original[2]]
		var start:=Time.get_ticks_usec(); editor._sync_selected_transform(); samples.append((Time.get_ticks_usec()-start)/1000.)
		var inspector_start:=Time.get_ticks_usec(); editor._inspector.refresh(false); inspector_samples.append((Time.get_ticks_usec()-inspector_start)/1000.)
		total_samples.append((Time.get_ticks_usec()-start)/1000.)
		await process_frame
	var drag_syncs: int=editor._ground_batches.sync_count-start_syncs
	editor._transform_drag.active=false; record.position=original; editor._sync_selected_transform(); await flush()
	samples.sort()
	inspector_samples.sort(); total_samples.sort()
	var report:={"median_ms":samples[samples.size()/2],"max_ms":samples[-1],"samples_ms":samples,"mesh_reused":mesh_id==editor._view.get_node(str(record.uuid)).mesh.get_instance_id(),"render_rebuilds":editor._ground_batches.rebuild_count-start_rebuilds,"records":doc.records.size(),"failures":failed}
	check(FileAccess.get_sha256(TOWN)==hash_before,"benchmark never writes town file")
	report["inspector_median_ms"]=inspector_samples[inspector_samples.size()/2]
	report["combined_median_ms"]=total_samples[total_samples.size()/2]
	report["combined_max_ms"]=total_samples[-1]
	report["drag_global_syncs"]=drag_syncs
	report.failures=failed
	var output: String=OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else directory.path_join("performance.json")
	var file:=FileAccess.open(output,FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("TRANSFORM_HOTSPOT_RESULT ",JSON.stringify(report)); editor.queue_free(); await settle(); quit(1 if failed else 0)
