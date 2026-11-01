extends "res://tools/test_entry_residency_startup.gd"
const FinalInitial=preload("res://scripts/world3d/final_index_preparation.gd")
const Initial=preload("res://scripts/world3d/initial_residency_preparation.gd")
var legacy_initial:=false
var initial_results:Array=[]

class InitialJob extends RefCounted:
	var library:Array
	var directory:Dictionary
	var records:Array
	var result:Dictionary={}
	var main_thread:int
	var worker_thread:int
	func run()->void:
		worker_thread=OS.get_thread_caller_id()
		result=FinalInitial.prepare(library,{},"","",1,true,directory,records)

func append_record(directory:Dictionary,record:Dictionary,reason:String="asset",known:bool=true,group:String="")->void:
	var at:int=directory.extras.rmmo_records.size()
	directory.extras.rmmo_records.append(record)
	directory.rows.append({"uuid":record.uuid,"order":at,"bounds_known":known,"group_id":group,"asset_path":str(record.get("asset_path","")),"bounds":AABB(Vector3.ZERO,Vector3.ONE),"classification":"spatial" if known else "global","reason":reason,"memory_bytes":0})
	if not group.is_empty():directory.groups[group]={"bounds":AABB(Vector3.ZERO,Vector3.ONE)}

func initial_fixture(host:Node,large:bool=true)->Dictionary:
	var fixture_map:=make_map(host)
	var mesh:=CountedMesh.new()
	var source:Array=values(mesh)
	if not large:source.resize(2)
	# The other declared namespace shares both this model and the render group.
	var annex:Dictionary=source[0].duplicate(true);annex.uuid="annex__part0"
	annex.extras.erase("fixture");source.append(annex)
	var directory:Dictionary=fixture_map.queue._reference_index
	var additions:Array=[
		{"uuid":"ordinary","kind":"asset","asset_path":MODEL},
		{"uuid":"unsafe","kind":"asset","asset_path":MODEL},
		{"uuid":"pinned","kind":"asset","asset_path":MODEL,"event":{"id":"guard"}},
		{"uuid":"procedural","kind":"asset","bridge_mesh":{}},
		{"uuid":"unknown","kind":"asset"},
		{"uuid":"hydrated","kind":"asset"},
		{"uuid":"initial_ground","kind":"box","surface_id":"ground","size":[128,1,128]},
		{"uuid":"native_box","kind":"box","size":[1,1,1]},
		{"uuid":"pair_a","kind":"box","building":{"id":"building:pair"}},
		{"uuid":"pair_b","kind":"box","building":{"id":"building:pair"}},
	]
	for record:Dictionary in additions:
		var id:String=record.uuid
		var reason:="native_bridge" if id=="procedural" else ("unknown_geometry" if id in ["unknown","hydrated"] else ("native_box" if record.kind=="box" else "asset"))
		append_record(directory,record,reason,id not in ["unknown","hydrated"],"building:pair" if id.begins_with("pair_") else "")
		var extra:Dictionary={"building":{"id":"unsafe"}} if id=="unsafe" else {}
		if id.begins_with("pair_"):extra.building={"id":"building:pair"}
		var spec:=row(id+"__part0",mesh,extra)
		spec.chunk_min=Vector2i.ZERO;spec.chunk_max=Vector2i.ONE;spec.ground_batch_record=record
		if id=="unsafe":spec.native_visual=true
		if id=="initial_ground":
			spec.uuid=id;spec.chunk_min=Vector2i(-1,-1);spec.chunk_max=Vector2i(2,2)
		source.append(spec)
	# Imported model-local author IDs cannot steal a declared map namespace.
	source[0].ground_batch_record={"uuid":"local_part","kind":"asset","asset_path":"wrong_model.scn"}
	var records:Array=directory.extras.rmmo_records.duplicate(true)
	for record:Dictionary in records:
		if record.uuid=="hydrated":record.asset_path=MODEL
	append_record(directory,{"uuid":"directory_only","kind":"asset","asset_path":MODEL})
	fixture_map.map.set_meta("stream_library",source)
	fixture_map.map.set_meta("extras",{"rmmo_records":records})
	return {"map":fixture_map.map,"queue":fixture_map.queue,"source":source,"mesh":mesh,"directory":directory,"records":records}

func prepare_initial(f:Dictionary,enabled:bool=true)->Dictionary:
	var job:=InitialJob.new();job.library=f.source;job.directory=f.directory;job.records=f.records
	job.main_thread=OS.get_thread_caller_id()
	var previous:bool=Initial.enabled;Initial.enabled=enabled
	var task:int=WorkerThreadPool.add_task(job.run,false,"InitialResidencyComponent")
	WorkerThreadPool.wait_for_task_completion(task);Initial.enabled=previous
	check(job.worker_thread!=job.main_thread,"initial preparation executes through a real WorkerThreadPool task")
	check(job.result.dependencies_valid,"trusted private final-index worker succeeds")
	for key:String in job.result.index:f.map.set_meta(key,job.result.index[key])
	f.map.set_meta("stream_library",f.source)
	var prepared:RefCounted=job.result.get("initial_residency")
	if prepared!=null:f.map.set_meta("initial_residency_preparation",prepared)
	return {"result":job.result,"prepared":prepared,"mesh_reads":f.mesh.reads}

func full_initial_state(f:Dictionary)->Dictionary:
	var result:=state(f)
	var ordinary:Node=f.map.get_node("AssetResidency");var native:Node=f.map.get_node("NativeResidency")
	for key:String in ["_catalog","_record_pins","_record_paths","_unknown_asset_specs","_procedural_assets"]:result["ordinary"+key]=ordinary.get(key).duplicate(true)
	for key:String in ["_model_entries","_group_units"]:result["native"+key]=native.get(key).duplicate(true)
	return result

func ledger(f:Dictionary)->Dictionary:
	var result:Dictionary={}
	for name_:String in ["AssetResidency","NativeResidency"]:
		var node:Node=f.map.get_node(name_)
		result[name_]={}
		for key:String in ["initial_prepared_adoptions","initial_directory_rows","initial_record_rows","initial_spec_rows"]:
			result[name_][key]=int(node.profile.get(key,0))
	return result

func test_actual_initial_handoff()->void:
	var host:=Host.new();root.add_child(host)
	var candidate:=initial_fixture(host);var control:=initial_fixture(host)
	var prepared:=prepare_initial(candidate);prepare_initial(control,false)
	var worker:RefCounted=prepared.prepared
	check(worker!=null,"final-index job produces a separate one-shot initial residency result")
	var worker_profile:Dictionary=worker.profile.duplicate(true) if worker!=null else {}
	if legacy_initial:candidate.map.remove_meta("initial_residency_preparation")
	check(Stream.set_entry_scope(candidate.map,AABB(Vector3(-64,-1000,-64),Vector3(128,2000,128))),"real entry scope changes before ownership adoption")
	var before_reads:int=candidate.mesh.reads
	var began:=Time.get_ticks_usec();check(Startup.ensure(host,candidate.map),"candidate initial map subscribes")
	var main_us:=Time.get_ticks_usec()-began
	check(Startup.ensure(host,control.map),"legacy reference initial map subscribes")
	check(full_initial_state(candidate)==full_initial_state(control),"worker handoff matches every legacy directory, ID/order, shared model, pin, group, support and runtime building table")
	var work:=ledger(candidate)
	var adopted:bool=work.AssetResidency.initial_prepared_adoptions==1 and work.NativeResidency.initial_prepared_adoptions==1
	check(adopted,"both services actually adopt prepared initial containers, not only earlier configure")
	check(work.AssetResidency.initial_directory_rows+work.NativeResidency.initial_directory_rows+work.AssetResidency.initial_record_rows+work.NativeResidency.initial_record_rows+work.AssetResidency.initial_spec_rows+work.NativeResidency.initial_spec_rows==0,"initial MAIN performs zero directory, authored-record and component visits")
	check(int(worker_profile.get("directory_rows",-1))==candidate.directory.rows.size() and int(worker_profile.get("record_rows",-1))==candidate.records.size() and int(worker_profile.get("index_spec_rows",-1))==candidate.source.size(),"worker ledger is one directory pass, one record pass, and one fused index visit per initial spec")
	check(candidate.mesh.reads==before_reads and candidate.mesh.reads==control.mesh.reads,"ownership adoption adds no Mesh getter or second collision-neighborhood build")
	check(not candidate.map.has_meta("initial_residency_preparation") and candidate.queue.published.get_connections().size()==2,"one-shot map ownership is removed and each live consumer connects once")
	check(int(candidate.map.get_meta("stream_children"))==candidate.map.get_child_count(true),"prepared adoption keeps completed child bookkeeping current")
	if not legacy_initial:check(not worker.claim(candidate.map,candidate.queue),"a consumed initial preparation cannot be claimed twice")
	var saved:=full_initial_state(candidate);var old_work:=ledger(candidate)
	check(Startup.ensure(host,candidate.map) and full_initial_state(candidate)==saved and ledger(candidate)==old_work,"repeated ensure neither consumes twice nor rescans/replaces service state")
	var ordinary:Node=candidate.map.get_node("AssetResidency");var native:Node=candidate.map.get_node("NativeResidency")
	check(ordinary._record_paths.guild==MODEL and ordinary._spec_namespaces["guild__part0"]=="guild","declared map model identity wins over embedded model-local record identity")
	check(not native._owners.has("unsafe") and ordinary._resident.unsafe.pinned=="native visual","native visual namespace remains conservatively ordinary and pinned")
	check(ordinary._record_pins.pinned=="event" and ordinary._procedural_assets.has("procedural") and ordinary._unknown_asset_specs.has("unknown__part0"),"prepared traits retain event pins, procedural exclusions and unknown-model fallback")
	check(ordinary._record_paths.hydrated==MODEL and ordinary._spec_namespaces["hydrated__part0"]=="hydrated" and ordinary._catalog.has("directory_only") and not ordinary._resident.has("directory_only"),"selected hydrated traits override compact paths while unloaded directory entries remain nonresident")
	check(native._group_units.guild.size()==2 and native._units["asset:guild"].support_ids.has("initial_ground") and native._units["asset:annex"].support_ids.has("initial_ground"),"initial shared render group gives both imported owners the same support")
	var native_ids:int=native._resident["asset:guild"].ids.size()
	ordinary.forget_specs(["guild__part0"])
	check(native._resident["asset:guild"].ids.size()==native_ids and native._resident["asset:guild"].known_ids.has("guild__part0"),"ordinary mutable membership does not alias native ID ownership")
	initial_results.append({"case":"initial_handoff","specs":candidate.source.size(),"rows":candidate.directory.rows.size(),"worker":worker_profile,"main":work,"main_us":main_us,"mesh_reads":candidate.mesh.reads,"legacy_control":legacy_initial})
	# Retain the consumed preparation alone after every geometry owner is gone.
	var mesh_ref:WeakRef=weakref(candidate.mesh)
	prepared.result.clear();candidate.source=[];candidate.mesh=null
	control.source=[];control.mesh=null;host.free();candidate.clear();control.clear();saved.clear()
	check(mesh_ref.get_ref()==null,"consumed one-shot preparation retains no Mesh/library after map disposal")

func reference_for(host:Node,f:Dictionary)->Dictionary:
	var reference:=make_map(host)
	reference.queue._reference_index=f.queue._reference_index
	reference.map.set_meta("extras",f.map.get_meta("extras"))
	for key:StringName in f.map.get_meta_list():
		if str(key).begins_with("stream_"):reference.map.set_meta(key,f.map.get_meta(key))
	return reference

func test_stale_initial_state()->void:
	for mutation:String in ["append","retire","rebuild","directory","activated"]:
		var host:=Host.new();root.add_child(host)
		var f:=initial_fixture(host,false);var prepared:=prepare_initial(f)
		match mutation:
			"append":
				var spec:=row("late_prop__part0",f.mesh);spec.chunk_min=Vector2i.ZERO;spec.chunk_max=Vector2i.ONE
				spec.ground_batch_record={"uuid":"late_prop","kind":"asset","asset_path":MODEL}
				check(Stream.append_specs(f.map,[spec]).ok,"real append mutates membership before startup adoption")
			"retire":
				f.map.set_meta("stream_append_pending",[]);f.map.set_meta("stream_chunk",Vector2i(100,100))
				check(Stream.retire_specs(f.map,["ordinary__part0"]).ok,"real ordinary retirement mutates membership before startup adoption")
			"rebuild":
				# A legitimate same-size replacement rebuilds the index and its
				# operation token. Arbitrary mutation of the private library without
				# an Index transaction is outside the production ownership contract.
				var replacement:Array=f.source.duplicate()
				var spec:Dictionary=replacement[0].duplicate(true);spec.uuid="guild__replacement"
				replacement[0]=spec;f.source=replacement;f.map.set_meta("stream_library",replacement)
				var rebuilt:Dictionary=Index.build(replacement,true)
				for key:String in rebuilt:f.map.set_meta(key,rebuilt[key])
			"directory":f.queue._reference_index=f.directory.duplicate(true)
			"activated":f.queue._active=true
		var reference:=reference_for(host,f)
		check(Startup.ensure(host,f.map) and Startup.ensure(host,reference.map),mutation+" stale result safely falls back")
		check(full_initial_state(f)==full_initial_state(reference),mutation+" fallback matches current authoritative membership and directory")
		var work:=ledger(f)
		check(work.AssetResidency.initial_prepared_adoptions==0 and work.NativeResidency.initial_prepared_adoptions==0 and work.AssetResidency.initial_spec_rows>0 and work.NativeResidency.initial_spec_rows>0,mutation+" rejects stale one-shot result instead of accepting equal counts")
		check(not f.map.has_meta("initial_residency_preparation"),mutation+" discards rejected one-shot metadata")
		initial_results.append({"case":"stale_"+mutation,"main":work})
		prepared.result.clear();host.free()

func test_initial_cancellation_and_signal_lifetime()->void:
	var host:=Host.new();root.add_child(host)
	var cancelled:=initial_fixture(host,false);var result:=prepare_initial(cancelled)
	var prepared:RefCounted=result.prepared;var geometry:WeakRef=weakref(cancelled.mesh)
	result.result.clear();cancelled.source=[];cancelled.mesh=null
	cancelled.map.free();cancelled.clear()
	check(geometry.get_ref()==null,"cancelled unpublished map releases geometry even while prepared scalar state remains referenced")
	var live:=initial_fixture(host,false);prepare_initial(live)
	live.map.set_meta("stream_children",-1)
	check(Startup.ensure(host,live.map),"replacement map consumes its own initial preparation")
	check(int(live.map.get_meta("stream_children"))==-1,"prepared adoption preserves incomplete child bookkeeping")
	var queue:Node=live.queue;live.map.remove_child(queue);live.map.free()
	check(queue.published.get_connections().is_empty(),"consumed initial map leaves no callback on an independently surviving queue")
	queue.published.emit([]);queue.free();host.free()
	check(prepared!=null,"cancellation fixture deliberately retains the detached preparation during the lifetime assertions")

func run()->void:
	legacy_initial="--legacy-initial" in OS.get_cmdline_user_args()
	test_actual_initial_handoff()
	test_stale_initial_state();test_initial_cancellation_and_signal_lifetime()
	# Keep the qualified live-publication and retirement contracts exercised.
	test_startup_and_publication();test_adoption_and_no_index()
	test_building_before_ground();test_shared_group_and_reappend()
	var report:={"failures":failures,"legacy_initial":legacy_initial,"initial_cases":initial_results,"live_cases":results,"scope":"Real final-index worker to one-shot startup ownership, work ledger and lifecycle; no map timing claim"}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("INITIAL_RESIDENCY_PREPARATION ",JSON.stringify(report));quit(1 if failures else 0)
