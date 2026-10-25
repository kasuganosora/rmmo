extends SceneTree
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Cover=preload("res://scripts/world3d/initial_loading_cover.gd")
const Probe=preload("res://tools/test_ground_batch_loading_budget.gd").SchedulerProbe
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var host:=Node3D.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map)
	var queue:=Deferred.new();queue._map=map;queue._host=host;map.add_child(queue)
	queue._candidates_revision=queue._demand_revision
	var batch:=Probe.new();map.add_child(batch);batch.set_process(false)
	map.set_meta("stream_chunk",Vector2i.ZERO);map.set_meta("stream_target",Vector2i.ZERO)
	var cover:=Cover.new();host.add_child(cover)
	await process_frame;await process_frame
	root.disable_3d=true
	check(queue.begin_loading_cover(host,cover),"real drawn cover grants initial loading authority")
	check(batch.effective_work_budget_usec()==6000,"idle textured load lends the existing six millisecond stream/batch allowance")
	batch._preparation={"phase":"collect"}
	batch.share_residency_budget(Time.get_ticks_usec()-6100);batch._process(0.)
	check(batch.seen_budget_usec==-1,"streaming overrun leaves no extra batch allowance")
	batch.residency_budget_frame=-1
	queue._demand_revision+=1
	check(batch.effective_work_budget_usec()==2000,"new demand immediately revokes the borrowed allowance")
	queue._candidates_revision=queue._demand_revision
	queue._jobs["pending"]={}
	check(batch.effective_work_budget_usec()==2000,"ready or running publication owners retain their lane")
	queue._jobs.clear()
	map.set_meta("stream_target",Vector2i.ONE)
	check(batch.effective_work_budget_usec()==2000,"changed destination revokes settled batch borrowing")
	map.set_meta("stream_target",Vector2i.ZERO)
	cover.hide()
	check(batch.effective_work_budget_usec()==2000,"hidden cover restores the interactive budget")
	cover.show();root.disable_3d=false
	check(batch.effective_work_budget_usec()==2000,"enabled 3D revokes cover-only borrowing")
	root.disable_3d=true
	queue.end_loading_cover()
	check(batch.effective_work_budget_usec()==2000,"normal completion or cancellation clears authority")
	queue.begin_loading_cover(host,cover)
	check(batch.effective_work_budget_usec()==6000,"fresh covered idle operation can borrow again")
	var ledger=preload("res://scripts/world3d/frame_work_budget.gd")
	ledger.enabled=true;batch.seen_budget_usec=-1
	batch._process(0.)
	check(batch.seen_budget_usec>2000 and batch.seen_budget_usec<=5000,"enabled whole-frame ledger keeps the covered batch lane cap")
	ledger.enabled=false
	Batch.covered_idle_budget_enabled=false
	check(batch.effective_work_budget_usec()==2000,"same-code diagnostic control retains the original texture budget")
	Batch.covered_idle_budget_enabled=true
	queue._cancelled=true
	check(batch.effective_work_budget_usec()==2000,"cancelled queue cannot lend a budget")
	queue._cancelled=false;queue.end_loading_cover();root.disable_3d=false
	host.free()
	print("COVERED_TEXTURE_BATCH_BUDGET checks=",checks," failures=",failures)
	quit(1 if failures else 0)
