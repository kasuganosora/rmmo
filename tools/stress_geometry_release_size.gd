extends SceneTree
const Size=preload("res://scripts/world3d/cpu_geometry_size.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func batch(inputs:Array,first:int,step:int,cached:bool)->Dictionary:
	var measure:=Size.new();var sum:=0
	var began:=Time.get_ticks_usec()
	for i:int in range(first,8192,step):
		var data:Dictionary=inputs[i%inputs.size()]
		sum+=measure.measure(data.surfaces,data.lods,data.key if cached else "")
	return {"us":Time.get_ticks_usec()-began,"sum":sum,"scans":measure.scans,"hits":measure.hits,"channels":measure.channels}
func run()->void:
	var inputs:Array=[];var expected:=0
	for i:int in 8:
		var surface:Array=[PackedByteArray([1,2,3]),PackedInt32Array([1,2]),PackedInt64Array([3,4]),PackedFloat32Array([1.25]),PackedFloat64Array([2.5]),PackedVector2Array([Vector2.ONE]),PackedVector3Array([Vector3.ONE]),PackedColorArray([Color.WHITE]),PackedVector4Array([Vector4.ONE]),null]
		var levels:Dictionary={1.:PackedInt32Array([0,1,2])};var surfaces:Array=[];var lods:Array=[]
		for j:int in i+1:surfaces.append(surface);lods.append(levels)
		var row:={"surfaces":surfaces,"lods":lods,"key":"known:"+str(i)};inputs.append(row)
		expected+=Size.new().measure(surfaces,lods)*1024
	var source:=var_to_bytes(inputs);var trials:Array=[]
	for cached:bool in [false,true,true,false]:
		var result:=batch(inputs,0,1,cached);result.cached=cached;trials.append(result)
		check(result.sum==expected,"8192 fixed shared-geometry byte counts remain exact")
		check(result.scans==(8 if cached else 8192),"only the eight distinct geometry identities are scanned when enabled")
	var parallel:Array=[]
	for width:int in [1,3,12]:
		var threads:Array[Thread]=[];var began:=Time.get_ticks_usec()
		for i:int in width:
			var worker:=Thread.new();check(worker.start(batch.bind(inputs,i,width,true))==OK,"private size worker starts");threads.append(worker)
		var sum:=0;var scans:=0;var hits:=0
		for worker:Thread in threads:
			var result:Dictionary=worker.wait_to_finish();sum+=result.sum;scans+=result.scans;hits+=result.hits
		parallel.append({"width":width,"us":Time.get_ticks_usec()-began,"scans":scans,"hits":hits,"calls":8192})
		check(sum==expected and scans+hits==8192,"parallel work keeps fixed calls and exact counts")
	var cache:=Size.new();var row:Dictionary=inputs[0]
	var base:=cache.measure(row.surfaces,row.lods,"one")
	var changed:Array=row.lods.duplicate(true);changed[0][2.]=PackedInt32Array([1,2,3])
	check(cache.measure(row.surfaces,changed,"new_lod")==base+12,"new LOD identity cannot reuse old byte count")
	for i:int in Size.LIMIT+1:cache.measure(row.surfaces,row.lods,"bounded:"+str(i))
	check(cache.sizes.size()<=Size.LIMIT,"size cache stays bounded and owns only scalar results")
	check(var_to_bytes(inputs)==source,"borrowed geometry is never mutated")
	var report:={"failures":failures,"trials":trials,"parallel":parallel,"logical_sum":expected}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("GEOMETRY_RELEASE_SIZE ",JSON.stringify(report));quit(1 if failures else 0)
