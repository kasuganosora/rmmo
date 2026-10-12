extends SceneTree
## Tiny positive main-thread slices must make real progress; zero must not.
## Pure CPU fixtures: no renderer upload, imported asset or Recast bake.
const Budget=preload("res://scripts/world3d/frame_work_budget.gd")
const Batcher=preload("res://scripts/world3d/ground_batcher.gd")
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
const Nearby=preload("res://scripts/world3d/nearby_navigation.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Candidates=preload("res://scripts/world3d/stream_candidate_plan.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failures+=1
func lane_remaining(lane:String,remaining:int)->void:
	Budget._shared=null
	Budget.shared().record(Engine.get_process_frames(),lane,int(Budget.INTERACTIVE[lane])-remaining)
func spec(id:String,collides:bool=false)->Dictionary:
	var mesh:=Cpu.new();mesh.bounds=AABB(Vector3(-1,-1,-1),Vector3(2,2,2))
	return {"uuid":id,"mesh":mesh,"transform":Transform3D.IDENTITY,"chunk":Vector2i.ZERO,"low":Vector2i.ZERO,"high":Vector2i.ZERO,"native_visual":true,"extras":{"rmmo_collision":"walk" if collides else "none"}}
func make_nav()->Node:
	var nav:=Navigation.new();root.add_child(nav);nav.set_process(false);nav.set_physics_process(false)
	return nav
func make_map()->Node3D:
	var node:=Node3D.new();root.add_child(node)
	node.set_meta("stream_library",[spec("one"),spec("two")])
	node.set_meta("stream_building_count",2);node.set_meta("stream_applied_source_revision",0)
	node.set_meta("stream_target",Vector2i.ZERO);node.set_meta("stream_children",0)
	node.set_meta("stream_jobs",[spec("one"),spec("two")]);node.set_meta("stream_cursor",0)
	return node
func run()->void:
	var old_enabled:bool=Budget.enabled;Budget.enabled=true
	var batch:=Batcher.new();root.add_child(batch);batch.set_process(false)
	batch.pending.assign(["gone_a","gone_b"]);batch._audit_keys.assign(["gone_a","gone_b"])
	lane_remaining("batch",0);batch._process(0)
	check(batch.pending.size()==2 and batch._audit_cursor==0,"zero batch allowance does not consume jobs or audit")
	lane_remaining("batch",1);batch._process(0)
	check(batch.pending.size()==1,"one microsecond batch slice consumes a pending group before audit")
	check(int(Budget.report().current_lanes.batch)>999,"indivisible batch work is charged beyond the remaining allowance")
	lane_remaining("batch",1);batch._process(0)
	check(batch.pending.is_empty(),"repeated tiny batch slices finish their finite queue")
	batch._preparation={"phase":"collect","cursor":0,"items":[null,null],"named":{},"desired":{},"excluded":{},"cpu_us":0}
	batch._process_work(1)
	check(not batch._preparation.is_empty() and int(batch._preparation.cursor)>0,"tiny batch preparation advances its real cursor")
	batch._preparation.clear()
	var done:=Thread.new();done.start(func():return {})
	while done.is_alive():await process_frame
	batch._workers.append({"key":"gone","generation":0,"started":0,"thread":done})
	batch._process_work(1)
	check(batch._workers.is_empty() and not done.is_started(),"tiny batch slice joins a finished worker and releases its slot")
	var gate:=Semaphore.new();var live:=Thread.new();live.start(func():gate.wait();return {})
	batch._workers.append({"key":"gone","generation":0,"started":0,"thread":live})
	batch.work_budget_usec=24000;batch._process_work(1)
	check(batch._workers.size()==1 and live.is_alive(),"budgeted batch leaves a live worker unjoined")
	gate.post()
	while live.is_alive():await process_frame
	batch._process_work(1);batch.free()
	var nav:=make_nav();nav._phase="bounds";nav._specs=[spec("one",true),spec("two",true),spec("three",true)]
	lane_remaining("navigation",0);nav._process(0)
	check(nav._cursor==0,"zero navigation allowance leaves source cursor untouched")
	lane_remaining("navigation",1);nav._process(0)
	check(nav._cursor==1 and nav._has_bounds,"one microsecond navigation slice advances real bounds work")
	check(int(Budget.report().current_lanes.navigation)>499,"navigation overrun remains charged without expanding its deadline")
	nav._budget_slice_active=true;nav._work_deadline_usec=Time.get_ticks_usec()-1
	var old_deadline:int=nav._work_deadline_usec;nav._step_background()
	check(nav._cursor==2 and nav._work_deadline_usec==old_deadline,"expired production deadline advances one unit without resetting to 12 ms")
	nav._phase="tile_vertices";nav._cursor=0;nav._merge_vertices=PackedVector3Array([Vector3.ONE,Vector3.ONE*2,Vector3.ONE*3])
	nav._work_deadline_usec=Time.get_ticks_usec()-1;nav._step_merge()
	check(nav._cursor==1,"expired positive navigation slice advances tile vertex cursor")
	nav._specs=[spec("a"),spec("b"),spec("c")]
	var nearby:=Nearby.new(NavigationMesh.new(),AABB(Vector3(-2,-2,-2),Vector3(4,4,4)))
	nearby.step(nav,0);check(nearby.cursor==0,"zero nearby navigation slice does not begin source work")
	nearby.step(nav,1);check(nearby.cursor>0 and not nearby.baking,"tiny nearby navigation slice advances its source cursor")
	nav.free()
	var map_node:=make_map()
	lane_remaining("collision",0);Stream.sync(map_node,map_node,Vector3.ZERO,1)
	check(map_node.get_meta("stream_cursor")==0,"zero collision allowance leaves residency jobs untouched")
	lane_remaining("collision",1);Stream.sync(map_node,map_node,Vector3.ZERO,1)
	check(map_node.get_meta("stream_cursor")==1,"tiny collision allowance advances actual residency apply cursor")
	check(int(Budget.report().current_lanes.collision)>1999,"collision metadata and apply overrun are included in ledger")
	# Existing child batch/collision nodes are intentionally retained by sync.
	lane_remaining("collision",1);Stream.sync(map_node,map_node,Vector3.ZERO,1)
	check(map_node.get_meta("stream_jobs").is_empty() and map_node.has_meta("stream_chunk"),"finite residency queue completes with repeated tiny slices")
	map_node.free();map_node=make_map()
	map_node.set_meta("stream_candidates",[spec("p1"),spec("p2"),spec("p3")]);map_node.set_meta("stream_plan_cursor",0)
	map_node.set_meta("stream_plan_bins",[[],[],[],[],[]]);map_node.set_meta("stream_jobs",[])
	lane_remaining("collision",1);Stream.sync(map_node,map_node,Vector3.ZERO,1)
	check(int(map_node.get_meta("stream_plan_cursor",0))>0,"tiny residency slice reaches planning after fixed metadata checks")
	var plan:=Candidates.new(map_node,Vector2i.ZERO,Vector2i.ONE,[spec("planned")],Stream)
	plan.advance(0);check(plan.cursor==0 and plan.selected.is_empty(),"zero candidate allowance does not progress")
	plan.advance(1);check(plan.cursor>0 or plan.stage>0 or plan.bin_cursor>0,"tiny candidate slice advances a real cursor")
	var finished:=false
	for i in 100:
		if plan.advance(1):finished=true;break
	check(finished and plan.selected.has("planned"),"finite candidate plan completes under one microsecond slices")
	map_node.free();Budget.enabled=old_enabled;Budget._shared=null
	print("LOADING_BUDGET_PROGRESS passed=",passed," failures=",failures)
	quit(1 if failures else 0)
