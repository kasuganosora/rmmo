extends SceneTree
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Bounds=preload("res://scripts/world3d/road_record_bounds.gd")
const Fixture=preload("res://tools/test_native_road_preparation.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func batch(records:Array,indices:Array,streamed:bool)->Array:
	var result:Array=[]
	for i:int in indices:result.append(Bounds.measure(records[i]) if streamed else Index._road_bounds(records[i]))
	return result
func run()->void:
	Bounds.enabled=false
	var helper:=Fixture.new();var records:Array=[]
	for i:int in 80:
		var record:=helper.road();record.rotation=[i*7.3,i*11.7,-i*5.2];record.position=[-49999.12+i*31.2,74.75,42990.25-i*17.3]
		record.size=[16.+i,.125+i*.075,30.-i*.1];record.road_mesh.grade=[.03,-.02];record.road_mesh.kerbs=[]
		if i%3==0:record.road_mesh.elevations=[[.1,.2,.25,.3]]
		if i%2==0:record.terrain_grade=[-.02,.01]
		for j:int in 256:record.road_mesh.kerbs.append(helper.part(j%2==0,j%3==0))
		records.append(record)
	var before:=var_to_bytes(records);var rows:Array=[];var expected:Array=[]
	for fast:bool in [false,true,true,false]:
		var began:=Time.get_ticks_usec();var actual:=batch(records,range(records.size()),fast);var elapsed:=Time.get_ticks_usec()-began
		if expected.is_empty():expected=actual
		check(actual==expected,"streamed bounds are bit-exact across poses, grades, elevations and kerbs")
		rows.append({"streamed":fast,"us":elapsed})
	var parallel:Array=[]
	for count:int in [1,3,12]:
		var began:=Time.get_ticks_usec();var threads:Array=[];var jobs:Array=[]
		for i:int in count:
			var indices:Array=[]
			for j:int in range(i,records.size(),count):indices.append(j)
			jobs.append(indices);var thread:=Thread.new();thread.start(batch.bind(records,indices,true));threads.append(thread)
		var exact:=true
		for i:int in count:
			var result:Array=threads[i].wait_to_finish()
			for j:int in jobs[i].size():exact=exact and result[j]==expected[jobs[i][j]]
		parallel.append({"workers":count,"us":Time.get_ticks_usec()-began});check(exact,"fixed 80 roads remain exact with %d workers"%count)
	var invalid:=helper.road();invalid.road_mesh.polygons[0][0][0]=INF
	check(not Bounds.measure(invalid).known,"nonfinite geometry has no finite spatial proof")
	var empty:=helper.road();empty.road_mesh.polygons=[]
	check(not Bounds.measure(empty).known,"empty geometry has no spatial bounds")
	check(var_to_bytes(records)==before,"all authored records remain unchanged")
	helper.free();var report:={"failures":failures,"roads":80,"kerbs_per_road":256,"runs":rows,"parallel":parallel}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):var file:=FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(1 if failures else 0)
