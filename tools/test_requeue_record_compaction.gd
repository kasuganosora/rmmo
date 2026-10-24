extends SceneTree
## Survivor-rich record arrays, unlike the all-retired or empty-catalog fixtures.
const Queue=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
var queue_type:Script=Queue
var failures:=0
var checks:=0
var reports:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func fixture(count:int)->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	var queue:Node=queue_type.new();map.add_child(queue);queue.set_process(false);queue._map=map
	queue._reference_index={"models":{}}
	var records:Array=[]
	for i:int in count:
		var heights:Array=[];heights.resize(128);heights.fill(i)
		var row:={"uuid":"record%d"%i,"terrain_mesh":{"heights":heights}}
		records.append(row);queue._runtime_record_ids[row.uuid]=row
	map.set_meta("extras",{"rmmo_records":records})
	queue._index_pending()
	return {"map":map,"queue":queue,"records":records}
func drain()->void:
	var service:Node=root.get_node_or_null(Retirement.NODE_NAME)
	if service==null:return
	service.set_process(false)
	var steps:=0
	while not service.pending.is_empty() and steps<20000:
		if service._advance(service.pending[0],1000):service._finish_front()
		steps+=1
		if steps%64==0:OS.delay_usec(100)
	check(service.pending.is_empty() and service.known.is_empty(),"background decoded records fully release")
func trial(name:String,selected:Array,background:bool)->void:
	Retirement.background_decoded_release_enabled=background
	var f:=fixture(4600);var expected:Array=[];var entries:Array=[];var chosen:Dictionary={}
	for i:int in selected:
		var uuid:="record%d"%i;chosen[uuid]=true
		entries.append({"compact_record":{"uuid":uuid},"asset_path":"model.res","bounds":AABB(Vector3.ZERO,Vector3.ONE),"record_index":i})
	var moved:=0;var read:=0
	for row:Dictionary in f.records:
		if not chosen.has(row.uuid):
			if expected.size()!=read:moved+=1
			expected.append(row)
		read+=1
	var borrowed:Array=f.records[-1].terrain_mesh.heights
	var began:=Time.get_ticks_usec();var accepted:int=f.queue.requeue_references(entries);var elapsed:=Time.get_ticks_usec()-began
	var writes:int=f.queue.profile.get("requeue_record_write_rows",-1)
	check(accepted==chosen.size(),"accept each selected entry once")
	check(is_same(f.records,f.map.get_meta("extras").rmmo_records) and f.records==expected,"in-place compaction preserves exact stable survivors")
	var same:=true
	for i:int in expected.size():same= same and is_same(f.records[i],expected[i])
	check(same,"surviving decoded identities are unchanged")
	check(writes==moved,"WORK only displaced survivors are assigned")
	var before:Dictionary=f.queue.profile.duplicate()
	check(f.queue.requeue_references(entries)==0 and f.queue.profile==before,"duplicate transaction does not rescan or rewrite")
	drain();check(borrowed.size()==128 and borrowed[0]==4599,"borrowed nested arrays remain intact")
	reports.append({"case":name,"background":background,"records":4600,"selected":chosen.size(),"survivors":expected.size(),"required_writes":moved,"actual_writes":writes,"main_us":elapsed})
	borrowed=[];expected=[];f.map.free();f={};drain()
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--legacy-requeue-script="):queue_type=load(arg.trim_prefix("--legacy-requeue-script="))
	for background:bool in [true,false]:
		trial("tail",range(4584,4600),background)
		trial("middle",[2300,2301,2301,2400],background)
		trial("head",range(0,16),background)
		trial("absent",[4600,4601],background)
		trial("all",range(4600),background)
	Retirement.background_decoded_release_enabled=true
	print("REQUEUE_RECORD_COMPACTION ",JSON.stringify({"checks":checks,"failures":failures,"reports":reports}))
	quit(1 if failures else 0)
