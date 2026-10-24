extends "res://tools/test_deferred_backpressure.gd"
class CountedQueue extends Queue:
	var snapshot_reads:=0
	func _materialize_pending_snapshot()->Array:
		snapshot_reads+=1
		return super._materialize_pending_snapshot()
func run()->void:
	var map:=Node3D.new();root.add_child(map);map.set_meta("stream_library",[])
	for key:String in Index.build([]):map.set_meta(key,Index.build([])[key])
	map.set_meta("extras",{"rmmo_records":[]})
	var queue:=CountedQueue.new();queue._doc=Document.new();queue._reference_root="D:/code/rmmo"
	var rows:Array=[]
	for i in 2400:rows.append(item("native%d"%i,float(i)))
	queue.pending=rows;map.add_child(queue);queue.activate(map);queue.set_process(false)
	queue.set_demand("test",AABB(Vector3(-1,-1,-1),Vector3(3000,3,3)),10)
	queue.set_process(false);queue._refresh_demanded();queue.snapshot_reads=0
	queue._dispatch_jobs(self)
	check(queue.started.size()>0,"native CPU tasks dispatch within the normal time budget")
	check(queue.snapshot_reads==0,"native tasks never traverse the model collision-consumer snapshot")
	print("NATIVE_DISPATCH_SNAPSHOT reads=",queue.snapshot_reads," jobs=",queue.started.size())
	map.free();await process_frame;quit(1 if failed else 0)
