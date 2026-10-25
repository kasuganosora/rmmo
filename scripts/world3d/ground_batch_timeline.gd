extends RefCounted
## Opt-in, bounded main-thread evidence. Workers return two scalar timestamps;
## they never mutate this log or retain a source/material for the observer.
static var enabled:=false
const LIMIT:=100000
static var rows:Array=[]
static var dropped:=0

static func record(event:String,generation:int,started:int,detail:Array=[])->void:
	if not enabled:return
	if rows.size()>=LIMIT:dropped+=1;return
	rows.append([event,generation,started,Time.get_ticks_usec(),Engine.get_process_frames(),detail])

static func build(members:Array,origin:Vector3)->Dictionary:
	var started:=Time.get_ticks_usec()
	var data:Dictionary=preload("res://scripts/world3d/ground_batch_geometry.gd").build(members,origin,true)
	data.batch_worker_interval=[started,Time.get_ticks_usec()]
	return data

static func report()->Dictionary:
	return {"columns":["event","generation","start_us","end_us","frame","detail"],"rows":rows,"dropped":dropped,"scope":"Diagnostic wall intervals; worker intervals overlap main work. Generation is local to each batcher."}
