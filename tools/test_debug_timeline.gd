extends SceneTree
const Timeline=preload("res://scripts/util/debug_timeline.gd")
var failures:Array=[]
var checks:=0
var output:=""
var reports:Dictionary={}

func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	checks+=1
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures.append(label_)

static func writer(label_id:int,task:int,count_:int)->Dictionary:
	var started:=Time.get_ticks_usec()
	for i in count_:
		var token:=Timeline.begin(label_id,task)
		Timeline.mark(label_id,task,i)
		Timeline.end(token)
	return {"task":task,"count":count_,"elapsed_us":Time.get_ticks_usec()-started,"thread":OS.get_thread_caller_id()}

static func held_writer(label_id:int,entered:Semaphore,release_:Semaphore)->Dictionary:
	var span:=Timeline.begin(label_id,9001)
	entered.post();release_.wait()
	Timeline.end(span) # Old capture token, deliberately closed after restart.
	return writer(label_id,9002,10)

static func worker_control(label_id:int)->Dictionary:
	return {"start":Timeline.start(256),"label":Timeline.label("must_not_register"),"stop":Timeline.stop(),"mark":label_id}

static func named_writer(label_id:int,context:int)->void:
	for i in 512:
		Timeline.task_name(i,context,"prepare/石材" if i%2==0 else "release/木材")
		var token:=Timeline.begin(label_id,i,context)
		Timeline.end(token)

func capture_done(name_:String)->Dictionary:
	var info:=Timeline.stop()
	check(not info.get("active",true),name_+": stopped")
	check(Timeline.export_capture(output.path_join(name_+".rmtrace"))==OK,name_+": exports after capture")
	reports[name_]=info
	return info

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="):output=arg.trim_prefix("--output-dir=").replace("\\","/")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/"):
		printerr("Requires isolated external --output-dir");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	check(Timeline.available(),"candidate exposes native GD controls")
	if not Timeline.available():quit(2);return
	var work_label:=Timeline.label("test.work")
	check(work_label>0 and Timeline.label("test.work")==work_label,"labels reuse one stable ID")
	check(Timeline.begin(work_label)==0,"disabled begin is a no-op")
	check(Timeline.start(0)==ERR_INVALID_PARAMETER,"invalid capacity rejected without enabling capture")
	check(Timeline.start(524288,true)==OK,"capture starts with explicit capacity and CPU clock")
	check(Timeline.start(256)==ERR_BUSY,"nested start cannot replace live buffers")
	check(Timeline.export_capture(output.path_join("must_not_exist.rmtrace"))==ERR_BUSY and not FileAccess.file_exists(output.path_join("must_not_exist.rmtrace")),"active capture never writes an export")
	var threads:Array=[]
	for i in 12:
		var thread:=Thread.new();threads.append(thread)
		check(thread.start(writer.bind(work_label,i+1,4096))==OK,"independent writer starts "+str(i))
	var receipts:Array=[]
	for thread:Thread in threads:receipts.append(thread.wait_to_finish())
	var info:=capture_done("parallel")
	check(info.dropped==0 and info.events>=147456 and info.threads>=12,"twelve writers retain all 147456 user records")
	check(receipts.size()==12 and receipts.all(func(row):return row.count==4096),"every private writer completes its own work")
	reports.parallel_receipts=receipts
	var altered:=Timeline.stop();altered.events=-1
	check(Timeline.status().events>=147456,"caller cannot mutate retained capture statistics")

	check(Timeline.start(4096)==OK,"held-worker capture starts")
	var entered:=Semaphore.new();var release_:=Semaphore.new();var slow:=Thread.new();var fast:=Thread.new()
	check(slow.start(held_writer.bind(work_label,entered,release_))==OK,"held writer starts")
	entered.wait()
	check(fast.start(writer.bind(work_label,8001,128))==OK,"unrelated writer starts while first waits")
	var fast_result:Dictionary=fast.wait_to_finish()
	check(fast_result.count==128 and slow.is_alive(),"another writer finishes while held writer remains blocked")
	var before_stop:=Time.get_ticks_usec();info=capture_done("held")
	reports.stop_wall_us=Time.get_ticks_usec()-before_stop
	check(slow.is_alive() and info.dropped==0,"stop waits for event writes, not for a held task")
	check(Timeline.start(4096)==OK,"next capture starts while old scope is still open")
	release_.post();var slow_result:Dictionary=slow.wait_to_finish()
	check(slow_result.count==10,"old writer can resume and use the new capture")
	info=capture_done("restart")
	check(info.dropped==0,"restart retains every new event")

	check(Timeline.start(256)==OK,"bounded capture starts")
	for i in 300:Timeline.mark(work_label,42,i)
	info=capture_done("overflow")
	check(info.events==256 and info.dropped==44,"overflow reports losses instead of overwriting history")
	var controller:=Thread.new();controller.start(worker_control.bind(work_label))
	var rejected:Dictionary=controller.wait_to_finish()
	check(rejected.start==ERR_UNAUTHORIZED and rejected.label==-1 and rejected.stop.get("error")==ERR_UNAUTHORIZED,"worker control calls fail without changing capture ownership")
	check(not Timeline.status().active,"invalid worker control leaves capture stopped")
	check(Timeline.start(8192)==OK,"named concurrent task capture starts")
	threads=[]
	for i in 3:
		var thread:=Thread.new();threads.append(thread)
		check(thread.start(named_writer.bind(work_label,300+i))==OK,"thread-private names writer starts "+str(i))
	for thread:Thread in threads:thread.wait_to_finish()
	info=capture_done("names")
	check(info.events==4608 and info.dropped==0,"concurrent task names and work are all captured")
	check(Timeline.start(256)==OK,"name overflow capture starts")
	for i in 300:Timeline.task_name(i,99,"unique_name_"+str(i))
	info=capture_done("names_overflow")
	check(info.events==256 and info.dropped==44,"name metadata stops growing with event overflow")
	# Exercise stop/restart while native event writes are active, rather than
	# only while a scope is parked at a semaphore. Missing ends at window edges
	# are expected; the decoder must never see corrupt records or orphan ends.
	check(Timeline.start(65536)==OK,"concurrent restart stress starts")
	threads=[]
	for i in 4:
		var thread:=Thread.new();threads.append(thread)
		check(thread.start(writer.bind(work_label,10000+i,20000))==OK,"restart stress writer starts "+str(i))
	for i in 8:
		OS.delay_usec(1000)
		capture_done("race_%02d"%i)
		check(Timeline.start(65536)==OK,"restart is safe while other threads keep writing "+str(i))
	for thread:Thread in threads:
		check(thread.wait_to_finish().count==20000,"concurrent restarts do not interrupt actual work")
	capture_done("race_final")
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"reports":reports},"\t"))
	print("DEBUG_TIMELINE checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
