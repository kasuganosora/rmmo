extends SceneTree
const Proof=preload("res://scripts/world3d/dependency_index_proof.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Budget=preload("res://scripts/world3d/frame_work_budget.gd")
var output:=""
var failures:Array=[]
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func make_snapshot()->Dictionary:
	var rows:Array=[]
	for i in 1024:
		var heights:Array=[]
		for j in 512:heights.append(float(i+j))
		rows.append({"uuid":"row_%d"%i,"terrain":{"heights":heights}})
	return {"source_sha256":"test","generator":"test","extras":{"rmmo_records":rows},"rows":rows,"groups":{},"models":{}}
func authored_snapshot(service:Node)->void:
	var map:=Node3D.new();root.add_child(map)
	var value:Dictionary=make_snapshot().extras
	map.set_meta("author_reference_extras",value);value={}
	var borrowed:Dictionary=map.get_meta("author_reference_extras").rmmo_records[0]
	preload("res://scripts/world3d/world_stream.gd").prepare_map_disposal(map,self)
	check(not service.pending.is_empty(),"permanent map disposal retains its raw JSON on the CPU retirement lane")
	var queued:int=service.pending.size()
	preload("res://scripts/world3d/world_stream.gd").prepare_map_disposal(map,self)
	check(service.pending.size()==queued,"repeat permanent disposal does not enqueue duplicate JSON work")
	map.free()
	var deadline:=Time.get_ticks_msec()+10000
	while not service.pending.is_empty() and Time.get_ticks_msec()<deadline:
		service._process(0.);await process_frame
	check(service.pending.is_empty() and borrowed.terrain.heights.size()==512,"map JSON disposal preserves every surviving borrower")
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	Budget.enabled=false
	var service:Node=Retirement._service();service.set_process(false)
	var snapshot:=make_snapshot();var issuer:=RefCounted.new()
	var proof:RefCounted=Proof.issue(snapshot,"map","root",issuer,true)
	check(proof!=null and proof.matches(snapshot,"root",issuer,"map"),"issued snapshot retains its exact immutable identity")
	var borrowed:Dictionary=snapshot.rows[0];snapshot={}
	var observed:WeakRef=weakref(proof);var started:=Time.get_ticks_usec();proof=null
	var release_us:=Time.get_ticks_usec()-started
	check(observed.get_ref()==null,"proof object itself releases immediately")
	check(not service.pending.is_empty(),"pure nested snapshot has an explicit CPU retirement owner")
	check(borrowed.is_read_only() and borrowed.terrain.heights.size()==512,"shared immutable row remains intact")
	var deadline:=Time.get_ticks_msec()+10000
	while not service.pending.is_empty() and Time.get_ticks_msec()<deadline:
		service._process(0.);await process_frame
	check(service.pending.is_empty(),"CPU snapshot retirement completes")
	check(int(service.profile.get("geometry_last_thread_id",OS.get_main_thread_id()))!=OS.get_main_thread_id(),"nested JSON containers release on the existing CPU worker")
	check(borrowed.terrain.heights[511]==511.,"worker only drops ownership and never clears shared children")
	await authored_snapshot(service)
	var report:={"checks":checks,"failures":failures,"release_us":release_us,"retirement":service.profile}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
