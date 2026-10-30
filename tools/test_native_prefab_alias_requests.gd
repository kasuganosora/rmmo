extends "res://tools/test_editor_native_asset_requests.gd"
const Dependencies=preload("res://scripts/world_editor/native_prefab_dependencies.gd")
var observations:Array=[]

func native_reads(trace:Dictionary)->int:
	var count_:=0
	for row:Dictionary in trace.stats:
		if row.label=="compiled.native_read":count_+=int(row.count)
	return count_
func alias_run(label:String)->void:
	var model:=fixture("alias_"+label,true)
	var alias:=Dependencies.capture(model.path,content_root.path_join("packs/"+label+"/assets"),{})
	check(alias.ok,label+": portable registration captured")
	if not alias.ok:return
	var host:=Host.new();root.add_child(host);var consumer:=Node.new();host.add_child(consumer)
	var service:Node=load(ServicePath).for_consumer(consumer);var pool:=ControlledPool.new();pool.hold=true;configure(service,pool)
	Trace.minimum_event_us=0;Trace.start()
	var original:int=service.request(model.path,consumer,received)
	var duplicate:int=service.request(alias.path,consumer,received)
	var deadline:=Time.get_ticks_msec()+5000
	while not pool.has_entered() and Time.get_ticks_msec()<deadline:await process_frame
	check(pool.has_entered() and service.profile.producers==1 and service.profile.joined==1,label+": cold original and alias share one native preparation")
	check(host._shared_preparation_ledger.reserved_bytes>0,label+": shared preparation keeps one charged owner while blocked")
	var index:=Compiled.index_path(model.path,content_root);var held:=index+".held"
	if label=="cancel":check(service.cancel(original),"cancel one logical subscriber while the alias continues")
	elif label=="changed":check(DirAccess.rename_absolute(index,held)==OK,"invalidate only original registration before delivery")
	pool.gate.post()
	var alias_reply:=await wait_reply(duplicate)
	check(alias_reply.get("ok",false) and alias_reply.handle.path==alias.path and alias_reply.handle.current(),label+": alias receives its own current logical handle")
	if label=="cancel":check(not replies.has(original),"cancelled logical subscriber gets no late result")
	else:
		var original_reply:=await wait_reply(original)
		check(original_reply.get("ok",false)==(label!="changed"),label+": original delivery checks only its own registration")
		if original_reply.get("ok",false):check(original_reply.handle.path==model.path and original_reply.handle.packed==alias_reply.handle.packed,"concurrent logical handles retain the same exact PackedScene")
		original_reply={}
	if label=="changed":check(DirAccess.rename_absolute(held,index)==OK,"restore source registration independently")
	var again:int=service.request(model.path,consumer,received);var sequential:=await wait_reply(again)
	check(sequential.get("ok",false) and sequential.handle.path==model.path and sequential.handle.packed==alias_reply.handle.packed,label+": sequential original request borrows the alias's adopted template")
	check(service.profile.producers==1 and pool.audit.created==1 and service.ownership_tracker.adoptions==1,label+": one geometry producer, texture producer and adoption")
	check(DirAccess.rename_absolute(index,held)==OK,label+": withhold original after both handles exist")
	check(not sequential.handle.current() and alias_reply.handle.current(),label+": original invalidation does not invalidate alias")
	check(DirAccess.rename_absolute(held,index)==OK,label+": restore original identity")
	var alias_index:=Compiled.index_path(alias.path,content_root);var alias_held:=alias_index+".held"
	check(DirAccess.rename_absolute(alias_index,alias_held)==OK,label+": withhold alias registration")
	check(sequential.handle.current() and not alias_reply.handle.current(),label+": alias invalidation does not invalidate original")
	check(DirAccess.rename_absolute(alias_held,alias_index)==OK,label+": restore alias identity")
	var trace:=Trace.stop();check(native_reads(trace)==1,label+": actual compiled SCN read happens once")
	var weak:WeakRef=weakref(alias_reply.handle.packed)
	observations.append({"case":label,"native_reads":native_reads(trace),"profile":service.profile.duplicate(true),"adoptions":service.ownership_tracker.adoptions,"texture_stub_creations":pool.audit.created})
	alias_reply={};sequential={};replies.clear();await settle(host._shared_preparation_ledger,pool)
	deadline=Time.get_ticks_msec()+5000
	while weak.get_ref()!=null and Time.get_ticks_msec()<deadline:await process_frame
	check(weak.get_ref()==null and host._shared_preparation_ledger.reserved_bytes==0,label+": all aliases release the native owner and preparation budget")
	service.close();host.free();await process_frame

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	for label:String in ["normal","cancel","changed"]:await alias_run(label)
	write(content_root.get_base_dir().path_join("observations.json"),JSON.stringify({"checks":checks,"failures":failures,"cases":observations,"scope":"Real native SCN/table IO and production service. Split texture/ownership are explicit existing CPU protocol stubs; not GPU proof."},"\t"))
	print("NATIVE_PREFAB_ALIAS checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
