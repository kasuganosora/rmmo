extends "res://tools/test_stream_index_append.gd"
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
func fixture()->Dictionary:
	var map:=Node3D.new();root.add_child(map)
	map.set_meta("stream_library",[])
	var data:=Index.build([])
	for key:String in data:map.set_meta(key,data[key])
	var queue:=Deferred.new();map.add_child(queue);queue._map=map;queue.set_process(false)
	var item:Dictionary={"path":"private-fixture","record":{"uuid":"large","kind":"asset"},"native_reference":true,"model_verified":true}
	queue.pending=[item];queue._demanded=[item];queue._demanded_by_id={"large":item};queue._demanded_rank={"large":0};queue._demanded_by_path={"private-fixture":[item]}
	queue._admission.reserve(item.path,{"estimated_bytes":1048576,"exclusive":false});queue._admission.park(item.path)
	queue._jobs[item.path]={"token":Drainer.CancelToken.new(),"result":{}}
	var specs:Array=[];var mesh:=BoxMesh.new()
	for i:int in 600:
		var value:=spec("large__part%d"%i,Vector2i.ZERO,Vector2i.ZERO,{}, {"building":{"id":"building"}})
		value.mesh=mesh;specs.append(value)
	return {"map":map,"queue":queue,"item":item,"specs":specs}
func run()->void:
	var fixture_:Dictionary=fixture();var queue:Node=fixture_.queue;var map:Node=fixture_.map
	var source:Array=fixture_.specs;var item:Dictionary=fixture_.item
	var emissions:Dictionary={"count":0,"size":0}
	queue.published.connect(func(values:Array):emissions.count+=1;emissions.size=values.size())
	check(not queue._publish_items([item],source) and not item.get("published",false) and map.get_meta("stream_library").is_empty(),"large actual publication first yields with no visible partial namespace")
	var calls:=1
	while not item.get("published",false) and calls<10000:
		queue._publish_items([item],source);calls+=1
	check(item.get("published",false) and calls>1 and emissions.count==1 and emissions.size==600,"all prepared parts publish exactly once through the actual queue")
	check(map.get_meta("stream_library").size()==600 and queue.pending.is_empty() and queue._jobs[item.path].collision_staged.is_empty(),"successful append transfers every identity and clears only staging ownership")
	check(queue._admission.reserved_bytes==1048576,"private preparation never releases the admitted job reservation")
	queue._discard_job(item.path);check(queue._admission.reserved_bytes==0,"normal post-publication discard releases its original reservation")
	map.free();fixture_={};source=[];item={}
	fixture_=fixture();queue=fixture_.queue;map=fixture_.map;item=fixture_.item;source=fixture_.specs
	queue._publish_items([item],source)
	var packet:Dictionary=queue._jobs[item.path].collision_staged[item.record.uuid]
	while not packet.index_preparation.advance(100):pass
	source[0].transform.origin+=Vector3.RIGHT
	check(not queue._publish_items([item],source) and queue.profile.get("index_preparation_restarts",0)==1 and queue.instance_errors.is_empty() and map.get_meta("stream_library").is_empty(),"pose mutation after preparation retries without failing the owner or touching the public index")
	var passes:=0
	while not item.get("published",false) and passes<10000:queue._publish_items([item],source);passes+=1
	check(item.get("published",false) and map.get_meta("stream_by_id")[source[0].uuid].transform==source[0].transform,"retry publishes the latest pose under the original complete namespace")
	map.free();fixture_={};source=[];item={};packet={}
	fixture_=fixture();queue=fixture_.queue;map=fixture_.map;item=fixture_.item;source=fixture_.specs
	Index.build(source)
	check(queue._publish_items([item],source) and item.published and map.get_meta("stream_library").size()==600,"already-derived input retains the ordinary validated append path instead of donating an unsafe fragment")
	map.free();fixture_={};source=[];item={}
	fixture_=fixture();queue=fixture_.queue;map=fixture_.map;item=fixture_.item;source=fixture_.specs
	queue._publish_items([item],source)
	var watch:WeakRef=weakref(source[0].mesh);var ledger:RefCounted=queue._admission
	fixture_={};source=[];item={};map.free()
	check(watch.get_ref()==null and ledger.reserved_bytes==0,"map exit disposes the partially built index, private specs and their admission lease")
	print("DEFERRED_INDEX_PREPARATION failures=",failures);quit(1 if failures else 0)
