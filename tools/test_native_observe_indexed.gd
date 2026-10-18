extends "res://tools/test_stream_index_append.gd"
const Native=preload("res://scripts/world3d/native_residency.gd")
const CANDIDATE:="res://scripts/world3d/native_residency.gd"
const CONTROL:="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/native_residency_before_observe_groups.gd"
class Ordinary extends Node:
	var handed:Array=[]
	func _init()->void:name="AssetResidency"
	func handoff_native(uuid:String)->void:handed.append(uuid)
class Queue extends Node:
	var calls:Array=[]
	func register_runtime_building(uuid:String,bounds:AABB,supports:Dictionary)->void:calls.append([uuid,bounds,supports.duplicate()])
func fixture(script:Script)->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	var ordinary:=Ordinary.new();map.add_child(ordinary)
	var queue:=Queue.new();map.add_child(queue)
	var service:Node=script.new();map.add_child(service);service.set_process(false);service._map=map;service._queue=queue
	for id:String in ["model","unsafe"]:
		service._model_entries[id]={"compact_record":{"uuid":id},"bounds":AABB(Vector3.ZERO,Vector3.ONE)}
	service._retired={"asset:model":true}
	return {"map":map,"ordinary":ordinary,"queue":queue,"service":service}
func snapshot(f:Dictionary)->Dictionary:
	var counters:Dictionary=f.service.profile.duplicate(true);counters.erase("observed_bounds")
	return {"owners":f.service._owners.duplicate(true),"units":f.service._units.duplicate(true),"resident":f.service._resident.duplicate(true),"retired":f.service._retired.duplicate(true),"profile":counters,"handoff":f.ordinary.handed.duplicate(),"registrations":f.queue.calls.duplicate(true)}
func run()->void:
	var candidate:Script=load(CANDIDATE)
	var control:Script=load(CONTROL) if FileAccess.file_exists(CONTROL) else Native
	var rows:Array=[]
	for i:int in 2151:rows.append(spec("model__part%d"%i,Vector2i(i%4,0),Vector2i(i%4,0),{"uuid":"model"},{"building":{"id":"group%d"%(i%156)}}))
	rows.push_front(spec("model__anchor",Vector2i(-2,0),Vector2i(-2,0),{"uuid":"model"}))
	rows.append(spec("unsafe__early",Vector2i.ZERO,Vector2i.ZERO,{}, {"building":{"id":"unsafe"}}))
	var late:=spec("unsafe__late",Vector2i.ONE,Vector2i.ONE,{}, {"building":{"id":"unsafe"}});late.native_visual=true;rows.append(late)
	rows.append(ground("support",Vector2i.ZERO,Vector2i(4,0)))
	Index.build(rows)
	var old:=fixture(control);var improved:=fixture(candidate)
	old.service.observe(rows);improved.service.observe(rows)
	check(snapshot(old)==snapshot(improved),"whole namespace, anchor order, late unsafe owner, bounds, support closure and original IDs match the reference observer")
	check(improved.service._resident["asset:model"].ids.size()==2152 and not improved.service._owners.has("unsafe"),"shared groups retain every part and reject late native-visual ownership")
	check(improved.service.profile.observed_bounds==157,"2152 parts keep complete ownership while only 156 shared groups and one independent anchor expand bounds")
	check(improved.service._units["asset:model"].support_ids=={"support":true} and improved.service._units["asset:model"].bounds.position.x==-64. and improved.service._units["asset:model"].bounds.end.x==160.,"anchor and exact ground support expand the expected complete 32 m-cell envelope")
	old.service.observe(rows);improved.service.observe(rows)
	check(snapshot(old)==snapshot(improved) and improved.service.profile.revisits==1,"repeated observation preserves idempotent membership and exact revisit accounting")
	# A repeated group label with a different mutable bounds object still grows
	# the conservative unit envelope; group strings alone cannot prove identity.
	rows[2].render_bounds={"chunk_min":Vector2i(-20,-10),"chunk_max":Vector2i(20,10)}
	old.service.observe(rows);improved.service.observe(rows)
	check(snapshot(old)==snapshot(improved),"distinct mutable bounds under the same group name cannot be skipped")
	old.map.free();improved.map.free()
	var timings:Dictionary={"before":[],"after":[]}
	for round_:int in 12:
		for label:String in (["before","after"] if round_%2==0 else ["after","before"]):
			var f:=fixture(control if label=="before" else candidate)
			var began:=Time.get_ticks_usec();f.service.observe(rows);timings[label].append((Time.get_ticks_usec()-began)/1000.)
			f.map.free()
	for label:String in timings:
		var values:Array=timings[label];values.sort();var total:=0.
		for value:float in values:total+=value
		print("NATIVE_OBSERVE ",label," mean_ms=",total/values.size()," p50_ms=",values[values.size()/2]," max_ms=",values[-1])
	print("NATIVE_OBSERVE_INDEXED failures=",failures);quit(1 if failures else 0)
