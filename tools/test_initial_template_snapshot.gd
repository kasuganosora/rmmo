extends "res://tools/test_native_texture_preview.gd"
## Exercise the real MapLoader -> instance cursor -> WorldDocument path.
## Only the final static-spec phase is intercepted to inspect and retire the
## small test map without starting streaming, cameras or a gameplay session.
const NEXT_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
class ObservedLoader extends "res://scripts/world3d/map_loader.gd":
	var observed:Dictionary
	var after_first:Callable
	var stop_after:=32
	var cancel_at:=-1
	func _prepare_asset_instance(doc:RefCounted,record:Dictionary,prepared:Dictionary)->Node3D:
		observed.calls+=1
		if prepared.has("template"):observed.template_handoffs+=1
		elif not prepared.has("scene"):observed.lookup_fallbacks+=1
		if observed.calls==2 and after_first.is_valid():
			await get_tree().process_frame
			after_first.call()
		var instance:=await super._prepare_asset_instance(doc,record,prepared)
		if instance!=null and not instance.has_meta("missing_asset"):
			var owner:Variant=instance.get_child(0).get_meta("_compiled_resource_owner",null)
			observed.owner_ids.append(owner.get_instance_id() if owner!=null else 0)
		return instance
	func _prepare_static_asset_specs(_root:Node3D,_instance:Node,_parts:Array,_library:Array)->bool:
		observed.built+=1
		if observed.built==cancel_at:
			_cancelled=true
			await get_tree().process_frame
			return false
		return observed.built<stop_after

func loaded(model:Dictionary)->Dictionary:
	var candidate:=Assets.native_candidate(model.path)
	var packet:=Assets._read_published_native(model.path,candidate)
	check(packet.get("hit",false),"read actual native product for operation snapshot")
	var state:=Binding.begin(packet.packed,{SHA:"prepared"},model.table_sha)
	check(Binding.adopt(state,{"prepared":GradientTexture2D.new()}) and Binding.step(state)==Binding.READY,"operation receives a completed split material graph")
	Binding.release(state)
	packet.path=model.path;packet.candidate=candidate
	return packet

func execute(packet:Dictionary,background:bool=false,after_first:Callable=Callable(),cancel_at:int=-1,admitted:bool=true)->Dictionary:
	var observation:={"calls":0,"built":0,"template_handoffs":0,"lookup_fallbacks":0,"owner_ids":[],"errors":[]}
	var loader:=ObservedLoader.new();loader.observed=observation;loader.after_first=after_first;loader.cancel_at=cancel_at
	root.add_child(loader);loader._building=true;loader.background_preload=background
	loader._model_preparation.require_native_products=true
	loader._model_signatures={packet.path:packet.source_digest};loader._asset_states={packet.path:packet} if admitted else {}
	var records:Array=[]
	for index:int in 32:
		var uuid:="snapshot_%d"%index
		records.append({"kind":"asset","uuid":uuid,"asset_path":packet.path,"position":[index*2.,0,0],"rotation":[0,0,0],"size":[1,1,1],"collision":"none"})
		loader._record_order[uuid]=index
	loader._record_meta={"rmmo_records":records}
	loader.finished.connect(func(_scene:Node,_path:String,error:String):observation.errors.append(error))
	# The external red/green runner optionally counts the real filesystem reads
	# in its frozen Footprint copy. These hooks do not exist in production code.
	var audit:RefCounted=Footprint.new()
	if audit.has_method("test_candidate_reads_reset"):audit.call("test_candidate_reads_reset")
	await loader._build_records()
	if audit.has_method("test_candidate_reads_snapshot"):observation.io=audit.call("test_candidate_reads_snapshot")
	await process_frame
	observation.loader_freed=not is_instance_valid(loader)
	return observation

func replace_version(packet:Dictionary,model:Dictionary,next:Dictionary)->void:
	var index_path:=Compiled.index_path(model.path,content_root)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(index_path));manifest.source_sha=NEXT_SHA
	write(index_path,JSON.stringify(manifest))
	var descriptor_path:=Footprint.descriptor_path(model.path,content_root)
	var envelope:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(descriptor_path))
	var descriptor:Dictionary=JSON.parse_string(envelope.body);descriptor.source_sha=NEXT_SHA
	var body:=JSON.stringify(descriptor)
	write(descriptor_path,JSON.stringify({"version":1,"body":body,"sha256":body.sha256_text()}))
	next.merge(loaded(model),true)
	check(Assets.cache_packed(model.path,next.packed,next.source_digest,next.candidate),"another publication replaces the global template during an await")
	check(next.packed!=packet.packed,"replacement has a distinct native owner")

func all_owner(observed:Dictionary,owner_id:int,count_:int)->bool:
	return observed.owner_ids.size()==count_ and observed.owner_ids.all(func(id):return id==owner_id)

func assert_no_lookup(observed:Dictionary,label:String)->void:
	check(observed.template_handoffs==observed.calls and observed.lookup_fallbacks==0,label+" passes accepted templates through the real instance cursor")
	if observed.has("io"):
		check(observed.io.json_reads==0 and observed.io.product_reads==0,label+" performs no repeated candidate file reads")

func clear_packet(packet:Dictionary)->void:
	var path:String=packet.get("path","")
	Assets._scenes.erase(path);Drainer.dispose_result(packet)
	var service:=root.get_node_or_null("ResourceRetirement")
	for _frame:int in 120:
		if service==null or service.pending.is_empty():break
		await process_frame
	Drainer.synchronize_transfer()

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):
		printerr("This fixture requires an isolated review_artifacts content root");quit(2);return
	create_timer(120).timeout.connect(func():quit(2))
	Drainer.for_tree(self)
	var cases:Dictionary={}
	var model:=fixture("repeated",true);var packet:=loaded(model)
	var id:int=packet.packed.get_instance_id();var reference:WeakRef=weakref(packet.packed)
	cases.foreground=await execute(packet)
	check(cases.foreground.built==32 and cases.foreground.errors.is_empty(),"foreground builds all 32 real instances")
	check(all_owner(cases.foreground,id,32),"all foreground instances use the accepted native owner")
	assert_no_lookup(cases.foreground,"foreground")
	await clear_packet(packet)
	check(cases.foreground.loader_freed and reference.get_ref()==null,"retired foreground loader drops its operation template owner")

	model=fixture("replacement",true);packet=loaded(model);id=packet.packed.get_instance_id()
	var next:Dictionary={}
	cases.replacement=await execute(packet,false,replace_version.bind(packet,model,next))
	check(cases.replacement.built==32 and cases.replacement.errors.is_empty(),"replacement during yield does not abort the accepted load")
	check(all_owner(cases.replacement,id,32),"current operation does not drift to another global template after yielding")
	# The mutation callback intentionally reads the new index once. Inspect the
	# handoff count instead of attributing that separate publication I/O to load.
	check(cases.replacement.lookup_fallbacks==0,"replacement path does not re-resolve the old operation through disk")
	await clear_packet(packet)
	if not next.is_empty():
		id=next.packed.get_instance_id();cases.next_operation=await execute(next)
		check(next.source_digest==NEXT_SHA and all_owner(cases.next_operation,id,32),"next operation accepts the newly published native version")
		assert_no_lookup(cases.next_operation,"next operation")
		await clear_packet(next)

	model=fixture("background",true);packet=loaded(model);id=packet.packed.get_instance_id()
	cases.background=await execute(packet,true)
	check(cases.background.built==32 and all_owner(cases.background,id,32),"background preload preserves its existing private template path")
	assert_no_lookup(cases.background,"background")
	await clear_packet(packet)

	model=fixture("cancel",true);packet=loaded(model);reference=weakref(packet.packed)
	cases.cancel=await execute(packet,false,Callable(),1)
	check(cases.cancel.built==1 and cases.cancel.loader_freed,"cancel after one real instance retires the loader")
	await clear_packet(packet)
	check(reference.get_ref()==null,"cancel and free release the accepted template without hidden retained owners")

	model=fixture("unbound_background",true)
	packet=Assets._read_published_native(model.path,Assets.native_candidate(model.path));packet.path=model.path
	check(not Ready.packed_ready(packet.packed),"unbound native packet has no runtime completion")
	cases.unbound_background=await execute(packet,true)
	check(cases.unbound_background.calls==0 and cases.unbound_background.built==0 and not cases.unbound_background.errors.is_empty(),"background publication refuses an unbound template before any instance work")
	await clear_packet(packet)

	model=fixture("unadmitted",true);packet=loaded(model)
	check(Assets.cache_packed(model.path,packet.packed,packet.source_digest,packet.candidate),"unrelated ready global owner exists for the missing-snapshot case")
	cases.unadmitted=await execute(packet,false,Callable(),-1,false)
	check(cases.unadmitted.built==0 and not cases.unadmitted.errors.is_empty(),"missing operation snapshot cannot borrow an arbitrary global template")
	check(cases.unadmitted.lookup_fallbacks==0,"missing snapshot cannot reopen a native product outside preparation")
	await clear_packet(packet)
	print("INITIAL_TEMPLATE_SNAPSHOT ",JSON.stringify({"checks":checks,"failures":failures,"cases":cases}))
	quit(0 if failures==0 else 1)
