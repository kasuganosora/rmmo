extends "res://tools/test_stream_index_retire.gd"
const Trace=preload("res://scripts/world3d/load_trace.gd")
func fixture()->Dictionary:
	var library:Array=[];var ids:Array=[];var mesh:=BoxMesh.new()
	for i:int in 2200:
		var item:=spec("guild__part%d"%i,Vector2i(50,50),Vector2i(50,50),{"kind":"asset","building":{"id":"group%d"%(i%10)}});item.mesh=mesh;library.append(item);ids.append(item.uuid)
	for i:int in 2400:
		var item:=spec("keep%d"%i,Vector2i.ZERO,Vector2i.ZERO,{"kind":"asset"});item.mesh=mesh;library.append(item)
	return {"data":Index.build(library),"library":library,"ids":ids}
func compare(f:Dictionary,ids:Array,label:String)->void:
	var frozen:Dictionary=f.data.duplicate(true);var rows:Array=f.library.duplicate(true)
	Index.retirement_schema_workers=0;var before:=Index.validate_owned_retire(f.data,f.library,ids)
	Index.retirement_schema_workers=4;var after:=Index.validate_owned_retire(f.data,f.library,ids)
	check(before==after and f.data==frozen and f.library==rows,label+" keeps the complete decision and performs zero writes")
func released()->WeakRef:
	var f:=fixture();var watch:WeakRef=weakref(f.library[0].mesh)
	Index.validate_owned_retire(f.data,f.library,f.ids)
	return watch
func run()->void:
	var f:=fixture()
	compare(f,f.ids,"complete large namespace")
	compare(f,f.ids.slice(1),"incomplete namespace")
	compare(f,f.ids+[f.ids[0]],"duplicate request")
	compare(f,["absent"],"missing request")
	compare(f,[],"empty request still validates every resident source")
	var proof:Dictionary=Index._retirement_library_schema(f.library,f.data.stream_by_id,{"guild":true,"missing":true})
	check(proof.ok and proof.seen.size()==4600 and proof.namespace_sizes=={"guild":2200},"only requested prefix counts are stored; all source identities are still checked")
	Trace.start();Index.validate_owned_retire(f.data,f.library,f.ids);var trace:=Trace.stop()
	var workers:Dictionary={}
	for row:Dictionary in trace.stats:
		if row.label=="stream.retirement_schema_slice":workers[row.thread_id]=true
	check(workers.size()==mini(4,OS.get_processor_count()) and (workers.size()==1 or not workers.has(OS.get_main_thread_id())),"real bounded worker threads perform the pure schema scan")
	for field:String in ["mesh","transform","extras","ground_batch_record","chunk_min"]:
		f=fixture();f.library[-1][field]=17;compare(f,f.ids,"malformed surviving "+field)
		check(not Index.validate_owned_retire(f.data,f.library,f.ids).ok,"malformed surviving "+field+" remains rejected")
	f=fixture();f.library[2300]=f.library[0];compare(f,f.ids,"same source repeated across worker partitions")
	check(not Index.validate_owned_retire(f.data,f.library,f.ids).ok,"cross-partition duplicate cannot hide behind local seen sets")
	f=fixture();f.data.stream_by_id[f.library[-1].uuid]=f.library[-1].duplicate();compare(f,f.ids,"different dictionary at a resident UUID")
	f=fixture();f.library[-1]=17;var frozen:Dictionary=f.data.duplicate(true)
	check(not Index.validate_owned_retire(f.data,f.library,f.ids).ok and f.data==frozen,"non-dictionary library member rejects gracefully after every reader has joined")
	f={};proof={};check(released().get_ref()==null,"joined readers/proof metadata retain no meshes after their caller exits")
	print("PARALLEL_RETIREMENT_SCHEMA checks=",checks," failures=",failures);quit(1 if failures else 0)
