extends SceneTree
## Equal 96000 task bodies for 1/2/12 writers. No file I/O inside a timed trial.
const Timeline=preload("res://scripts/util/debug_timeline.gd")
const TOTAL:=96000
var output:=""
func _initialize()->void:run.call_deferred()
static func work(mode:String,label_id:int,task:int,count_:int)->int:
	var sum_:=0
	for i in count_:
		var span:=Timeline.begin(label_id,task) if mode!="baseline" else 0
		sum_+=i%16
		if mode!="baseline":
			Timeline.mark(label_id,task,i)
			Timeline.end(span)
	return sum_
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/") or not Timeline.available():quit(2);return
	var label_id:=Timeline.label("benchmark.task")
	var rows:Array=[];var failed:=false
	for writers:int in [1,2,12]:
		for mode:String in ["baseline","disabled","enabled","enabled_cpu","enabled","disabled","baseline"]:
			var enabled_:bool=mode.begins_with("enabled")
			if enabled_ and Timeline.start(TOTAL*4,mode=="enabled_cpu")!=OK:quit(2);return
			var threads:Array=[];var sum_:=0;var started:=Time.get_ticks_usec()
			for i in writers:
				var thread:=Thread.new();threads.append(thread)
				if thread.start(work.bind(mode,label_id,i,TOTAL/writers))!=OK:quit(2);return
			for thread:Thread in threads:sum_+=int(thread.wait_to_finish())
			var elapsed:=Time.get_ticks_usec()-started
			var stats:Dictionary=Timeline.stop() if enabled_ else {}
			var ok:bool=sum_==TOTAL*15/2 and (not enabled_ or (stats.dropped==0 and stats.events==TOTAL*3))
			failed=failed or not ok
			rows.append({"writers":writers,"mode":mode,"tasks":TOTAL,"wall_us":elapsed,"checksum":sum_,"stats":stats,"ok":ok})
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"failed":failed,"scope":"Independent diagnostic component throughput; same task count. Includes GD wrapper, thread start/join, and optional OS CPU query. No claim of game loading or frame improvement."},"\t"))
	print("TIMELINE_BENCHMARK ",JSON.stringify(rows));quit(1 if failed else 0)
