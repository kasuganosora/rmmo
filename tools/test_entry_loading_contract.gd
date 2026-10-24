extends SceneTree
const Plan=preload("res://scripts/world3d/entry_plan.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
class Host extends Node3D:
	var _ready_for_play:=false
class Cover extends Deferred.TransferLoading:
	func _ready()->void:pass
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label_)
func run()->void:
	var origin:=Vector3(321.2,.9,160.3)
	var plan:=Plan.create(origin)
	check(plan.cell==Vector2i(10,5),"problem position maps to actual 32m cell")
	check(plan.core_clip.position.x==320 and plan.core_clip.position.z==160 and plan.core_clip.size.x==32,"core is a cell not a 32m radius")
	var negative:=Plan.create(Vector3(-.1,0,-32.1))
	check(negative.cell==Vector2i(-1,-2),"negative coordinates use floor cell selection")
	check(Plan.create(Vector3(INF,0,0)).is_empty(),"nonfinite origin cannot create entry work")
	for point in [origin+Vector3(12.215,0,0),origin-Vector3(12.215,0,0),origin+Vector3(0,0,12.215),origin-Vector3(0,0,12.215)]:
		check(plan.safety_clip.has_point(point),"maximum camera sweep has safety coverage")
	var host:=Host.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map);map.set_meta("entry_plan",plan)
	var queue:=Deferred.new();map.add_child(queue)
	var cover:=Cover.new();host.add_child(cover);cover.drawn_frame=0;cover.opacity=1;cover.phase="waiting"
	check(not queue.begin_entry_loading(host,plan.safety_clip,cover),"neighbours cannot begin before core milestone")
	plan.core_resources_ready_us=Time.get_ticks_usec();map.set_meta("entry_plan",plan)
	cover.drawn_frame=-1
	check(not queue.begin_entry_loading(host,plan.safety_clip,cover),"undrawn cover cannot authorize loading publication")
	cover.drawn_frame=0;cover.opacity=1;cover.phase="waiting"
	check(not queue.begin_entry_loading(host,plan.core_clip,cover),"caller cannot substitute a different safety contract")
	queue.set_demand("far",AABB(Vector3(1000,-1,1000),Vector3(20,2,20)))
	check(queue.begin_entry_loading(host,plan.safety_clip,cover),"verified core starts explicitly scoped neighbour preparation")
	queue.set_process(false)
	check(queue.get_demand_scope()==["entry_safety"],"far tickets are not admitted during safety preparation")
	check(map.get_meta("entry_plan").neighbours_started_us>=plan.core_resources_ready_us,"phase order is timestamped")
	root.disable_3d=true
	check(queue._entry_loading_allowed() and queue._main_thread_budget_usec()==queue.covered_loading_budget_usec,"drawn cover plus disabled viewport permits bounded publication")
	root.disable_3d=false
	check(queue._main_thread_budget_usec()==2000,"rendering first frame restores interactive submission budget")
	cover.visible=false
	check(not queue._entry_loading_allowed(),"hidden cover revokes entry authority")
	cover.visible=true
	queue.end_entry_loading();queue.set_process(false)
	check(queue.get_demand_scope().is_empty() and queue._demands.has("far") and not queue._demands.has("entry_safety"),"completion restores ordinary tickets without losing neighbours")
	check(not queue._entry_loading_allowed(),"completed entry cannot keep a loading publication permit")
	check(not queue.begin_scene_handoff(),"active queue cannot bypass cancellation during reparent")
	await queue.quiesce()
	check(queue.begin_scene_handoff(),"quiesced queue permits synchronous scene handoff")
	var next_host:=Host.new();root.add_child(next_host)
	map.reparent(next_host);queue.end_scene_handoff(next_host)
	check(not queue._cancelled and not queue._active and queue._host==next_host,"handoff preserves queue without starting publication before the first frame")
	queue.activate(next_host)
	check(queue._active and not queue._cancelled,"committed map can resume neighbouring work")
	map.remove_child(queue)
	check(queue._cancelled,"ordinary tree removal still cancels its workers")
	queue.free();next_host.free()
	host.free()
	print("ENTRY_LOADING_CONTRACT ",checks," checks / ",failures," failures")
	quit(1 if failures else 0)
