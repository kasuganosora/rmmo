extends SceneTree
const Data=preload("res://scripts/world3d/world_map_data.gd")
var failures:Array=[]
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func run()->void:
	var data:=Data.new();var rng:=RandomNumberGenerator.new();rng.seed=77816
	for i in 4096:
		data.shapes.append({"bounds":Rect2(Vector2(rng.randf_range(-256,256),rng.randf_range(-256,256)),Vector2(12,12)),"height":float(i%17),"map_draw_order":4096-i,"id":i})
	# A footprint in the large-shape side list must still sort among local rows.
	data.shapes.append({"bounds":Rect2(-10000,-10000,20000,20000),"height":3.5,"id":4096})
	data.rebuild_shape_index()
	var queries:Array[Rect2]=[];var expected:Array=[]
	for i in 200:
		var rect:=Rect2(Vector2(rng.randf_range(-200,0),rng.randf_range(-200,0)),Vector2(192,192))
		queries.append(rect)
		var rows:Array=data.shapes.filter(func(s):return rect.intersects(s.bounds));rows.sort_custom(Data._paint_less);expected.append(rows)
	data.query_profile_enabled=true
	var began:=Time.get_ticks_usec();var matches:=true;var indexed:=true;var results:=0
	for i in queries.size():
		var rows:=data.visible_shapes(queries[i]);matches=matches and rows==expected[i];results+=rows.size();indexed=indexed and data.last_query_indexed
	var elapsed:=Time.get_ticks_usec()-began
	check(indexed and matches,"200 dense spatial queries preserve exact height and tie order, including the large-shape side list")
	check(data.query_sort_comparisons==0,"indexed visibility uses existing numeric ranks without scripted sort comparisons")
	check(results>100000,"stress query actually returns dense visible sets")
	var comparisons:=data.query_sort_comparisons
	# Compare elapsed time without the per-comparison work counter. Preserve
	# all ABBA samples, separately from the deterministic functional assertions.
	data.query_profile_enabled=false
	var original_mode:bool=Data.native_visible_order_enabled
	var timings:Array=[]
	for mode:bool in [false,true,true,false]:
		Data.native_visible_order_enabled=mode
		var total:=0;var start:=Time.get_ticks_usec()
		for rect:Rect2 in queries:total+=data.visible_shapes(rect).size()
		timings.append({"native":mode,"elapsed_us":Time.get_ticks_usec()-start,"results":total})
	Data.native_visible_order_enabled=original_mode
	var original:Array=data.shapes.duplicate(true)
	data.shapes.reverse();data.rebuild_shape_index()
	check(data.visible_shapes(queries[0])==expected[0],"same-count replacement rebuilds rank-to-storage mapping")
	data.shapes=original;data.shapes.pop_back() # An unindexed mutation uses the existing scan contract.
	var rows:Array=data.shapes.filter(func(s):return queries[0].intersects(s.bounds));rows.sort_custom(Data._paint_less)
	check(data.visible_shapes(queries[0])==rows and not data.last_query_indexed,"unindexed direct shape edits retain exact fallback order")
	check(data.visible_shapes(Rect2()).is_empty() and data.visible_shapes(Rect2(Vector2.INF,Vector2.ONE)).is_empty(),"empty and nonfinite queries remain empty")
	var report:={"checks":checks,"failures":failures,"queries":queries.size(),"results":results,"elapsed_us":elapsed,"scripted_comparisons":comparisons,"uncounted_abba":timings}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
