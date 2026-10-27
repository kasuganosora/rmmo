extends SceneTree
## A fixed production-pool lifecycle: retirement retains the old lease while a
## same-identity replacement is independently admitted, then releases both.
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const PipelineProbe=preload("res://tools/profile_axel_game_pipeline.gd")
var failures:=0
var quiesced:=false
class ConcurrentControl extends RefCounted:
	var mutex:=Mutex.new()
	var stopped:=false
	var started:=Semaphore.new()
	func stop()->void:mutex.lock();stopped=true;mutex.unlock()
	func is_stopped()->bool:mutex.lock();var result:=stopped;mutex.unlock();return result
func check(value:bool,label:String)->void:
	if value:print("PASS ",label)
	else:failures+=1;printerr("FAIL ",label)
func _initialize()->void:run.call_deferred()
func publish(pool:RefCounted)->WeakRef:
	var image:=Image.create_empty(1024,1024,false,Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var weak:WeakRef=weakref(image)
	check(pool.publish("old","test","digest",image),"publish old image")
	return weak
func publish_batch(pool:RefCounted,key:String)->bool:
	var image:=Image.create_empty(512,128,false,Image.FORMAT_RGBA8)
	image.fill(Color.BLUE)
	return pool.publish("batch",key,"digest",image)
static func concurrent_reader(pool:RefCounted,control:ConcurrentControl)->Dictionary:
	var iterations:=0;var failures_:=0
	control.started.post()
	while not control.is_stopped():
		var answer:Dictionary=pool.fetch("other","other","digest",null)
		if answer.get("image")==null:failures_+=1
		var snapshot:Dictionary=pool.snapshot()
		if int(snapshot.retiring_bytes)<0 or int(snapshot.retiring_outputs)<0:failures_+=1
		iterations+=1
	return {"iterations":iterations,"failures":failures_}
func wait_quiesce(queue:Node)->void:
	await queue.quiesce()
	quiesced=true
func blocked_worker_case(plan:Dictionary,row:Dictionary)->void:
	var gate:=Semaphore.new();Retirement.pixel_retirement_test_gate=gate
	var ledger:=Admission.new();ledger.worker_limit=1;ledger.byte_limit=128*1024*1024
	var pool:=Pool.new();pool.admission=ledger
	var offer:Dictionary=pool.offer(plan)
	check(ledger.reserve_bundle("old",{"estimated_bytes":offer.scratch_bytes,"exclusive":false},offer.retained),"blocked case admits producer")
	pool.commit("old",offer);var weak:=publish(pool);ledger.park("old")
	var answer:Dictionary=pool.fetch("old","test","digest",null)
	var borrower:Image=answer.image;answer.clear()
	check(ledger.reserve("busy",{"estimated_bytes":1,"exclusive":false}),"busy job occupies only worker slot")
	pool.release("old");ledger.release("old")
	var retired:Dictionary=pool.snapshot()
	check(retired.outputs==0 and retired.consumers==0 and retired.retained_bytes==0 and retired.retiring_outputs==1,"logical ready and asynchronous retirement are separate")
	await process_frame;await process_frame
	var service:Node=root.get_node_or_null("ResourceRetirement")
	check(service!=null and not service.pending.is_empty() and service.pending[0].worker==null,"retirement waits for unified worker capacity")
	check(ledger.active_workers()==1 and ledger.retiring_pixel_outputs==1,"pending retirement holds bytes but no extra worker")
	ledger.park("busy");ledger.release("busy")
	var deadline:=Time.get_ticks_msec()+5000
	while service.pending[0].worker==null and Time.get_ticks_msec()<deadline:await process_frame
	check(service.pending[0].worker!=null and service.pending[0].worker.is_alive() and ledger.active_workers()==1,"one bounded retirement worker starts and remains blocked")
	ledger.worker_limit=2
	var next_pool:=Pool.new();next_pool.admission=ledger
	var next:Dictionary=next_pool.offer(plan)
	check(next.bindings==offer.bindings and ledger.reserve_bundle("new",{"estimated_bytes":next.scratch_bytes,"exclusive":false},next.retained),"second pool independently admits identical binding")
	next_pool.commit("new",next);ledger.park("new");ledger.release("new")
	check(ledger.reserved_bytes==row.output_bytes*4,"two pools retain independent charges")
	next_pool.cancel("new");next_pool.release("new")
	check(ledger.reserved_bytes==row.output_bytes*2 and ledger.retiring_pixel_outputs==1,"new cancelled generation releases without touching blocked old lease")
	check(not PipelineProbe.texture_pixels_settled(next_pool.snapshot(),ledger),"historical full-ready still observes retiring lease from a replaced pool")
	var queue:=Deferred.new();queue._admission=ledger;root.add_child(queue)
	quiesced=false;wait_quiesce(queue)
	await process_frame
	check(not quiesced and ledger.retiring_pixel_outputs==1,"quiesce waits for the old retirement fence")
	gate.post();deadline=Time.get_ticks_msec()+5000
	while not quiesced and Time.get_ticks_msec()<deadline:await process_frame
	check(quiesced and ledger.reserved_bytes==0 and ledger.retiring_pixel_outputs==0,"quiesce returns only after retirement completes")
	check(PipelineProbe.texture_pixels_settled(next_pool.snapshot(),ledger),"historical full-ready permits completion after old lease retires")
	check(weak.get_ref()!=null and borrower.get_pixel(0,0).is_equal_approx(Color.RED),"external Image borrower remains alive and usable after pool lease completion")
	borrower=null;Retirement.pixel_retirement_test_gate=null;queue.free()
func failed_start_case(plan:Dictionary)->void:
	var ledger:=Admission.new();ledger.byte_limit=128*1024*1024
	var pool:=Pool.new();pool.admission=ledger
	var offer:Dictionary=pool.offer(plan)
	check(ledger.reserve_bundle("old",{"estimated_bytes":offer.scratch_bytes,"exclusive":false},offer.retained),"start-failure case admits image")
	pool.commit("old",offer);publish(pool);ledger.park("old")
	Retirement.pixel_retirement_test_start_failure=true
	pool.release("old");ledger.release("old")
	var deadline:=Time.get_ticks_msec()+5000
	while ledger.reserved_bytes>0 and Time.get_ticks_msec()<deadline:await process_frame
	Retirement.pixel_retirement_test_start_failure=false
	var service:Node=root.get_node("ResourceRetirement")
	check(ledger.reserved_bytes==0 and ledger.retiring_pixel_outputs==0 and int(service.profile.get("pixel_start_failures",0))>0,"failed worker start releases bytes and old charge synchronously")
func service_shutdown_case(plan:Dictionary)->void:
	var ledger:=Admission.new();ledger.worker_limit=1;ledger.byte_limit=128*1024*1024
	var pool:=Pool.new();pool.admission=ledger
	var offer:Dictionary=pool.offer(plan)
	check(ledger.reserve_bundle("old",{"estimated_bytes":offer.scratch_bytes,"exclusive":false},offer.retained),"shutdown case admits image")
	pool.commit("old",offer);publish(pool);ledger.park("old")
	check(ledger.reserve("busy",{"estimated_bytes":1,"exclusive":false}),"shutdown case has occupied worker")
	pool.release("old");ledger.release("old")
	var service:Node=root.get_node("ResourceRetirement");service.free()
	check(ledger.retiring_pixel_outputs==0 and ledger.reserved_bytes==1,"service shutdown drains retirement even when worker slot is occupied")
	ledger.park("busy");ledger.release("busy")
func queue_shutdown_case(plan:Dictionary)->void:
	var queue:=Deferred.new();root.add_child(queue)
	var ledger:RefCounted=queue._admission;ledger.byte_limit=128*1024*1024
	var pool:RefCounted=queue._shared_images;pool.admission=ledger
	var offer:Dictionary=pool.offer(plan)
	check(ledger.reserve_bundle("old",{"estimated_bytes":offer.scratch_bytes,"exclusive":false},offer.retained),"real queue shutdown admits a shared image")
	pool.commit("old",offer);var weak:=publish(pool);ledger.park("old")
	var token:=Drainer.CancelToken.new();token.cancel_callback=pool.cancel.bind("old")
	token.set_meta("prefab_shared_owner",pool);token.set_meta("prefab_shared_release",pool.release.bind("old"));token.set_meta("admission_owner",ledger)
	token.set_meta("admission_release",ledger.release.bind("old"))
	queue._jobs["old"]={"token":token,"result":{}}
	queue.shutdown()
	var clean:bool=ledger.reserved_bytes==0 and ledger.retiring_pixel_outputs==0 and weak.get_ref()==null
	check(clean,"real queue.shutdown synchronously drains image retirements before immediate free")
	queue.free()
	if not clean:
		var deadline:=Time.get_ticks_msec()+5000
		while ledger.retiring_pixel_outputs>0 and Time.get_ticks_msec()<deadline:await process_frame
func fifo_progress_case(plan:Dictionary,busy:bool)->void:
	var ledger:=Admission.new();ledger.worker_limit=1;ledger.byte_limit=128*1024*1024
	var pool:=Pool.new();pool.admission=ledger
	var offer:Dictionary=pool.offer(plan)
	check(ledger.reserve_bundle("old",{"estimated_bytes":offer.scratch_bytes,"exclusive":true},offer.retained),"FIFO case admits exclusive producer")
	pool.commit("old",offer);publish(pool);ledger.park("old")
	pool.release("old")
	if busy:check(ledger.resume_worker("old"),"exclusive slot becomes occupied before pixel retirement")
	# This main-thread retirement ticket follows the blocked pixel ticket. Its
	# completion is the only release of the exclusive/occupied lease.
	var service:Node=root.get_node("ResourceRetirement")
	service.serial+=1;var id:String="test_fifo:%d"%service.serial
	service.pending.append({"kind":"private_array","source_id":id,"values":[1],"on_done":ledger.release.bind("old"),"owner":ledger})
	service.known[id]=true;service.set_process(true)
	var deadline:=Time.get_ticks_msec()+800
	while ledger.reserved_bytes>0 and Time.get_ticks_msec()<deadline:await process_frame
	var progressed:bool=ledger.reserved_bytes==0
	check(progressed,"FIFO advances past blocked pixel ticket and retires exclusive lease (busy=%s)"%busy)
	if not progressed:
		# Restore progress so a failed red test never hangs the harness shutdown.
		ledger.release("old")
		deadline=Time.get_ticks_msec()+5000
		while ledger.reserved_bytes>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(ledger.peak_workers<=ledger.worker_limit,"FIFO progress never exceeds configured worker limit")
func disabled_worker_case(plan:Dictionary)->void:
	var ledger:=Admission.new();ledger.worker_limit=1;ledger.byte_limit=128*1024*1024
	var pool:=Pool.new();pool.admission=ledger
	var offer:Dictionary=pool.offer(plan)
	check(ledger.reserve_bundle("old",{"estimated_bytes":offer.scratch_bytes,"exclusive":false},offer.retained),"disabled case admits producer")
	pool.commit("old",offer);publish(pool);ledger.park("old");pool.release("old");ledger.release("old")
	ledger.worker_limit=0
	var service:Node=root.get_node("ResourceRetirement");var before:int=service.profile.get("pixel_batches",0)
	var deadline:=Time.get_ticks_msec()+800
	while ledger.retiring_pixel_outputs>0 and Time.get_ticks_msec()<deadline:await process_frame
	var progressed:bool=ledger.retiring_pixel_outputs==0
	check(progressed and int(service.profile.get("pixel_batches",0))==before,"disabled loading workers use a bounded main-thread cleanup fallback")
	if not progressed:
		ledger.worker_limit=1;deadline=Time.get_ticks_msec()+5000
		while ledger.retiring_pixel_outputs>0 and Time.get_ticks_msec()<deadline:await process_frame
func batch_case()->void:
	var ledger:=Admission.new();ledger.worker_limit=2;ledger.byte_limit=128*1024*1024
	var pool:=Pool.new();pool.admission=ledger;var rows:Dictionary={}
	for i:int in 129:rows[str(i)]={"path":"batch_%d.png"%i,"width":512,"height":128,"source_bytes":1,"output_bytes":256*1024,"extension":"dds"}
	var offer:Dictionary=pool.offer({"rows":rows})
	check(ledger.reserve_bundle("batch",{"estimated_bytes":offer.scratch_bytes,"exclusive":false},offer.retained),"129 image batch admits under shared byte budget")
	pool.commit("batch",offer)
	for key:String in rows:
		check(publish_batch(pool,key),"batch publish "+key)
	ledger.park("batch");pool.release("batch");ledger.release("batch")
	var service:Node=root.get_node("ResourceRetirement")
	var pixel_counts:Array=[]
	for ticket:Dictionary in service.pending:
		if ticket.get("kind","")=="pixel_buffers":pixel_counts.append(ticket.values.size())
	check(pixel_counts==[128,1] and ledger.retiring_pixel_outputs==129,"129 outputs are bounded into two tickets, not one thread per image")
	var before:int=service.profile.get("pixel_batches",0);var deadline:=Time.get_ticks_msec()+5000
	while ledger.retiring_pixel_outputs>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(ledger.reserved_bytes==0 and int(service.profile.get("pixel_batches",0))-before==2 and ledger.peak_workers<=ledger.worker_limit,"two bounded batches return every lease within worker cap")
func concurrent_profile_case(plan:Dictionary,row:Dictionary)->void:
	var ledger:=Admission.new();ledger.worker_limit=3;ledger.byte_limit=128*1024*1024
	var pool:=Pool.new();pool.admission=ledger
	var old:Dictionary=pool.offer(plan)
	check(ledger.reserve_bundle("old",{"estimated_bytes":old.scratch_bytes,"exclusive":false},old.retained),"concurrent case admits retiring producer")
	pool.commit("old",old);publish(pool);ledger.park("old")
	var other_row:Dictionary=row.duplicate();other_row.path="fixture_other.png"
	var other:Dictionary=pool.offer({"rows":{"other":other_row}})
	check(ledger.reserve_bundle("other",{"estimated_bytes":other.scratch_bytes,"exclusive":false},other.retained),"concurrent case admits live producer")
	pool.commit("other",other)
	var image:=Image.create_empty(1024,1024,false,Image.FORMAT_RGBA8);image.fill(Color.BLUE)
	check(pool.publish("other","other","digest",image),"concurrent case publishes live image")
	image=null;ledger.park("other")
	var control:=ConcurrentControl.new();var worker:=Thread.new()
	var started:bool=worker.start(concurrent_reader.bind(pool,control))==OK
	check(started,"concurrent pool reader starts")
	if not started:
		pool.release("old");ledger.release("old");pool.release("other");ledger.release("other");return
	control.started.wait()
	pool.release("old");ledger.release("old")
	var deadline:=Time.get_ticks_msec()+5000
	while ledger.retiring_pixel_outputs>0 and Time.get_ticks_msec()<deadline:await process_frame
	control.stop();var result:Dictionary=worker.wait_to_finish()
	check(ledger.retiring_pixel_outputs==0 and result.iterations>0 and result.failures==0,"worker fetch/snapshot overlaps locked retirement counters safely")
	pool.release("other");ledger.release("other")
	deadline=Time.get_ticks_msec()+5000
	while ledger.retiring_pixel_outputs>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(ledger.reserved_bytes==0,"concurrent pool releases both generations")
func run()->void:
	check(Retirement._service()!=null,"retirement service is ready before asynchronous contract cases")
	var ledger:=Admission.new();ledger.worker_limit=2;ledger.byte_limit=128*1024*1024
	var pool:=Pool.new();pool.admission=ledger
	var row:Dictionary={"path":"fixture.png","width":1024,"height":1024,"source_bytes":1,"output_bytes":1024*1024*4,"extension":"dds"}
	var plan:Dictionary={"rows":{"test":row}}
	var old:Dictionary=pool.offer(plan)
	check(ledger.reserve_bundle("old",{"estimated_bytes":old.scratch_bytes,"exclusive":false},old.retained),"admit old generation")
	pool.commit("old",old)
	var old_weak:=publish(pool)
	ledger.park("old");pool.release("old");ledger.release("old")
	check(old_weak.get_ref()==null,"Image object retired on main thread")
	check(ledger.reserved_bytes==row.output_bytes*2,"old generation remains charged until worker joins")
	var replacement:Dictionary=pool.offer(plan)
	check(replacement.bindings==old.bindings,"same source retains its logical binding")
	var old_binding:String=old.bindings.test
	check(not ledger._entries.has(old_binding),"retiring lease no longer occupies the logical binding")
	check(ledger.reserve_bundle("new",{"estimated_bytes":replacement.scratch_bytes,"exclusive":false},replacement.retained),"same source can be independently admitted while old pixels retire")
	pool.commit("new",replacement);ledger.park("new");ledger.release("new")
	check(ledger.reserved_bytes==row.output_bytes*4,"old and new generations remain charged together")
	pool.release("new");ledger.release("new")
	var deadline:=Time.get_ticks_msec()+5000
	while ledger.reserved_bytes>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(ledger.reserved_bytes==0,"all retirement callbacks eventually return their leases")
	await blocked_worker_case(plan,row)
	await failed_start_case(plan)
	await fifo_progress_case(plan,false)
	await fifo_progress_case(plan,true)
	await disabled_worker_case(plan)
	await batch_case()
	await concurrent_profile_case(plan,row)
	await queue_shutdown_case(plan)
	service_shutdown_case(plan)
	print("SHARED_PIXEL_RETIREMENT failures=",failures)
	quit(0 if failures==0 else 1)
