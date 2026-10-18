extends SceneTree
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var files:=preload("res://tools/test_map_dependency_index.gd").new()
	files.content_root=Paths.external_root();files.folder=Paths.cache_directory("directory_workers_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	var roads:=preload("res://tools/test_road_dependency_index.gd").new()
	var records:Array=[]
	for i:int in 32:records.append(roads.road("road%d"%i,i*32))
	roads.free()
	var model_fixture:=preload("res://tools/test_asset_bounds_manifest.gd").new()
	var data:Dictionary=model_fixture.data();model_fixture.free()
	data.nodes[0].extras={"rmmo_model_components":{"version":1},"rmmo_building":{"version":1,"regions":[{"id":"hall","floor":0,"min":[-1,0,-1],"max":[1,3,1]}]}}
	data.nodes[1].extras={"rmmo_source_uuid":"floor","rmmo_part":{"floor":0,"floor_y":0,"role":"floor","part":"slab"}}
	var payload:=PackedByteArray();payload.resize(4*1024*1024+36);payload.fill(7);data.buffers[0].byteLength=payload.size()
	var writer:=preload("res://tools/test_imported_source_snapshot.gd").new()
	var source_paths:Array=[];var extra:={"rmmo_records":[]};var source_rows:Array=[]
	for i:int in 4:
		var path:String=files.folder.path_join("source%d.glb"%i);source_paths.append(path);files.created.append(path)
		writer.write(path,data,payload)
		var descriptor:Dictionary=Index.Imported.read_source_descriptor(path)
		check(not descriptor.is_empty(),"source fixture %d valid"%i)
		extra.rmmo_records.append({"rmmo_state":{"model_building":descriptor}});source_rows.append({"order":i,"asset_path":path})
	for i:int in 8:
		records.insert(i*3,{"uuid":"model%d"%i,"kind":"asset","asset_path":source_paths[i%4],"position":[i*32,0,0],"rotation":[0,0,0],"size":[1,1,1]})
	var source:Dictionary=files.fixture("mixed",records)
	Index.parallel_native_classification=false;Index.parallel_imported_sources=false
	var serial:=Index.build_for_loading(source.path,files.content_root,records)
	var bytes:=FileAccess.get_file_as_bytes(Index.cache_path(source.path,files.content_root))
	Index.parallel_native_classification=true;Index.parallel_imported_sources=true
	var parallel:=Index.build_for_loading(source.path,files.content_root,records)
	check(serial.ok and parallel.ok and serial.index==parallel.index,"mixed model/native rows retain every bound, source, estimate, order and group")
	check(bytes==FileAccess.get_file_as_bytes(Index.cache_path(source.path,files.content_root)),"serial and parallel persisted envelopes are byte-identical")
	var obsolete:Dictionary=bytes_to_var(bytes.slice(49));obsolete.generator="0".repeat(64)
	var cache:String=Index.cache_path(source.path,files.content_root);files.replace_payload(cache,obsolete)
	Index.Trace.minimum_event_us=0;Index.Trace.start()
	var stale:=Index.read(source.path,files.content_root);var events:Dictionary=Index.Trace.stop()
	check(not stale.ok and stale.reason=="stale_index" and events.events.filter(func(e):return e.label in ["index.schema","index.ownership","index.imported_batch"]).is_empty(),"obsolete generator stops before row/schema/ownership/source work")
	files.write_bytes(cache,bytes)
	var lengths:Dictionary={}
	for i:int in records.size():lengths[source.extras.rmmo_records[i].rmmo_ref.sha256]=var_to_bytes(Index.Store._definition(records[i])).size()
	Index.Trace.start()
	var reused:=Index.build_for_loading(source.path,files.content_root,records,"",4,Index.Snapshot.RETAIN_LIMIT,true,lengths,parallel.index.models)
	var reused_trace:=Index.Trace.stop()
	check(reused.ok and reused.index==parallel.index,"load-local model manifests preserve exact directory output")
	check(reused_trace.events.filter(func(e):return e.label=="model.bounds_manifest").is_empty(),"directory construction reuses model bounds without opening shared GLB headers again")
	var fallback:=Index._build_rows(records,source.extras.rmmo_records,lengths,files.content_root,4,func(_worker,_task):return ERR_CANT_CREATE)
	check(fallback.ok and fallback.profile.fallback_count==4 and fallback.profile.threads_started==0 and fallback.rows==parallel.index.rows,"failed native worker launches use caller fallback without missing/reordered rows")
	var single:=Index._build_rows(records,source.extras.rmmo_records,lengths,files.content_root,1)
	check(single.ok and single.profile.peak_active==1 and single.profile.threads_started==0 and single.rows==fallback.rows,"worker_limit=1 remains serial for background preparation")
	check(Index._imported_sources_valid(extra,source_rows),"parallel complete source SHA and annotations accepted")
	check(Index._imported_sources_valid(extra,source_rows,1),"single-worker complete source checks accepted")
	check(Index._imported_sources_valid(extra,source_rows,4,func(_worker,_task):return ERR_CANT_CREATE),"failed source worker launches retain all validation on caller")
	var same:Dictionary=extra.duplicate(true);var rows:Array=source_rows.duplicate(true)
	same.rmmo_records.append(extra.rmmo_records[0].duplicate(true));rows.append({"order":4,"asset_path":source_paths[0]})
	check(Index._imported_sources_valid(same,rows),"repeated source path validates each independent authored instance")
	same.rmmo_records[4].rmmo_state.model_building.members.floor.role="roof"
	check(not Index._imported_sources_valid(same,rows),"conflicting annotation on later repeated path cannot borrow first instance success")
	same=extra.duplicate(true);same.rmmo_records[-1].rmmo_state.model_building.source_sha="0".repeat(64)
	check(not Index._imported_sources_valid(same,source_rows),"one wrong digest rejects complete parallel batch")
	var launched:=[0]
	var starter:=func(worker:Thread,task:Callable)->int:
		if launched[0]==0:
			var changed:PackedByteArray=payload.duplicate();changed[-1]=8
			writer.write(source_paths[0],data,changed)
		launched[0]+=1
		return worker.start(task)
	check(not Index._imported_sources_valid(extra,source_rows,4,starter),"same-length source replacement at dispatch is detected after a warmed source cache")
	writer.write(source_paths[0],data,payload)
	check(Index._imported_sources_valid(extra,source_rows),"restoring exact bytes remains valid after failed batch")
	DirAccess.remove_absolute(source_paths[-1])
	check(not Index._imported_sources_valid(extra,source_rows),"removed source cannot be supplied by previous worker/cache result")
	writer.free()
	for path:String in files.created:
		if Paths.allowed(path,files.content_root) and FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(source.path+".resources");DirAccess.remove_absolute(files.folder);files.free()
	print("DIRECTORY_WORKERS checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
